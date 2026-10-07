import Foundation
import CryptoKit

// ═══════════════════════════════════════════════════════════════════════════════════
// The ONE vault-write engine (2026-07-26, "make it shared code and then we improve
// both"). Both apps compile this file; each keeps only its ASSET SOURCING (the Mac
// reads a working folder on disk, the phone reads `MemoAsset` blobs) and hands the
// finished markdown here. Everything that made the two exporters diverge — naming,
// collision handling, the edit guard, atomicity, the ledger — exists once.
//
// The doctrine, from the 2026-07-26 design conversation with Tuur:
// - The picked folder IS the destination. No hardcoded `Skrift/` prefix, no
//   source-keyed subfolders — his vault has its own organisation (PARA) and the old
//   phone layout would have nested `Skrift/Skrift/` inside the folder he picked.
// - The folder is an INBOX: notes get filed OUT of it. So identity lives in the file
//   (`VaultStamp`), never in a remembered path — and when a note has left, this
//   engine reports it and steps aside rather than re-creating a duplicate. Following
//   it is the return path's job (chunk 2 / the Obsidian plugin, roadmap i14).
// - Never write over anything that isn't provably ours and untouched. Foreign file →
//   refuse. Pre-stamp legacy export → refuse (no hash ⇒ no way to know if he edited
//   it). User-edited → back off, report; the return path later ADOPTS the edit.
// - The vault lives in iCloud: writes are atomic + NSFileCoordinator'd, and an
//   unchanged note is never rewritten (every needless mtime bump is sync churn, and
//   churn is what breeds iCloud's `(1)` conflict copies).
// ═══════════════════════════════════════════════════════════════════════════════════

/// Per-device record of what this device has written into the picked folder, keyed by
/// memo UUID. LOCAL-ONLY by design (each device has its own folder bookmark, so
/// "exported here" is a per-device fact) — and deliberately DUMB: identity and edit
/// detection live in the file's own stamp, so losing this ledger loses convenience
/// (sticky paths, skip work), never safety. Replaces the phone's `ExportStateStore`,
/// whose stack shipped without a vault picker and so never ran on any device.
final class ExportLedger {
    struct Entry: Codable, Equatable {
        /// Path relative to the picked folder, as last written. Sticky: a retitled
        /// note keeps its file (single owner per file → no `note 2.md`).
        var relativePath: String
        var exportedAt: Date
    }

    private let fileURL: URL
    private var cache: [String: Entry]

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.cache = (try? JSONDecoder().decode([String: Entry].self,
                                                from: Data(contentsOf: fileURL))) ?? [:]
    }

    func entry(for id: UUID) -> Entry? { cache[id.uuidString] }

    func set(_ entry: Entry, for id: UUID) {
        cache[id.uuidString] = entry
        persist()
    }

    func remove(for id: UUID) {
        guard cache.removeValue(forKey: id.uuidString) != nil else { return }
        persist()
    }

    /// Every relative path this device believes it owns — the memo-link resolver reads
    /// stems from here so wikilinks land on the files actually written.
    func relativePath(for id: UUID) -> String? { cache[id.uuidString]?.relativePath }

    /// The ledger for one PICKED FOLDER, keyed by the folder's path — so pointing the
    /// app at a different folder starts a fresh ledger (correct: new destination; the
    /// stamps in the old one still protect it), and tests against temp roots are
    /// isolated by construction instead of by discipline.
    static func `default`(for root: URL) -> ExportLedger {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Skrift", isDirectory: true)
            .appendingPathComponent("export-ledgers", isDirectory: true)
        let key = VaultIdentity.uuid(for: root.standardizedFileURL.path).uuidString
        return ExportLedger(fileURL: dir.appendingPathComponent("\(key).json"))
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

/// Stable identity for things that aren't UUIDs — a demo row's string id, a folder
/// path. SHA-256 folded into UUID shape, so the same input maps to the same UUID on
/// every device forever (a name, not a random draw).
enum VaultIdentity {
    static func uuid(for string: String) -> UUID {
        let digest = SHA256.hash(data: Data(string.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // version 5-ish marker
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// Filename derivation — ONE rule for both apps (they disagreed: the Mac wrote
/// `<title>.md`, the phone `<title>-<id8>.md` into forced subfolders).
enum VaultName {
    /// Profile-aware stem. The portfolio names an entry by WHEN it was captured
    /// (`2026-08-26-142312`); a vault names it by what it is called.
    static func stem(title: String?, filename: String,
                     profile: ExportProfile, recordedAt: Date?) -> String {
        if profile.usesTimestampNames, let recordedAt {
            return ExportProfile.entryStem(for: recordedAt, title: title)
        }
        return stem(title: title, filename: filename)
    }

    /// The note's filename stem: title → filename stem, sanitized for Obsidian.
    /// Obsidian forbids * " \ / < > : | ? in note names (cross-platform sync) and
    /// # ^ [ ] break its link syntax; path separators become "-" (keeps word
    /// boundaries). Capped well past the 80-char derived-title clip so a cap never
    /// bites a real title, but a pasted-in monster can't become a 500-char filename.
    static func stem(title: String?, filename: String) -> String {
        let fallback = (filename as NSString).deletingPathExtension
        let base = (title?.isEmpty == false) ? title! : fallback
        var safe = base.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .filter { !"*\"<>:|?#^[]".contains($0) }
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))   // avoid "Title..md"
        if safe.isEmpty { safe = "note" }
        return String(safe.prefix(120)).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    }

    /// The deterministic second choice when the plain stem is taken by someone else:
    /// suffix the memo's first 8 UUID chars. Same memo → same suffix, every device,
    /// every run — so a collision never fans out into `(1) (2) (3)` copies.
    ///
    /// The portfolio gets a slug-shaped suffix (`a-bench-9e24a49f`) rather than the vault's
    /// `A bench 9E24A49F` — its filenames ARE slugs now that the date has left them, and two
    /// notes called the same thing in one folder is no longer a rare case.
    static func disambiguated(_ stem: String, id: UUID, profile: ExportProfile = .obsidian) -> String {
        let short = id.uuidString.prefix(8)
        return profile.usesTimestampNames
            ? "\(stem)-\(short.lowercased())"
            : "\(stem) \(short)"
    }
}

/// A file to place beside the note — an image or the original audio.
struct VaultAsset {
    enum Source {
        case data(Data)     // phone: MemoAsset blobs
        case file(URL)      // Mac: the working folder's original media
    }
    var name: String
    var source: Source
}

/// What one write attempt did — or why it refused. Every refusal names the file it
/// refused over, so the UI can say something true instead of "export failed".
enum VaultWriteOutcome: Equatable {
    case created(relativePath: String)
    case updated(relativePath: String)
    /// Identical content already there (stamp's volatile lines aside) — nothing
    /// written, no mtime churn for iCloud to sync.
    case unchanged(relativePath: String)
    /// Ours, but edited in the vault since we wrote it. Their version is the newer
    /// intent — left alone. (The return path will ADOPT the edit; today it stops.)
    case backedOffUserEdited(relativePath: String)
    /// Our ledger says we wrote it here, and it's gone — filed out of the inbox, or
    /// deleted. Stepping aside rather than re-creating a duplicate is the point of
    /// the inbox doctrine; the return path / plugin follows it later.
    case movedAway(relativePath: String)
    /// A PRE-STAMP Skrift export sits at the target (the `lastTouched:` tell, no id).
    /// No hash ⇒ no way to know whether the user edited it ⇒ never overwrite, and
    /// never write a suffixed twin beside it either — that would duplicate every
    /// legacy note on its first re-export.
    case blockedLegacy(relativePath: String)
    /// A file that isn't Skrift's occupies every candidate path. Never touched.
    case blockedForeign(relativePath: String)

    /// The path this outcome is about — for messages ("left “X” alone") and for
    /// callers that record where the note lives.
    var relativePath: String {
        switch self {
        case .created(let p), .updated(let p), .unchanged(let p),
             .backedOffUserEdited(let p), .movedAway(let p),
             .blockedLegacy(let p), .blockedForeign(let p):
            return p
        }
    }

    /// Did the vault end this attempt holding the note's current content? (created /
    /// updated / unchanged — the outcomes a caller may mark "exported" on.)
    var isWrittenOrCurrent: Bool {
        switch self {
        case .created, .updated, .unchanged: return true
        default: return false
        }
    }
}

/// The engine. `assess` FIRST — it decides whether a write will happen and where,
/// so callers do zero asset work (image conversion, blob reads) for a note that
/// gets refused; then `commit` stamps and writes.
struct VaultWriter {
    /// The user-picked destination folder (the Mac's noteFolder / the phone's
    /// security-scoped bookmark). The caller owns scope start/stop.
    var root: URL
    /// Subfolders INSIDE the home folder. NOT configurable since 2026-08-14 (signed mock
    /// `vault-folder-model.html`): they were two free-text settings on the Mac and hardcoded
    /// defaults on iOS, so the same vault got `1 Recordings`/`0 Images` from one device and
    /// `Voice Memos`/`Attachments` from another. Skrift owns its own house now.
    let attachmentsFolder = VaultLayout.images
    let audioFolder = VaultLayout.audio
    /// PDFs and other shared documents. `MemoAsset.Kind.document` has reached the Mac since
    /// the 3b capture work and the exporter simply never wrote it to the vault.
    let documentsFolder = VaultLayout.documents
    var ledger: ExportLedger
    /// HOW to lay this note out — see `ExportProfile`. Defaults to today's behaviour, so a
    /// caller that has not been taught about destinations writes exactly what it always did.
    var profile: ExportProfile = .obsidian
    let now: () -> Date = Date.init

    // ── Phase 1: where would this note go, and may we write there? ──

    enum Assessment: Equatable {
        /// Go ahead: build the markdown against this stem and call `commit`.
        case proceed(relativePath: String, creates: Bool)
        case refused(VaultWriteOutcome)
    }

    func assess(id: UUID, title: String?, filenameFallback: String,
                recordedAt: Date? = nil) -> Assessment {
        let fm = FileManager.default

        // A path we've written before is sticky — the file keeps its name across
        // retitles, and its fate is judged where it stands.
        if let known = ledger.entry(for: id) {
            let dest = root.appendingPathComponent(known.relativePath)
            if fm.fileExists(atPath: dest.path) {
                return judge(existingAt: known.relativePath, id: id)
            }
            // Gone from where we wrote it — MOVED or DELETED, and those want opposite
            // answers. The stamp is what tells them apart (2026-08-28): if the note is still
            // somewhere under this folder it was filed out, which is the inbox working as
            // intended, and Skrift steps aside. If it is nowhere, it was deleted, and
            // refusing forever is just a dead end — Tuur deleted his test exports, edited the
            // note, re-exported, and got "left where you put it" with no way back.
            if VaultStamp.locate(id: id, under: root, fileManager: fm) != nil {
                return .refused(.movedAway(relativePath: known.relativePath))
            }
            ledger.remove(for: id)   // the note it pointed at does not exist; start over
        }

        // First contact from this device. Try the plain stem, then the deterministic
        // id-suffixed one. Two candidates is enough: the suffix is unique per memo.
        let stem = VaultName.stem(title: title, filename: filenameFallback,
                                  profile: profile, recordedAt: recordedAt)
        for candidate in [stem, VaultName.disambiguated(stem, id: id, profile: profile)] {
            let rel = candidate + ".md"
            let dest = root.appendingPathComponent(rel)
            guard fm.fileExists(atPath: dest.path) else {
                return .proceed(relativePath: rel, creates: true)
            }
            let verdict = judge(existingAt: rel, id: id)
            guard case .refused(let outcome) = verdict else {
                // Ours (same id) → adopt this path: a fresh install / wiped ledger
                // reconnects to its own file instead of writing a twin.
                return verdict
            }
            switch outcome {
            case .backedOffUserEdited:
                return verdict   // ours, edited → this IS the answer, not a collision
            case .blockedLegacy:
                // A pre-stamp export owns this name. Do NOT sidestep to the suffixed
                // name — that would mint a duplicate for every legacy note.
                return verdict
            default:
                continue   // someone else's file / another note's — try the suffix
            }
        }
        return .refused(.blockedForeign(relativePath: stem + ".md"))
    }

    /// Judge the file that already exists at `rel` against memo `id`.
    private func judge(existingAt rel: String, id: UUID) -> Assessment {
        let dest = root.appendingPathComponent(rel)
        guard let text = Self.readCoordinated(dest) else {
            // Unreadable = unknowable. Refuse rather than overwrite blind.
            return .refused(.blockedForeign(relativePath: rel))
        }
        switch VaultStamp.standing(of: text) {
        case .absent:
            return .proceed(relativePath: rel, creates: true)
        case .untouched(let marks):
            return marks.id == id
                ? .proceed(relativePath: rel, creates: false)
                : .refused(.blockedForeign(relativePath: rel))
        case .userEdited(let marks):
            return marks.id == id
                ? .refused(.backedOffUserEdited(relativePath: rel))
                : .refused(.blockedForeign(relativePath: rel))
        case .foreign:
            return VaultStamp.looksLegacySkrift(text)
                ? .refused(.blockedLegacy(relativePath: rel))
                : .refused(.blockedForeign(relativePath: rel))
        }
    }

    // ── Phase 2: stamp + write ──

    struct Result: Equatable {
        var outcome: VaultWriteOutcome
        var markdownURL: URL
        var audioURL: URL?
    }

    /// Write `markdown` (pre-stamp) for `id` at the assessed path. Skips everything —
    /// file AND assets — when the content is equivalent to what's already there.
    func commit(markdown: String, id: UUID, relativePath: String,
                attachments: [VaultAsset] = [], audio: VaultAsset? = nil,
                documents: [VaultAsset] = []) throws -> Result {
        let dest = root.appendingPathComponent(relativePath)

        // WHERE the media goes. The vault keeps its subfolders (`Images/`, `Recordings/`,
        // `Documents/`) so a note's attachments stay out of the way of a folder you file out
        // of. The portfolio puts them BESIDE the note, sharing its basename — that pair is what
        // makes an entry able to walk out whole. Needed BEFORE the stamp now (below), not just
        // at write time, so a name collision can be resolved before the embed is frozen.
        let beside = dest.deletingLastPathComponent()
        func folder(_ named: String) -> URL {
            profile.assetsBesideNote ? beside : root.appendingPathComponent(named, isDirectory: true)
        }

        // C58/C56: a caller compiles its embed against a PREFERRED name, but only the vault
        // on disk can say whether that name is free — a foreign file may already own it, in
        // which case the write lands under the id8-disambiguated name instead. Resolve that
        // HERE, before the stamp, and patch any embed the caller wrote for the old name to
        // match. This is the one documented patch point (C56) — everything downstream
        // (`writeAsset`) writes under the name already settled here, never re-decides it.
        var markdown = markdown
        var resolvedAttachments: [VaultAsset] = []
        for asset in attachments {
            let owned = VaultAttachmentOwnership.settledName(for: asset, into: folder(attachmentsFolder), id: id)
            if owned != asset.name {
                markdown = markdown
                    .replacingOccurrences(of: "[[\(asset.name)]]", with: "[[\(owned)]]")
                    .replacingOccurrences(of: "](\(asset.name))", with: "](\(owned))")
            }
            resolvedAttachments.append(VaultAsset(name: owned, source: asset.source))
        }

        let stamped = VaultStamp.apply(to: markdown, id: id, touchedAt: now())

        let existing = Self.readCoordinated(dest)
        if let existing, VaultStamp.contentEquivalent(stamped, existing) {
            return Result(outcome: .unchanged(relativePath: relativePath),
                          markdownURL: dest, audioURL: nil)
        }

        try Self.writeAtomic(Data(stamped.utf8), to: dest)
        ledger.set(.init(relativePath: relativePath, exportedAt: now()), for: id)

        // Assets ride along on a real write. A failed asset is never fatal — a note
        // without its image beats no note.
        for a in resolvedAttachments { _ = Self.writeAsset(a, into: folder(attachmentsFolder), id: id) }
        for d in documents { _ = Self.writeAsset(d, into: folder(documentsFolder), id: id) }
        var audioURL: URL?
        if let audio {
            let dir = folder(audioFolder)
            if Self.writeAsset(audio, into: dir, id: id) {
                audioURL = dir.appendingPathComponent(audio.name)
            }
        }

        let created = existing == nil
        return Result(outcome: created ? .created(relativePath: relativePath)
                                       : .updated(relativePath: relativePath),
                      markdownURL: dest, audioURL: audioURL)
    }

    // ── IO (coordinated: the vault lives in iCloud) ──

    /// Atomic + NSFileCoordinator'd, so Obsidian/iCloud never observe a half-written
    /// file — the phone's proven pattern, now the ONLY write path. (The Mac used a
    /// bare `Data.write`, which is exactly the kind of writer that seeds iCloud's
    /// documented duplicate/conflict behavior.)
    static func writeAtomic(_ data: Data, to dest: URL) throws {
        try coordinatedWrite(to: dest) { try data.write(to: $0, options: .atomic) }
    }

    /// The one `NSFileCoordinator` write dance: make the parent folder, coordinate a
    /// `.forReplacing` write at `dest`, run `body` on the coordinated URL, rethrow either error.
    static func coordinatedWrite(to dest: URL, _ body: (URL) throws -> Void) throws {
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: dest, options: .forReplacing, error: &coordError) { url in
            do { try body(url) } catch { writeError = error }
        }
        if let coordError { throw coordError }
        if let writeError { throw writeError }
    }

    static func readCoordinated(_ url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var coordError: NSError?
        var data: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { u in
            data = try? Data(contentsOf: u)
        }
        return data.flatMap { String(data: $0, encoding: .utf8) }
    }

    /// `id` disambiguates a foreign collision (C58) — see `VaultAttachmentOwnership`.
    /// R7/R77: neither source kind may clobber an existing vault attachment we don't own.
    private static func writeAsset(_ asset: VaultAsset, into dir: URL, id: UUID) -> Bool {
        VaultAttachmentOwnership.place(asset.source, preferredName: asset.name, into: dir, id: id) != nil
    }
}

extension VaultAsset.Source {
    /// Is the file already at `url` byte-identical to this source (so ours, a safe no-op)?
    fileprivate func isIdentical(to url: URL, fm: FileManager) -> Bool {
        switch self {
        case .data(let data):
            return (try? Data(contentsOf: url)) == data
        case .file(let src):
            guard let sizeA = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int,
                  let sizeB = (try? fm.attributesOfItem(atPath: src.path))?[.size] as? Int,
                  sizeA == sizeB else { return false }
            guard let da = try? Data(contentsOf: url), let db = try? Data(contentsOf: src) else { return false }
            return da == db
        }
    }

    /// Put these bytes at `dest` through the coordinated write path.
    fileprivate func write(to dest: URL) throws {
        switch self {
        case .data(let data): try VaultWriter.writeAtomic(data, to: dest)
        case .file(let src):  try VaultWriter.coordinatedWrite(to: dest) { try FileManager.default.copyItem(at: src, to: $0) }
        }
    }
}

/// The ownership rule attachments must obey too (C58): never remove or clobber a vault
/// file this device doesn't own. There's no text stamp to read for a binary attachment
/// (unlike `VaultStamp` for markdown), so ownership is judged the only way it can be:
/// byte-identical to what we're about to write means ours already, a safe no-op; anything
/// else already sitting at the target name is untouched, and the incoming file is
/// written under a disambiguated name instead (the same twin-on-collision answer C54
/// gives a foreign markdown file) so no attachment lane ever deletes a file it
/// doesn't own.
enum VaultAttachmentOwnership {
    /// Copies `src` into `dir`, choosing an ownership-safe name first. Returns the URL
    /// actually written (existing untouched file gives the same URL, nothing copied), or nil on
    /// a genuine I/O failure.
    @discardableResult
    static func copyOwned(from src: URL, preferredName: String, into dir: URL, id: UUID,
                          fileManager fm: FileManager = .default) -> URL? {
        place(.file(src), preferredName: preferredName, into: dir, id: id, fileManager: fm)
    }

    /// Same rule for in-memory bytes (the phone's `MemoAsset` blobs, no source file on
    /// disk to hand `copyOwned`). Never removes an existing file.
    @discardableResult
    static func writeOwned(_ data: Data, preferredName: String, into dir: URL, id: UUID,
                           fileManager fm: FileManager = .default) -> URL? {
        place(.data(data), preferredName: preferredName, into: dir, id: id, fileManager: fm)
    }

    /// The one place-bytes step: resolve an ownership-safe name, then write unless that
    /// name already holds identical bytes. This resolve is NOT redundant with `settledName`
    /// (commit's pre-stamp pass): it is the only guard against a clobber if the settled
    /// name was taken between the two.
    static func place(_ source: VaultAsset.Source, preferredName: String, into dir: URL, id: UUID,
                      fileManager fm: FileManager = .default) -> URL? {
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = ownedName(preferred: preferredName, in: dir, id: id, fileManager: fm) {
            source.isIdentical(to: $0, fm: fm)
        }
        let dest = dir.appendingPathComponent(name)
        guard !fm.fileExists(atPath: dest.path) else { return dest }   // already correct, no-op
        do { try source.write(to: dest); return dest } catch { return nil }
    }

    /// `preferred` when nothing occupies it yet, or when what's there `isIdentical` (ours
    /// already, unchanged). Otherwise the name is left completely alone and a disambiguated
    /// one (` <id8>` suffix, before the extension) is returned instead.
    static func ownedName(preferred: String, in dir: URL, id: UUID,
                          fileManager fm: FileManager = .default,
                          isIdentical: (URL) -> Bool) -> String {
        let dest = dir.appendingPathComponent(preferred)
        guard fm.fileExists(atPath: dest.path) else { return preferred }
        return isIdentical(dest) ? preferred : disambiguated(preferred, id: id)
    }

    /// The name an attachment will actually land under, for `commit` to patch the embed
    /// BEFORE the stamp. Iterates `ownedName` to a fixed point so it agrees with `place`'s
    /// own resolve even when the id8 name is itself occupied by different bytes (it used to
    /// stop at one step, so the embed said `X id8.png` while `place` wrote `X id8 id8.png`).
    static func settledName(for asset: VaultAsset, into dir: URL, id: UUID,
                            fileManager fm: FileManager = .default) -> String {
        var name = asset.name
        for _ in 0..<4 {
            let next = ownedName(preferred: name, in: dir, id: id, fileManager: fm) {
                asset.source.isIdentical(to: $0, fm: fm)
            }
            if next == name { break }
            name = next
        }
        return name
    }

    private static func disambiguated(_ preferredName: String, id: UUID) -> String {
        let stem = (preferredName as NSString).deletingPathExtension
        let ext = (preferredName as NSString).pathExtension
        let short = id.uuidString.prefix(8)
        return ext.isEmpty ? "\(stem) \(short)" : "\(stem) \(short).\(ext)"
    }
}
