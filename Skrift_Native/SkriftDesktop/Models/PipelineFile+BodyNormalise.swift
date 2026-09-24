import Foundation
import SwiftData

/// The Mac side of the one-time body normalisation (C10, D4, R25 —
/// `Shared/BodyV2/BodyNormaliseMigration.swift`). Runs at a note's first open on THIS Mac over
/// the three bodies the review shows (sanitised → copy-edit → transcript). The suggested-name
/// offsets (`ambiguousNames`) point into `sanitised`, so when that body moves they are
/// re-derived over the new text (R25). The once-flag and the originals live in the local
/// ledger, never in the store.
extension PipelineFile {
    private var bodyNormaliseBodies: [BodyNormaliseMigration.Body] {
        [.init(name: "transcript", get: { self.transcript }, set: { self.transcript = $0 }),
         .init(name: "sanitised", get: { self.sanitised }, set: { self.sanitised = $0 }),
         .init(name: "enhancedCopyedit", get: { self.enhancedCopyedit }, set: { self.enhancedCopyedit = $0 })]
    }

    private var bodyNormaliseMetadata: [String: Any] {
        audioMetadataJSON.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
    }

    /// Normalises this note's stored bodies once, if they break C10. A second call is a no-op.
    @discardableResult
    func normaliseBodyOnce(ledger: BodyNormaliseMigration.Ledger = .standard) -> BodyNormaliseMigration.Outcome? {
        guard !ledger.hasRun(id) else { return nil }
        let meta = bodyNormaliseMetadata
        let manifestCount = (meta["imageManifest"] as? [Any])?.count ?? 0
        let madeAt = ((meta["capturedAt"] ?? meta["recordedAt"]) as? String).flatMap { MetadataDate.parse($0) }
        let outcome = BodyNormaliseMigration.run(
            id: id, bodies: bodyNormaliseBodies, manifestCount: manifestCount,
            machineText: !transcriptUserEdited && sourceType == .audio,
            legacyShape: BodyNormaliseMigration.isC203Legacy(
                sharedContent: meta["sharedContent"] as? [String: Any], madeAt: madeAt),
            ledger: ledger,
            didRewrite: { name, old, new in self.remapNameOffsets(body: name, from: old, to: new) })
        if outcome == .rewritten { try? modelContext?.save() }
        return outcome
    }

    /// Puts the pre-migration bodies back (each only if still the migrated text), with the
    /// name offsets mapped back, and marks the note so it is never migrated again.
    @discardableResult
    func undoBodyNormalise(ledger: BodyNormaliseMigration.Ledger = .standard) -> Bool {
        let restored = BodyNormaliseMigration.undo(
            id: id, bodies: bodyNormaliseBodies, ledger: ledger,
            didRestore: { name, migrated, original in self.remapNameOffsets(body: name, from: migrated, to: original) })
        if !restored.isEmpty { try? modelContext?.save() }
        return !restored.isEmpty
    }

    /// R25: the suggested-name offsets index `sanitised`; re-derive them when it changes.
    private func remapNameOffsets(body: String, from old: String, to new: String) {
        guard body == "sanitised", let occ = ambiguousNames, !occ.isEmpty else { return }
        ambiguousNames = BodyNormaliseMigration.remap(occ, from: old, to: new)
    }
}

/// ISO-8601 with or without fractional seconds (metadata dates are written both ways).
private enum MetadataDate {
    static func parse(_ s: String) -> Date? {
        if let d = ISO8601.date(from: s) { return d }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
