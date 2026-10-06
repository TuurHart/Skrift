import Foundation

/// Persisted access to the user-picked Obsidian folder (security-scoped bookmark).
/// The Settings picker calls `setVault`; the publisher resolves it. Mirrors the
/// security-scoped pattern in `AudiobookImporter`/`MemoSaver`.
enum ObsidianVault {
    private static let bookmark = ScopedFolderBookmark(key: "skrift.obsidian.vaultBookmark")

    /// True once the user has chosen a folder.
    static var isConfigured: Bool { bookmark.isConfigured }

    /// Persist a bookmark to the chosen folder (call from the picker with the picked URL).
    static func setVault(_ url: URL) throws { try bookmark.set(url) }

    /// Resolve the saved bookmark to a (security-scoped) folder URL — the publisher
    /// starts/stops the scope around the write. nil if unset or unresolvable (stale →
    /// re-prompt in the UI).
    static func resolveVault() -> URL? { bookmark.resolve() }

    /// The picked folder's display name for Settings ("Skrift", not a whole path).
    static var displayName: String? { bookmark.displayName }
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
    /// Refused: someone else's file at the target.
    case blocked(relativePath: String)
    /// Refused: a PRE-STAMP Skrift export sits at the target (Q117 — folded into `.blocked`
    /// before, so the note said "isn't Skrift's" about a file that is).
    case blockedLegacy(relativePath: String)
    case noVault

    /// The engine's outcome in the coordinator's vocabulary. `relativePath` is the file the
    /// engine decided on (what a write names); a refusal names its own, and legacy stays
    /// apart from foreign (different sentences, different remedies).
    init(_ outcome: VaultWriteOutcome, relativePath: String) {
        switch outcome {
        case .created, .updated:            self = .written(relativePath: relativePath)
        case .unchanged:                    self = .skippedUnchanged
        case .backedOffUserEdited(let rel): self = .userEdited(relativePath: rel)
        case .movedAway(let rel):           self = .movedAway(relativePath: rel)
        case .blockedLegacy(let rel):       self = .blockedLegacy(relativePath: rel)
        case .blockedForeign(let rel):      self = .blocked(relativePath: rel)
        }
    }

    /// The export stem of a vault-relative path: its file name without the extension.
    static func stem(ofRelativePath path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// The engine's own outcome for the shared words (`ExportOutcomeCopy`); nil for
    /// `.noVault`, which has no engine decision behind it. `path` is the file the engine
    /// named — `.skippedUnchanged` carries none of its own.
    func vaultOutcome(path: String) -> VaultWriteOutcome? {
        switch self {
        case .written(let rel):         return .created(relativePath: rel)
        case .skippedUnchanged:         return .unchanged(relativePath: path)
        case .userEdited(let rel):      return .backedOffUserEdited(relativePath: rel)
        case .movedAway(let rel):       return .movedAway(relativePath: rel)
        case .blocked(let rel):         return .blockedForeign(relativePath: rel)
        case .blockedLegacy(let rel):   return .blockedLegacy(relativePath: rel)
        case .noVault:                  return nil
        }
    }
}

/// `PublishOutcome` plus what the outcome LINE needs and the outcome itself cannot carry
/// without breaking its one-value cases: the file the engine named and the photos/audio
/// placed beside it (Q117 — the Mac quotes the written stem and counts files, the iPad quoted
/// a display title and counted nothing).
struct PublishReport: Equatable {
    var outcome: PublishOutcome
    /// The vault-relative path the engine decided on; empty for `.noVault`.
    var relativePath: String
    /// Files written beside the note (embedded photos, audio) — 0 unless this was a write.
    var assetCount: Int

    /// The engine's outcome in the shared type, nil for `.noVault`.
    var vaultOutcome: VaultWriteOutcome? { outcome.vaultOutcome(path: relativePath) }

    /// The report for one engine result. A write and an unchanged result name `relativePath`
    /// (the file decided on); only a write counts `assetCount`; a refusal names its own file.
    init(_ result: VaultWriteOutcome, relativePath: String, assetCount: Int = 0) {
        let mapped = PublishOutcome(result, relativePath: relativePath)
        switch mapped {
        case .written:
            self.init(outcome: mapped, relativePath: relativePath, assetCount: assetCount)
        case .skippedUnchanged:
            self.init(outcome: mapped, relativePath: relativePath, assetCount: 0)
        default:
            self.init(outcome: mapped, relativePath: result.relativePath, assetCount: 0)
        }
    }
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
/// - AUDIO EXPORTS into `Voice Memos/` like the Mac, honouring the note's synced
///   include-audio switch (`Memo.includeAudioInExport`, Q186 — set on the Mac).
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
    /// The folder a PORTFOLIO destination writes into (portfolio root + `_ideas` etc). Injected
    /// like `vaultProvider` rather than read from `PortfolioVault` inside, so a test can point
    /// the whole thing at a temp directory — the portfolio layout is derived data and derived
    /// data has to be proven end-to-end on real files.
    var portfolioFolderProvider: (NoteDestination) -> URL? = { PortfolioVault.folder(for: $0) }
    /// The root the security scope belongs to (the bookmarked folder, not the subfolder).
    var portfolioScopeRoot: () -> URL? = { PortfolioVault.resolveRoot() }
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
    /// C63 / C136: the kept source movie of a video note (the file `MemoSaver.keepMovie` wrote,
    /// or the iPad's materialized copy of the synced `video` asset). Only a PORTFOLIO export
    /// asks; nil when the note has none or the file is not on this device.
    var movieProvider: (Memo) -> URL? = { memo in
        guard let name = memo.metadata?.videoFilename, !name.isEmpty else { return nil }
        let url = AppPaths.recordingsDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
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
        try publishReport(memo).outcome
    }

    /// `publish`, with the file the engine named and the photos it placed — what the
    /// outcome line quotes (`ExportOutcomeCopy`).
    func publishReport(_ memo: Memo) throws -> PublishReport {
        // WHERE and HOW both follow the note's destination. `.personal` is the Obsidian vault
        // and today's layout, unchanged; a portfolio destination is its folder inside the
        // portfolio root, written flat (see `ExportProfile`).
        guard let destination = ExportDestinationRoot.resolve(
            for: memo.destination, vault: vaultProvider,
            portfolioFolder: portfolioFolderProvider, portfolioScopeRoot: portfolioScopeRoot) else {
            return PublishReport(outcome: .noVault, relativePath: "", assetCount: 0)
        }
        let profile = destination.profile
        let vaultRoot = destination.picked
        // Scope the ROOT the bookmark was made against — for the portfolio that is the portfolio
        // root, not the per-destination subfolder we write into.
        let scope = destination.openScope(manage: manageScope)
        defer { scope.close() }

        // Resolve the PICK into the folder Skrift owns — the same call the Mac makes, or the
        // two apps would write to different places in one vault again (iOS at the picked
        // root, the Mac inside `Skrift/`). That divergence is the whole thing we're removing.
        let home = VaultLayout.home(forPicked: vaultRoot, profile: profile)
        let people = peopleProvider()
        let writer = VaultWriter(root: home,
                                 ledger: ledgerOverride ?? .default(for: home),
                                 profile: profile)
        // ONE title ladder with the Mac (C25 via `ExportNaming`): user title → the Mac's
        // suggested title → first body line → …, so both name the same note the same file.
        let enhancement = enhancementProvider(memo.id)
        let title = MemoExporter.exportTitle(for: memo, people: people, enhancement: enhancement)
        let fallback = memo.audioFilename.isEmpty ? "memo_\(memo.id.uuidString).m4a" : memo.audioFilename

        let relPath: String
        switch writer.assess(id: memo.id, title: title, filenameFallback: fallback,
                             recordedAt: MemoDate.isUnknown(memo.recordedAt) ? nil : memo.recordedAt) {
        case .refused(let outcome):
            return PublishReport(outcome, relativePath: outcome.relativePath)
        case .proceed(let rel, _):
            relPath = rel
        }
        let stem = PublishOutcome.stem(ofRelativePath: relPath)

        // Memo-link stems: the ledger's sticky filename first (rename-safe), else the
        // target's derived one — same precedence as the Mac.
        var stems: [UUID: String] = [:]
        for id in MemoLinkSyntax.targets(in: memo.transcript ?? "") {
            if let rel = writer.ledger.relativePath(for: id) {
                stems[id] = PublishOutcome.stem(ofRelativePath: rel)
            } else if let target = memoProvider(id) {
                stems[id] = ExportNaming.stem(title: MemoExporter.exportTitle(for: target, people: people,
                                                                              enhancement: enhancementProvider(id)),
                                              filename: target.audioFilename)
            }
        }

        let markdown = MemoExporter.markdown(for: memo, people: people, author: author,
                                             enhancement: enhancement,
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
            return PublishReport(outcome: .skippedUnchanged, relativePath: relPath, assetCount: 0)
        }

        // A real write — now the blobs.
        let photoBlobs = embedNames.isEmpty ? [:] : photosProvider(memo.id)
        let attachments: [VaultAsset] = embedNames.compactMap { source, embedName in
            photoBlobs[source].map { VaultAsset(name: embedName, source: .data($0)) }
        }
        var audio: VaultAsset?
        if memo.includeAudioInExport, !memo.audioFilename.isEmpty, let blob = audioProvider(memo.id) {
            let ext = (memo.audioFilename as NSString).pathExtension
            audio = VaultAsset(name: stem + "." + (ext.isEmpty ? "m4a" : ext), source: .data(blob))
        }

        // C63 / C136 / D172: a video filed Inspiration / Idea / Project brings its movie, beside
        // the note like the picture. The Obsidian vault never gets it (a 200 MB clip has no
        // business in a notes folder), and a Personal note never reaches this branch.
        var documents: [VaultAsset] = []
        if profile == .portfolio, memo.destination.isPortfolio, let movie = movieProvider(memo) {
            documents.append(VaultAsset(name: stem + "." + movie.pathExtension, source: .file(movie)))
        }

        let r = try writer.commit(markdown: converted, id: memo.id, relativePath: relPath,
                                  attachments: attachments, audio: audio, documents: documents)
        return PublishReport(r.outcome, relativePath: relPath, assetCount: attachments.count)
    }

    /// Replace `[[img_NNN]]` markers with this profile's embeds of `<stem>_NNN.ext`, through
    /// the ONE shared converter (`ExportProfile.convertPictureMarkers`, the Mac's exporter
    /// uses it too). Returns the rewritten markdown + (source filename → embed name) for the
    /// markers that resolved; unresolvable markers are DROPPED, never printed literally.
    static func convertPhotoMarkers(_ markdown: String, manifest: [ImageManifestEntry],
                                    stem: String,
                                    profile: ExportProfile = .obsidian) -> (String, [(String, String)]) {
        let r = profile.convertPictureMarkers(markdown, manifest: manifest.map(\.filename), stem: stem)
        return (r.markdown, r.placed.map { ($0.source, $0.embedName) })
    }
}
