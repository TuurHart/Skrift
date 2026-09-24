import Foundation

/// Persisted access to the user-picked Obsidian folder (security-scoped bookmark).
/// The Settings picker calls `setVault`; the publisher resolves it. Mirrors the
/// security-scoped pattern in `AudiobookImporter`/`MemoSaver`.
enum ObsidianVault {
    private static let bookmarkKey = "skrift.obsidian.vaultBookmark"

    /// True once the user has chosen a folder.
    static var isConfigured: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    /// Persist a bookmark to the chosen folder (call from the picker with the picked URL).
    static func setVault(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    /// Resolve the saved bookmark to a (security-scoped) folder URL — the publisher
    /// starts/stops the scope around the write. nil if unset or unresolvable (stale →
    /// re-prompt in the UI).
    static func resolveVault() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// The picked folder's display name for Settings ("Skrift", not a whole path).
    static var displayName: String? { resolveVault()?.lastPathComponent }

    /// Has THIS device ever published this memo into the current folder? (The
    /// lock-flow notice: "it's still in your vault". One helper — the same check
    /// sat twinned in MemosListView and MemoDetailView and drifted apart once.)
    static func hasPublished(_ memoID: UUID) -> Bool {
        guard let vault = resolveVault() else { return false }
        return ExportLedger.default(for: vault).relativePath(for: memoID) != nil
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: bookmarkKey) }
}

/// The result of publishing one memo — the shared engine's outcomes in the
/// coordinator's vocabulary.
enum PublishOutcome: Equatable {
    case written(relativePath: String)
    case skippedUnchanged
    /// The user edited this file in their vault → Skrift backed off, did NOT overwrite.
    case userEdited(relativePath: String)
    /// Filed out of the picked folder → left where the user put it (the folder is an
    /// INBOX; the return path / plugin follows moves later).
    case movedAway(relativePath: String)
    /// Refused: a pre-stamp legacy export or someone else's file at the target.
    case blocked(relativePath: String)
    case noVault
}

/// The iPhone/iPad's Obsidian export, over the SHARED `VaultWriter` (2026-07-26).
///
/// **What changed from the never-shipped v1** (which had no picker, so no vault was
/// ever configured and none of it ever ran on a device):
/// - The picked folder IS the destination. The hardcoded `Skrift/` prefix and the
///   source-keyed subfolders are GONE — pointing the picker at Tuur's `0 Inbox/Skrift`
///   would have produced `…/Skrift/Skrift/Voice Memos/`, a convention imposed on a
///   vault that already has one.
/// - Naming, the edit guard, collisions, atomicity and the ledger are the engine's —
///   identical to the Mac's, file for file. Same note, same filename, either device.
/// - PHOTOS EXPORT: `[[img_NNN]]` markers become real `![[<stem>_NNN.ext]]` embeds
///   with the images copied into `Attachments/` — the phone-side gap that made
///   Mac-only export the rule is closed.
/// - AUDIO EXPORTS into `Voice Memos/` like the Mac (the per-note include-audio
///   toggle stays Mac-only until the field syncs — that chunk is parked in backlog).
/// - The Mac's polish is PREFERRED when it has synced back (`MemoEnhancement`), so
///   the published note upgrades itself once the Mac has done its pass.
///
/// **PRIVACY (hard rule): WRITE-ONLY.** Never scans vault contents — the one read is
/// of the app's OWN candidate path, to judge standing (that's Skrift's own file or a
/// collision, and reading it is what makes never-overwriting possible).
struct ObsidianPublisher {
    /// Returns the vault root, or nil if unconfigured. `manageScope` wraps the write in
    /// `start/stopAccessingSecurityScopedResource` (true in prod; false for temp-dir tests).
    var vaultProvider: () -> URL?
    /// The folder an ARCHIVE destination writes into (archive root + `_ideas` etc). Injected
    /// like `vaultProvider` rather than read from `ArchiveVault` inside, so a test can point
    /// the whole thing at a temp directory — the archive layout is derived data and derived
    /// data has to be proven end-to-end on real files.
    var archiveFolderProvider: (NoteDestination) -> URL? = { ArchiveVault.folder(for: $0) }
    /// The root the security scope belongs to (the bookmarked folder, not the subfolder).
    var archiveScopeRoot: () -> URL? = { ArchiveVault.resolveRoot() }
    var manageScope: Bool
    var author: String
    var peopleProvider: () -> [Person]
    /// Memo↔memo links: look a linked memo up so its export stem can be resolved.
    var memoProvider: (UUID) -> Memo? = { _ in nil }
    /// The Mac's synced polish for a memo, when it exists — preferred over raw.
    var enhancementProvider: (UUID) -> MemoEnhancement? = { _ in nil }
    /// Photo blobs by filename (fetched only when a write actually happens).
    var photosProvider: (UUID) -> [String: Data] = { _ in [:] }
    /// The original audio blob (fetched only when a write actually happens).
    var audioProvider: (UUID) -> Data? = { _ in nil }
    /// Test hook — nil uses the per-root default ledger.
    var ledgerOverride: ExportLedger? = nil

    /// Production publisher over the saved bookmark + live stores.
    @MainActor
    static func live(author: String) -> ObsidianPublisher {
        ObsidianPublisher(
            vaultProvider: { ObsidianVault.resolveVault() },
            manageScope: true,
            author: author,
            peopleProvider: { NamesStore.shared.load().people },
            memoProvider: { id in NotesRepository.shared.memo(id: id) },
            enhancementProvider: { id in NotesRepository.shared.enhancement(forMemo: id) },
            photosProvider: { id in
                var out: [String: Data] = [:]
                for a in NotesRepository.shared.assets(forMemo: id) where a.kind == MemoAsset.Kind.photo {
                    out[a.filename] = a.blob
                }
                return out
            },
            audioProvider: { id in
                NotesRepository.shared.assets(forMemo: id)
                    .first { $0.kind == MemoAsset.Kind.audio }?.blob
            }
        )
    }

    /// Publish one memo through the engine. Idempotent and safe by the engine's rules:
    /// unchanged writes nothing, an edited file backs it off, a filed-away note is not
    /// re-created, and nothing that isn't provably Skrift's is ever overwritten.
    func publish(_ memo: Memo) throws -> PublishOutcome {
        // WHERE and HOW both follow the note's destination. `.personal` is the Obsidian vault
        // and today's layout, unchanged; an archive destination is its folder inside the
        // archive root, written flat (see `ExportProfile`).
        let profile = ExportProfile.of(memo.destination)
        let pickedRoot: URL? = memo.destination.isArchive
            ? archiveFolderProvider(memo.destination)
            : vaultProvider()
        guard let vaultRoot = pickedRoot else { return .noVault }
        // Scope the ROOT the bookmark was made against — for the archive that is the archive
        // root, not the per-destination subfolder we write into.
        let scopeRoot = memo.destination.isArchive ? (archiveScopeRoot() ?? vaultRoot) : vaultRoot
        let scoped = manageScope && scopeRoot.startAccessingSecurityScopedResource()
        defer { if scoped { scopeRoot.stopAccessingSecurityScopedResource() } }

        // Resolve the PICK into the folder Skrift owns — the same call the Mac makes, or the
        // two apps would write to different places in one vault again (iOS at the picked
        // root, the Mac inside `Skrift/`). That divergence is the whole thing we're removing.
        let home = VaultLayout.home(forPicked: vaultRoot, profile: profile)
        let people = peopleProvider()
        let writer = VaultWriter(root: home,
                                 ledger: ledgerOverride ?? .default(for: home),
                                 profile: profile)
        let title = MemoExporter.exportTitle(for: memo, people: people)
        let fallback = memo.audioFilename.isEmpty ? "memo_\(memo.id.uuidString).m4a" : memo.audioFilename

        let relPath: String
        switch writer.assess(id: memo.id, title: title, filenameFallback: fallback,
                             recordedAt: memo.recordedAt) {
        case .refused(let outcome):
            switch outcome {
            case .backedOffUserEdited(let rel): return .userEdited(relativePath: rel)
            case .movedAway(let rel):           return .movedAway(relativePath: rel)
            default:                            return .blocked(relativePath: outcome.relativePath)
            }
        case .proceed(let rel, _):
            relPath = rel
        }
        let stem = ((relPath as NSString).lastPathComponent as NSString).deletingPathExtension

        // Memo-link stems: the ledger's sticky filename first (rename-safe), else the
        // target's derived one — same precedence as the Mac.
        var stems: [UUID: String] = [:]
        for id in MemoLinkSyntax.targets(in: memo.transcript ?? "") {
            if let rel = writer.ledger.relativePath(for: id) {
                stems[id] = ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
            } else if let target = memoProvider(id) {
                stems[id] = VaultName.stem(title: MemoExporter.exportTitle(for: target, people: people),
                                           filename: target.audioFilename)
            }
        }

        let markdown = MemoExporter.markdown(for: memo, people: people, author: author,
                                             enhancement: enhancementProvider(memo.id),
                                             linkStems: stems, profile: profile)
        // Photo markers → real embeds, names derived from the MANIFEST alone so the
        // heavy blobs are only fetched when a write actually happens.
        let manifest = memo.metadata?.imageManifest ?? []
        let (converted, embedNames) = Self.convertPhotoMarkers(
            BodyV2Legacy.shown(markdown).text, manifest: manifest, stem: stem,
            profile: profile)

        // Cheap unchanged check BEFORE touching any blob: candidate vs on-disk,
        // volatile stamp lines aside.
        // Against the HOME, not the pick — the writer writes there, and a pre-check looking
        // somewhere else finds nothing, calls every note changed, and re-fetches every blob
        // on every publish. (It did; `testUnchangedNoteFetchesNoBlobs` caught it.)
        let dest = home.appendingPathComponent(relPath)
        if let existing = VaultWriter.readCoordinated(dest),
           VaultStamp.contentEquivalent(VaultStamp.apply(to: converted, id: memo.id), existing) {
            return .skippedUnchanged
        }

        // A real write — now the blobs.
        let photoBlobs = embedNames.isEmpty ? [:] : photosProvider(memo.id)
        let attachments: [VaultAsset] = embedNames.compactMap { source, embedName in
            photoBlobs[source].map { VaultAsset(name: embedName, source: .data($0)) }
        }
        var audio: VaultAsset?
        if !memo.audioFilename.isEmpty, let blob = audioProvider(memo.id) {
            let ext = (memo.audioFilename as NSString).pathExtension
            audio = VaultAsset(name: stem + "." + (ext.isEmpty ? "m4a" : ext), source: .data(blob))
        }

        let r = try writer.commit(markdown: converted, id: memo.id, relativePath: relPath,
                                  attachments: attachments, audio: audio)
        switch r.outcome {
        case .created, .updated: return .written(relativePath: relPath)
        case .unchanged:         return .skippedUnchanged
        case .backedOffUserEdited(let rel): return .userEdited(relativePath: rel)
        case .movedAway(let rel):           return .movedAway(relativePath: rel)
        default:                 return .blocked(relativePath: r.outcome.relativePath)
        }
    }

    /// Replace `[[img_NNN]]` markers with `![[<stem>_NNN.ext]]` embeds, resolving NNN
    /// through the manifest (the same rule as the app's own body rendering and the
    /// Mac's exporter). Returns the rewritten markdown + (source filename → embed
    /// name) for the markers that resolved; unresolvable markers are DROPPED, never
    /// printed literally.
    static func convertPhotoMarkers(_ markdown: String, manifest: [ImageManifestEntry],
                                    stem: String,
                                    profile: ExportProfile = .obsidian) -> (String, [(String, String)]) {
        guard let rx = try? NSRegularExpression(pattern: "\\[\\[img_(\\d{3})\\]\\]") else {
            return (markdown, [])
        }
        let ns = markdown as NSString
        var replacements: [(NSRange, String)] = []
        var resolved: [(String, String)] = []
        for m in rx.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
            let nnn = ns.substring(with: m.range(at: 1))
            guard let n = Int(nnn), n >= 1, n <= manifest.count else {
                replacements.append((m.range, ""))   // dangling marker → drop
                continue
            }
            let source = manifest[n - 1].filename
            let ext = (source as NSString).pathExtension
            let embedName = "\(stem)_\(nnn).\(ext.isEmpty ? "jpg" : ext)"
            resolved.append((source, embedName))
            // `![[x]]` in a vault, `![](x)` in the archive — a vault-relative embed is exactly
            // what makes a note unreadable anywhere else, and the archive's rule is that an
            // entry has to be able to walk out whole. Obsidian renders both.
            replacements.append((m.range, profile.imageMarkdown(embedName)))
        }
        var out = markdown
        for (range, repl) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            out = (out as NSString).replacingCharacters(in: range, with: repl)
        }
        return (out, resolved)
    }
}
