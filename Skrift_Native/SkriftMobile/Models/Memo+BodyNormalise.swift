import Foundation
import SwiftData

/// The phone side of the one-time body normalisation (C10, D4, R25 —
/// `Shared/BodyV2/BodyNormaliseMigration.swift`). Runs at a note's first open on THIS device;
/// the once-flag and the original body live in the local ledger, never in the synced `Memo`.
/// The phone stores no name offsets (it re-derives `nameSpans` over the raw body on demand),
/// so the rewritten body is all R25 needs here. Not a touch: `editedAt` is left alone, so the
/// note's lifecycle clock does not restart.
extension Memo {
    private var bodyNormaliseBodies: [BodyNormaliseMigration.Body] {
        [.init(name: "transcript", get: { self.transcript }, set: { self.transcript = $0 })]
    }

    /// Normalises this note's stored body once, if it breaks C10. A second call is a no-op.
    @discardableResult
    func normaliseBodyOnce(ledger: BodyNormaliseMigration.Ledger = .standard) -> BodyNormaliseMigration.Outcome? {
        guard !ledger.hasRun(id.uuidString) else { return nil }
        let outcome = BodyNormaliseMigration.run(
            id: id.uuidString, bodies: bodyNormaliseBodies,
            manifestCount: metadata?.imageManifest?.count ?? 0,
            machineText: !transcriptUserEdited && sharedContentData == nil && !audioFilename.isEmpty,
            legacyShape: BodyNormaliseMigration.isC203Legacy(sharedContentData: sharedContentData,
                                                             madeAt: createdAt ?? recordedAt),
            ledger: ledger)
        if outcome == .rewritten {
            DevLog.log("bodyNormalise: \(id.uuidString) rewritten")
            try? modelContext?.save()
        }
        return outcome
    }

    /// Puts the pre-migration body back (only if it is still the migrated one) and marks the
    /// note so it is never migrated again. Returns true when the body was restored.
    @discardableResult
    func undoBodyNormalise(ledger: BodyNormaliseMigration.Ledger = .standard) -> Bool {
        let restored = BodyNormaliseMigration.undo(id: id.uuidString, bodies: bodyNormaliseBodies, ledger: ledger)
        if !restored.isEmpty { try? modelContext?.save() }
        return !restored.isEmpty
    }
}
