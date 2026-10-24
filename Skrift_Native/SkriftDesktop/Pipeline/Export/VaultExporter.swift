import Foundation
import os
import SwiftData

/// Writes a compiled note to the Obsidian vault: the `.md` (frontmatter + body) at
/// the vault root, the original audio into the audio subfolder, and any captured
/// images into the attachments subfolder. Pure (ExportV2 + FileManager), so the
/// coordinator and the `-runfile` harness share it and it host-tests.
enum VaultExporter {
    struct Result: Equatable {
        /// What the shared engine decided — created/updated/unchanged, or WHY it
        /// refused (edited in the vault / filed away / legacy / foreign). Callers
        /// message from this instead of pretending every non-throw was a write.
        let outcome: VaultWriteOutcome
        let markdownURL: URL
        let audioURL: URL?
        let imageCount: Int
        /// C163: `outcome` is about the OLD file a destination move left, and the move was refused.
        var refusedMove = false
        /// C158: vault pictures this export removed because the body no longer shows them.
        var removedPictures: [String] = []
    }

    /// When this note was CAPTURED — what the portfolio names an entry by. The phone's
    /// `recordedAt` rides the metadata blob; `uploadedAt` is the fallback for a row that
    /// never carried one (a local import). Never "now": re-exporting must not rename a file.
    static func captureDate(for pf: PipelineFile) -> Date {
        let input = pf.compilerInput
        if let iso = input.metadata?.recordedAt ?? input.rawRecordedAt,
           let d = ISO8601.date(from: iso) { return d }
        return pf.uploadedAt
    }

    /// The `source.<ext>` movie `IngestService` keeps beside the extracted audio, if this note
    /// came from a video. nil for everything else, and for videos ingested before Skrift
    /// started keeping them.
    static func keptSourceVideo(in workingFolder: URL) -> URL? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: workingFolder.path) else { return nil }
        return names.first { ($0 as NSString).deletingPathExtension == "source" }
            .map { workingFolder.appendingPathComponent($0) }
    }

    /// The portfolio folder for a destination, from the Mac's settings — `<portfolioRoot>/_ideas`
    /// etc. Empty when no portfolio root is picked here, which `export` turns into
    /// `noPortfolioFolder` (not `noVault`: the user's fix is a different Settings row).
    static func portfolioFolder(for destination: NoteDestination, settings: AppSettings) -> String {
        let root = settings.portfolioRoot.trimmingCharacters(in: .whitespaces)
        guard !root.isEmpty, let sub = destination.portfolioFolder else { return "" }
        return (root as NSString).appendingPathComponent(sub)
    }

    /// Where a note's images go: the vault's `Images/` folder, or — for the portfolio —
    /// the note's OWN folder, so the pair travels together.
    static func imageDestination(vaultURL: URL, relativePath: String,
                                 profile: ExportProfile) -> URL {
        profile.assetsBesideNote
            ? vaultURL.appendingPathComponent(relativePath).deletingLastPathComponent()
            : vaultURL.appendingPathComponent(VaultLayout.images, isDirectory: true)
    }

    /// The folder Skrift owns for this note's destination, nil when none is picked. Resolves
    /// the PICK the way `export` always has: point at `0 Inbox` and Skrift makes
    /// `0 Inbox/Skrift`; point at `0 Inbox/Skrift` and it uses that, unchanged — both of
    /// Tuur's habits land in the same place and nothing in the vault moves.
    static func exportHome(for pf: PipelineFile, settings: AppSettings) -> URL? {
        let picked: String = pf.destination.isPortfolio
            ? portfolioFolder(for: pf.destination, settings: settings)
            : settings.noteFolder.trimmingCharacters(in: .whitespaces)
        guard !picked.isEmpty else { return nil }
        return VaultLayout.home(forPicked: URL(fileURLWithPath: picked),
                                profile: ExportProfile.of(pf.destination))
    }

    /// The folder Skrift owns for the destination this note is NOT in now — where an export
    /// from before a re-file lives. nil when that destination has no folder picked here, or
    /// when both destinations resolve to the same folder (then there is nothing to move).
    static func otherHome(for pf: PipelineFile, settings: AppSettings) -> URL? {
        let other: NoteDestination = pf.destination.isPortfolio ? .personal : .portfolio
        let probe = PipelineFile(id: pf.id, filename: pf.filename)
        probe.destination = other
        guard let otherHome = exportHome(for: probe, settings: settings),
              otherHome.standardizedFileURL != exportHome(for: pf, settings: settings)?.standardizedFileURL
        else { return nil }
        return otherHome
    }

    enum MoveStep {
        case none
        case removeOld(relativePath: String, home: URL, ledger: ExportLedger)
        case refused(Result)
    }

    /// C163: the destination-move step of `export`, judged before anything is written.
    /// Only a row whose last export (`pf.exported`) lies under the other home has anything to
    /// move, so a run without a re-filed note never decodes that home's ledger (Q365: one
    /// decode and one write per run). The ledger is the run's when it already has it open, else
    /// a standalone one that writes only when `removeOld` changes it.
    static func destinationMove(_ pf: PipelineFile, id: UUID, settings: AppSettings,
                                session: ExportSession?) -> MoveStep {
        guard let old = otherHome(for: pf, settings: settings), let last = pf.exported,
              URL(fileURLWithPath: last).standardizedFileURL.path.hasPrefix(old.standardizedFileURL.path + "/")
        else { return .none }
        let ledger = session?.ledgerIfOpen(for: old) ?? .default(for: old)
        switch DestinationMove.verdict(id: id, oldHome: old, ledger: ledger) {
        case .nothingThere:
            return .none
        case .remove(let rel):
            return .removeOld(relativePath: rel, home: old, ledger: ledger)
        case .refuse(let outcome):
            return .refused(Result(outcome: outcome, markdownURL: old.appendingPathComponent(outcome.relativePath),
                                   audioURL: nil, imageCount: 0, refusedMove: true))
        }
    }

    /// The pick-time check (the Mac's destination row): may `pf` be re-filed to `destination`?
    /// nil = yes (nothing exported, or the old file can go); else the shared refusal sentence.
    static func destinationChangeRefusal(_ pf: PipelineFile, to destination: NoteDestination,
                                         settings: AppSettings) -> String? {
        guard destination != pf.destination, pf.exportStatus == .done else { return nil }
        let probe = PipelineFile(id: pf.id, filename: pf.filename)
        probe.destination = destination
        guard let old = otherHome(for: probe, settings: settings) else { return nil }
        guard case .refuse(let outcome) = DestinationMove.verdict(id: ledgerID(for: pf), oldHome: old,
                                                                 ledger: .default(for: old)) else { return nil }
        return ExportOutcomeCopy.destinationMoveRefused(outcome, from: pf.destination, to: destination).text
    }

    /// The id the stamp and the export ledger key this row on. A synced memo's row id IS the
    /// memo UUID; demo/synthetic rows get a stable derived one so the stamp works for every
    /// row, forever.
    static func ledgerID(for pf: PipelineFile) -> UUID {
        UUID(uuidString: pf.id) ?? VaultIdentity.uuid(for: pf.id)
    }

    /// The Process / Export / Re-export inputs for a row, through the ONE shared rule
    /// (`NoteWorkState.Inputs`) the iPad uses: the synced `MemoEnhancement` (when `cloud` can
    /// see one) plus this row's own polish, and the export ledger of the note's destination
    /// folder rather than the local `steps.export` flag.
    static func workInputs(for pf: PipelineFile, cloud: ModelContext?,
                           settings: AppSettings, session: ExportSession? = nil) -> NoteWorkState.Inputs {
        var enhancement: MemoEnhancement?
        if let cloud, let memo = ReconcileV2.Writers.resolve(pf, in: cloud) {
            let memoID = memo.id
            enhancement = (try? cloud.fetch(FetchDescriptor<MemoEnhancement>(
                predicate: #Predicate { $0.memoID == memoID })))?.first
        }
        let ledger = exportHome(for: pf, settings: settings).map {
            session?.ledger(for: $0) ?? ExportLedger.default(for: $0)
        }
        return .from(ledgerID: ledgerID(for: pf), enhancement: enhancement, ledger: ledger,
                     local: .init(passRan: pf.steps.enhance == .done,
                                  copyedit: pf.enhancedCopyedit, title: pf.enhancedTitle,
                                  summary: pf.enhancedSummary))
    }

    /// A refusal from the shared gate (`ExportGate`, Q156). The cases the write path itself
    /// throws keep their names; the words are `ExportOutcomeCopy.refusal`, never typed here.
    enum ExportError: LocalizedError, Equatable {
        case noVault
        case noPortfolioFolder
        case lockedNote
        case twoVersions
        /// Any other gate (trashed / unrated / nothing / unprocessed), for callers that ask the
        /// `full` scope and want to throw.
        case refused(ExportGate.Failure)

        init(_ failure: ExportGate.Failure) {
            switch failure {
            case .noVaultFolder: self = .noVault
            case .noPortfolioFolder: self = .noPortfolioFolder
            case .locked: self = .lockedNote
            case .twoVersions: self = .twoVersions
            default: self = .refused(failure)
            }
        }

        var failure: ExportGate.Failure {
            switch self {
            case .noVault: return .noVaultFolder
            case .noPortfolioFolder: return .noPortfolioFolder
            case .lockedNote: return .locked
            case .twoVersions: return .twoVersions
            case .refused(let f): return f
            }
        }

        var errorDescription: String? { ExportOutcomeCopy.refusal(failure, device: .mac).text }
    }

    /// The gate's inputs for a Mac row. `processed` is the caller's: the `full` scope needs the
    /// synced `MemoEnhancement` (`workInputs(...).hasPolish`); the `engine` scope never asks.
    static func gateFacts(for pf: PipelineFile, settings: AppSettings, processed: Bool) -> ExportGate.Facts {
        let body = (pf.sanitised ?? pf.transcript ?? "")
        return ExportGate.Facts(
            destinationIsPortfolio: pf.destination.isPortfolio,
            folderConfigured: exportHome(for: pf, settings: settings) != nil,
            trashed: pf.deletedAt != nil,
            locked: pf.locked,
            twoVersionsHeld: EditConflictHold.isHeld(pf.id),
            rated: NoteConsent.isRated(pf),
            hasContent: !body.isEmpty || !pf.exportTitle.isEmpty,
            processed: processed)
    }

    /// What a PERSON's Export press (and a re-export after a sync) must pass: every gate, the
    /// same predicate the iPad runs. nil = may export.
    static func fullGateFailure(for pf: PipelineFile, cloud: ModelContext?,
                                settings: AppSettings, session: ExportSession? = nil) -> ExportGate.Failure? {
        let processed = workInputs(for: pf, cloud: cloud, settings: settings, session: session).hasPolish
        return ExportGate.check(gateFacts(for: pf, settings: settings, processed: processed),
                                device: .mac)
    }

    /// Places one picture/attachment: `(source file, preferred name, folder) -> URL written`
    /// (nil = could not place, the embed is dropped). The real one is `copyOwned`; the Q365
    /// skip check passes one that only records where each would go.
    typealias Placer = (_ source: URL, _ preferredName: String, _ into: URL) -> URL?

    /// The real placer: the C58 ownership-safe copy.
    static func owned(_ id: UUID) -> Placer {
        { src, name, dir in VaultAttachmentOwnership.copyOwned(from: src, preferredName: name, into: dir, id: id) }
    }

    /// Stat-only (Q365): is the vault copy at `vaultCopy` plausibly the one we placed from
    /// `source` — present, the same size, and not modified after our last write of the note?
    /// False sends the export down the full path (the byte compare decides there).
    static func assetLooksCurrent(source: URL, vaultCopy: URL, writtenAt: Date) -> Bool {
        let fm = FileManager.default
        guard let dest = try? fm.attributesOfItem(atPath: vaultCopy.path),
              let src = try? fm.attributesOfItem(atPath: source.path),
              let destSize = dest[.size] as? Int, let srcSize = src[.size] as? Int, destSize == srcSize,
              let modified = dest[.modificationDate] as? Date else { return false }
        return modified <= writtenAt.addingTimeInterval(1)
    }

    /// The exported note's filename stem — `enhancedTitle` (else the file stem), sanitized
    /// for Obsidian. ONE derivation, used by the export write AND the memo-link resolver
    /// (`[[memo:UUID|Title]]` → `[[<stem>|Title]]`), so links always match the real file.
    ///
    /// Obsidian forbids * " \ / < > : | ? in note names (cross-platform sync)
    /// and # ^ [ ] break its link syntax. Path separators become "-" (keeps
    /// word boundaries); the rest are stripped, then doubled spaces collapsed
    /// — Gemma loves "Title: Subtitle", which must not become "Title- Subtitle".
    static func noteStem(_ pf: PipelineFile) -> String {
        VaultName.stem(title: pf.exportTitle, filename: pf.filename)
    }

    /// The note's picture manifest as ordered filenames: `image_manifest.json` beside
    /// `images/` (written by phone sync, uploads, video and mixed-drop ingest), else the
    /// sorted `images/` listing for a folder that predates manifests. Empty when neither.
    static func pictureManifest(imagesDir: URL) -> [String] {
        let manifestURL = imagesDir.deletingLastPathComponent().appendingPathComponent("image_manifest.json")
        if let data = try? Data(contentsOf: manifestURL),
           let entries = try? JSONDecoder().decode([ImageManifestEntry].self, from: data) {
            return entries.map(\.filename)
        }
        return ((try? FileManager.default.contentsOfDirectory(atPath: imagesDir.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }

    /// A copy failure LOGGED — a bare `try?` made a missing attachment indistinguishable
    /// from success (the embed got written either way).
    private static func logCopyFailure(name: String) {
        Logger(subsystem: "com.skrift.desktop", category: "export")
            .error("attachment copy FAILED \(name, privacy: .public) — embed will dangle")
    }

    /// LEGACY (pre-Wave-2) captures: copy images from the capture's `images/` folder to
    /// the vault attachments folder under their original names — no `[[img_NNN]]` markers
    /// in the body, the capture block pins a `![[filename]]` embed instead. Wave-2
    /// captures carry markers and go through export v2's picture placing like memos. A name
    /// collision with a file this device doesn't own (C58) never deletes it — ours lands
    /// under a disambiguated name instead, and the pinned embed is rewritten to match.
    static func copyCaptureFolderImages(imagesDir: URL, into attDir: URL, markdown: String, id: UUID,
                                        place: Placer? = nil) -> (String, Int) {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
        guard !files.isEmpty else { return (markdown, 0) }
        var copied = 0
        var out = markdown
        for file in files {
            let originalName = file.lastPathComponent
            guard let written = (place ?? owned(id))(file, originalName, attDir) else {
                Self.logCopyFailure(name: originalName); continue
            }
            copied += 1
            if written.lastPathComponent != originalName {
                // The pinned embed the compile already baked in references the ORIGINAL
                // name — a foreign file occupied it, so keep the reference pointed at what
                // we actually wrote.
                out = out.replacingOccurrences(of: "[[\(originalName)]]", with: "[[\(written.lastPathComponent)]]")
                    .replacingOccurrences(of: "](\(originalName))", with: "](\(written.lastPathComponent))")
            }
        }
        return (out, copied)
    }

    /// Copy an Apple Note's `Attachments/` files referenced as `![alt](Attachments/x)`
    /// or `[alt](Attachments/x)` into `attDir`, and convert the refs to Obsidian
    /// embeds/links (`![[x]]` / `[[x]]`). Robust to spaces in the renamed files (the
    /// wikilink form sidesteps markdown URL escaping). Returns rewritten md + copies.
    /// `id` disambiguates a name collision with a file this device doesn't own (C58).
    /// `profile`: the portfolio's `![](x)` / `[x](x)`, the vault's `![[x]]` / `[[x]]` (R51).
    static func convertNoteAttachments(_ markdown: String, attachmentsSrc: URL, into attDir: URL, id: UUID,
                                       place: Placer? = nil, profile: ExportProfile) -> (String, Int) {
        let fm = FileManager.default
        guard let rx = try? NSRegularExpression(pattern: "(!?)\\[[^\\]]*\\]\\(Attachments/([^)]+)\\)") else {
            return (markdown, 0)
        }
        let ns = markdown as NSString
        var replacements: [(NSRange, String)] = []
        var copied = 0
        for m in rx.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
            let bang = ns.substring(with: m.range(at: 1))
            let raw = ns.substring(with: m.range(at: 2))
            let name = raw.removingPercentEncoding ?? raw
            let src = attachmentsSrc.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { continue }
            guard let written = (place ?? owned(id))(src, name, attDir) else {
                Self.logCopyFailure(name: name); continue
            }
            copied += 1
            let out = written.lastPathComponent
            replacements.append((m.range, profile == .portfolio
                ? (bang.isEmpty ? "[\(out)](\(out))" : "![](\(out))")
                : "\(bang)[[\(out)]]"))
        }
        return (Sanitiser.nsReplace(markdown, edits: replacements), copied)
    }
}
