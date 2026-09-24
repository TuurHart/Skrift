import Foundation
import SwiftData

/// The phone side of the one-time body normalisation (C10, D4, R25 —
/// `Shared/BodyV2/BodyNormaliseMigration.swift`). Runs at a note's first open on THIS device;
/// the once-flag and the original body live in the local ledger, never in the synced `Memo`.
/// The phone stores no name offsets (it re-derives `nameSpans` over the raw body on demand),
/// so the rewritten body is all R25 needs here. Not a touch: `editedAt` is left alone, so the
/// note's lifecycle clock does not restart.
///
/// Q40: the polished copy-edit (`MemoEnhancement.copyedit`, what he reads and edits) gets the
/// same pass under its own once-flag. Only `copyedit` is written: `enhancedAt`,
/// `enhancedByDeviceID` and `processedAt` stay as they were, so the rewrite never makes an old
/// polish look newer than another device's re-polish (LWW by `enhancedAt`) and never claims
/// authorship; and it is not a words edit, so no edit vector / `MemoEditHead` moves (those
/// hash title + transcript + tags, and nothing here calls `markEdited`/`recordEdit`).
extension Memo {
    private var bodyNormaliseBodies: [BodyNormaliseMigration.Body] {
        [.init(name: "transcript", get: { self.transcript }, set: { self.transcript = $0 })]
    }

    private static func polishedBodies(_ e: MemoEnhancement?) -> [BodyNormaliseMigration.Body] {
        guard let e else { return [] }
        return [.init(name: "copyedit", get: { e.copyedit }, set: { e.copyedit = $0 })]
    }

    private var bodyNormaliseLegacyShape: Bool {
        BodyNormaliseMigration.isC203Legacy(sharedContentData: sharedContentData, madeAt: createdAt ?? recordedAt)
    }

    /// Normalises this note's stored body once, if it breaks C10, and its polished copy-edit
    /// once (own flag). The return is the body's outcome; a second call returns nil.
    @discardableResult
    func normaliseBodyOnce(enhancement: MemoEnhancement? = nil,
                           ledger: BodyNormaliseMigration.Ledger = .standard) -> BodyNormaliseMigration.Outcome? {
        normalisePolishOnce(enhancement, ledger: ledger)
        guard !ledger.hasRun(id.uuidString) else { return nil }
        let outcome = BodyNormaliseMigration.run(
            id: id.uuidString, bodies: bodyNormaliseBodies,
            manifestCount: metadata?.imageManifest?.count ?? 0,
            machineText: !transcriptUserEdited && sharedContentData == nil && !audioFilename.isEmpty,
            legacyShape: bodyNormaliseLegacyShape,
            ledger: ledger)
        if outcome == .rewritten {
            DevLog.log("bodyNormalise: \(id.uuidString) rewritten")
            try? modelContext?.save()
        }
        return outcome
    }

    /// The polished copy-edit's one pass (Q40). Writes `copyedit` only; see the type comment.
    @discardableResult
    func normalisePolishOnce(_ enhancement: MemoEnhancement?,
                             ledger: BodyNormaliseMigration.Ledger = .standard) -> BodyNormaliseMigration.Outcome? {
        guard let enhancement, enhancement.memoID == id else { return nil }
        let outcome = BodyNormaliseMigration.runPolished(
            id: id.uuidString, bodies: Self.polishedBodies(enhancement),
            manifestCount: metadata?.imageManifest?.count ?? 0,
            legacyShape: bodyNormaliseLegacyShape, ledger: ledger)
        if outcome == .rewritten {
            DevLog.log("bodyNormalise: \(id.uuidString) polish rewritten")
            try? (enhancement.modelContext ?? modelContext)?.save()
        }
        return outcome
    }

    /// Puts the pre-migration body (and polished copy-edit) back, each only if it is still the
    /// migrated one, and marks the note so it is never migrated again. True when any came back.
    @discardableResult
    func undoBodyNormalise(enhancement: MemoEnhancement? = nil,
                           ledger: BodyNormaliseMigration.Ledger = .standard) -> Bool {
        var restored = BodyNormaliseMigration.undo(id: id.uuidString, bodies: bodyNormaliseBodies, ledger: ledger)
        if enhancement != nil {   // without the row, leave its record rewritten so a later undo can still restore it
            restored += BodyNormaliseMigration.undoPolished(id: id.uuidString, bodies: Self.polishedBodies(enhancement), ledger: ledger)
        }
        if !restored.isEmpty {
            try? modelContext?.save()
            try? enhancement?.modelContext?.save()
        }
        return !restored.isEmpty
    }
}
