import Foundation

/// What to SAY after an export, and whether it can be allowed to disappear — one table for
/// both apps (Tuur, 2026-08-28: *"when I click the export button, what happens afterwards is
/// not the same on Mac and iPad"*).
///
/// It wasn't. Three ways:
///
/// 1. **A refusal vanished on the Mac.** Every outcome went to the same 3.5-second banner, so
///    "filed out of your Skrift folder" — a state that blocks the export *permanently* — got the
///    same three seconds as "done". The phone had it right: a refusal is a notice you dismiss.
///    That is the whole reason `stickiness` exists here.
/// 2. **The Mac said "Exported" when nothing was written.** `unchanged` was folded in with
///    created/updated, so a no-op claimed a write. The phone said "Already in the vault".
/// 3. **Different words for identical outcomes**, which is how two implementations of one verb
///    always end (memory `feedback_shared_code_first`).
enum ExportOutcomeCopy {

    /// Can this message be allowed to fade on its own?
    enum Stickiness {
        /// Something happened and the note is where it should be — a flash is enough.
        case transient
        /// The export did NOT happen. It must stay until the user dismisses it, on every
        /// device: a refusal that fades is a refusal the user never learns about.
        case sticky
    }

    struct Message {
        let text: String
        let stickiness: Stickiness
        var isRefusal: Bool { stickiness == .sticky }
    }

    // MARK: - Refusals before the engine runs (Q156)

    /// The sentence for each gate `ExportGate.check` can fail, the SAME words on both devices;
    /// only the pointer to where Settings lives follows the device. Always sticky: a refusal
    /// stays until dismissed and names the FIRST failing gate (C194).
    static func refusal(_ failure: ExportGate.Failure, device: ExportGate.Device) -> Message {
        let text: String
        switch failure {
        case .noPortfolioFolder:
            text = "No portfolio folder is set on this device yet. Pick one in Settings → Destinations."
        case .noVaultFolder:
            let place = device == .mac ? "Settings → Vault & author" : "Settings → Obsidian"
            text = "No vault folder is set on this device yet. Pick one in \(place)."
        case .trashed:
            text = "This note is in Recently Deleted."
        case .locked:
            text = "Locked notes stay inside Skrift — the vault is plain text on disk. "
                 + "Unlock the note to export it."
        case .twoVersions:
            text = "This note has two versions. Pick one to export it."
        case .unrated:
            text = "Rate this note first — unrated notes never leave Skrift."
        case .nothingToExport:
            text = "There's nothing to export yet."
        case .unprocessed:
            text = "Process this note first — the vault gets the polished note, not the raw one."
        }
        return .init(text: text, stickiness: .sticky)
    }

    /// A pick exists but the folder can't be opened (stale bookmark, drive gone).
    static func folderUnreadable(device: ExportGate.Device) -> Message {
        let place = device == .mac ? "Settings → Vault & author" : "Settings → Obsidian"
        return .init(text: "The vault folder couldn't be opened — pick it again in \(place).",
                     stickiness: .sticky)
    }

    /// The gate passed a moment ago and the publish path still declined (the note changed
    /// under the press).
    static let notEligible = Message(text: "This note isn't eligible to export right now.",
                                     stickiness: .sticky)

    /// The write threw.
    static func failed(_ error: Error) -> Message {
        .init(text: "Export failed: \(error.localizedDescription)", stickiness: .sticky)
    }

    /// The ONE name rule: the stem of the file the engine wrote or refused (Q117 — the iPad
    /// quoted the note's display title, the Mac the file stem, so one outcome read two ways).
    static func noteName(forRelativePath rel: String) -> String {
        ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// The call both apps make: the name comes from the engine's own outcome, and
    /// `assetCount` is the files (photos, documents) the write placed beside the note.
    static func message(for outcome: VaultWriteOutcome, assetCount: Int? = nil) -> Message {
        message(for: outcome, noteName: noteName(forRelativePath: outcome.relativePath),
                assetCount: assetCount)
    }

    /// `noteName` is the note's exported stem; `assetCount` is images+documents written
    /// (nil / 0 omits the clause).
    static func message(for outcome: VaultWriteOutcome,
                        noteName: String,
                        assetCount: Int? = nil) -> Message {
        switch outcome {
        case .created, .updated:
            let assets = (assetCount ?? 0) > 0
                ? " · \(assetCount!) file\((assetCount! == 1) ? "" : "s")" : ""
            return .init(text: "Exported “\(noteName)”\(assets)", stickiness: .transient)

        case .unchanged:
            // NOT "Exported": nothing was written, and saying otherwise is the small lie that
            // makes a person stop trusting the banner.
            return .init(text: "“\(noteName)” is already up to date", stickiness: .transient)

        case .backedOffUserEdited:
            return .init(text: "You've edited “\(noteName)” where it lives — Skrift left your "
                             + "version alone and exported nothing.", stickiness: .sticky)

        case .movedAway:
            return .init(text: "“\(noteName)” was filed out of the folder Skrift wrote it to, so "
                             + "it wasn't exported. Skrift leaves a filed note where you put it.",
                         stickiness: .sticky)

        case .blockedLegacy:
            return .init(text: "“\(noteName)” predates Skrift's stamp, so it can't be told apart "
                             + "from your own edits. Delete that file to export this note fresh.",
                         stickiness: .sticky)

        case .blockedForeign:
            return .init(text: "A file called “\(noteName)” is already there and isn't Skrift's — "
                             + "refused to overwrite it.", stickiness: .sticky)
        }
    }
}
