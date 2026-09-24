import Foundation
import SwiftData

/// The Mac side of the one-time body normalisation (C10, D4, R25 —
/// `Shared/BodyV2/BodyNormaliseMigration.swift`). Runs at a note's first open on THIS Mac over
/// the bodies the review shows (sanitised → copy-edit → transcript). The suggested-name
/// offsets (`ambiguousNames`) point into `sanitised`, so when that body moves they are
/// re-derived over the new text (R25). The once-flag and the originals live in the local
/// ledger, never in the store.
///
/// Q40: the polished copy-edit has its OWN once-flag (`<id>.polished`), because a polish can
/// arrive after the first open: the local `enhancedCopyedit`, the `sanitised` derived from it
/// (when the body pass has not already fixed it) and — when the CloudKit store is at hand — the
/// synced `MemoEnhancement.copyedit`. On the synced row ONLY `copyedit` is written:
/// `enhancedAt` / `enhancedByDeviceID` / `processedAt` stay, so the rewrite never wins an LWW
/// race against another device's newer polish and never claims authorship; `MacCloudWriteBack`
/// (which stamps `enhancedAt = now`) is deliberately NOT used. It is not a words edit either: no
/// `EditConflicts.recordEdit`, so no edit vector or `MemoEditHead` moves.
extension PipelineFile {
    private var bodyNormaliseBodies: [BodyNormaliseMigration.Body] {
        [.init(name: "transcript", get: { self.transcript }, set: { self.transcript = $0 }),
         .init(name: "sanitised", get: { self.sanitised }, set: { self.sanitised = $0 }),
         // Q14 records may hold it; the pass itself now runs it under the polished flag.
         .init(name: "enhancedCopyedit", get: { self.enhancedCopyedit }, set: { self.enhancedCopyedit = $0 })]
    }

    private var bodyNormaliseMainBodies: [BodyNormaliseMigration.Body] {
        bodyNormaliseBodies.filter { $0.name != "enhancedCopyedit" }
    }

    private func polishedBodies(cloud: MemoEnhancement?) -> [BodyNormaliseMigration.Body] {
        var out: [BodyNormaliseMigration.Body] = [
            .init(name: "enhancedCopyedit", get: { self.enhancedCopyedit }, set: { self.enhancedCopyedit = $0 }),
            .init(name: "sanitised", get: { self.sanitised }, set: { self.sanitised = $0 })]
        if let cloud {
            out.append(.init(name: "cloudCopyedit", get: { cloud.copyedit }, set: { cloud.copyedit = $0 }))
        }
        return out
    }

    private var bodyNormaliseMetadata: [String: Any] {
        audioMetadataJSON.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
    }

    private var bodyNormaliseManifestCount: Int {
        (bodyNormaliseMetadata["imageManifest"] as? [Any])?.count ?? 0
    }

    private var bodyNormaliseLegacyShape: Bool {
        let meta = bodyNormaliseMetadata
        let madeAt = ((meta["capturedAt"] ?? meta["recordedAt"]) as? String).flatMap { MetadataDate.parse($0) }
        return BodyNormaliseMigration.isC203Legacy(sharedContent: meta["sharedContent"] as? [String: Any], madeAt: madeAt)
    }

    /// The synced polish row for this note in `cloud`, if any (newest `enhancedAt` first).
    private func cloudEnhancement(in cloud: ModelContext?) -> MemoEnhancement? {
        guard let cloud, let memoID = MacCloudWriteBack.resolve(for: self, in: cloud)?.id else { return nil }
        let rows = (try? cloud.fetch(FetchDescriptor<MemoEnhancement>(predicate: #Predicate { $0.memoID == memoID }))) ?? []
        return rows.max { $0.enhancedAt < $1.enhancedAt }
    }

    /// Normalises this note's stored bodies once, if they break C10, then its polished text
    /// once (own flag). The return is the body pass's outcome; a second call returns nil.
    @discardableResult
    func normaliseBodyOnce(ledger: BodyNormaliseMigration.Ledger = .standard,
                           cloud: ModelContext? = nil) -> BodyNormaliseMigration.Outcome? {
        var outcome: BodyNormaliseMigration.Outcome?
        if !ledger.hasRun(id) {
            outcome = BodyNormaliseMigration.run(
                id: id, bodies: bodyNormaliseMainBodies, manifestCount: bodyNormaliseManifestCount,
                machineText: !transcriptUserEdited && sourceType == .audio,
                legacyShape: bodyNormaliseLegacyShape,
                ledger: ledger,
                didRewrite: { name, old, new in self.remapNameOffsets(body: name, from: old, to: new) })
            if outcome == .rewritten { try? modelContext?.save() }
        }
        normalisePolishOnce(ledger: ledger, cloud: cloud)
        return outcome
    }

    /// The polished text's one pass (Q40). Writes the text fields only; see the type comment.
    @discardableResult
    func normalisePolishOnce(ledger: BodyNormaliseMigration.Ledger = .standard,
                             cloud: ModelContext? = nil) -> BodyNormaliseMigration.Outcome? {
        guard !ledger.hasRun(BodyNormaliseMigration.polishedKey(id)) else { return nil }
        let row = cloudEnhancement(in: cloud)
        // No polish yet = no flag (`sanitised` alone must not burn the once-flag).
        func blank(_ s: String?) -> Bool { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !blank(enhancedCopyedit) || !blank(row?.copyedit) else { return nil }
        let outcome = BodyNormaliseMigration.runPolished(
            id: id, bodies: polishedBodies(cloud: row), manifestCount: bodyNormaliseManifestCount,
            legacyShape: bodyNormaliseLegacyShape, ledger: ledger,
            didRewrite: { name, old, new in self.remapNameOffsets(body: name, from: old, to: new) })
        if outcome == .rewritten {
            try? modelContext?.save()
            if row != nil { try? cloud?.save() }
        }
        return outcome
    }

    /// Puts the pre-migration bodies back (each only if still the migrated text), with the
    /// name offsets mapped back, and marks the note so it is never migrated again. The synced
    /// polish row comes back too when `cloud` is given.
    @discardableResult
    func undoBodyNormalise(ledger: BodyNormaliseMigration.Ledger = .standard,
                           cloud: ModelContext? = nil) -> Bool {
        let remapBack: (String, String, String) -> Void = { name, migrated, original in
            self.remapNameOffsets(body: name, from: migrated, to: original)
        }
        let row = cloudEnhancement(in: cloud)
        let restored = BodyNormaliseMigration.undo(id: id, bodies: bodyNormaliseBodies, ledger: ledger, didRestore: remapBack)
            + BodyNormaliseMigration.undoPolished(id: id, bodies: polishedBodies(cloud: row), ledger: ledger, didRestore: remapBack)
        if !restored.isEmpty {
            try? modelContext?.save()
            if row != nil, restored.contains("cloudCopyedit") { try? cloud?.save() }
        }
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
