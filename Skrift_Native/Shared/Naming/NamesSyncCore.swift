import Foundation
import SwiftData

/// The names reconcile — ONE algorithm for every device (phone, iPad, Mac). Folds the
/// local `names.json` people together with every synced `NamesRecord` carrier through
/// `NamesMerge.mergeByCanonical` (per-canonical last-write-wins + **union** of
/// voiceEmbeddings), collapses the carriers to a single row holding the merged blob,
/// and reports whether the local roster changed. Both apps carried a byte-identical
/// copy of this (phone `Services/NamesCloudSync`, Mac `App/NamesCloudSync`) — an
/// encoder divergence here would cause a CloudKit churn loop, so it lives once.
///
/// The caller owns everything platform-specific: the sync gate, fetching the records,
/// writing `names.json`, saving the context, and any change notification. It supplies
/// `insert`/`delete` for the carrier collapse (matching `VocabularySyncCore`'s recipe).
enum NamesSyncCore {

    struct Outcome {
        /// The merged roster — the caller writes it to `names.json` IFF `localChanged`.
        let merged: NamesData
        /// True when the merge differs from the local roster → caller saves + notifies.
        let localChanged: Bool
    }

    /// Deterministic `NamesData` (sorted people, max timestamp) — the carrier payload and
    /// the "did anything change" comparison, both free of `now()` so an unchanged set is
    /// byte-stable (no CloudKit churn).
    static func normalized(_ people: [Person]) -> NamesData {
        NamesData(lastModifiedAt: NamesMerge.topLevelTimestamp(people),
                  people: NamesMerge.sortPeople(people))
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    /// Merge local people with every carrier, collapse to one carrier row, and report the
    /// outcome. Returns nil only if the merged roster can't be encoded (nothing is written
    /// — the carriers are left untouched, mirroring both originals' early-return).
    static func reconcile(localPeople: [Person],
                          records: [NamesRecord],
                          insert: (NamesRecord) -> Void,
                          delete: (NamesRecord) -> Void) -> Outcome? {
        // Fold local + every carrier row (handles the rare duplicate-carrier case — two
        // devices each created one before syncing). Commutative enough (LWW + union) to converge.
        var people = localPeople
        for record in records {
            guard let remote = try? JSONDecoder().decode(NamesData.self, from: record.blob) else { continue }
            people = NamesMerge.mergeByCanonical(local: people, remote: remote.people)
        }

        let merged = normalized(people)
        guard let mergedBlob = try? encoder.encode(merged) else { return nil }
        let localChanged = (try? encoder.encode(normalized(localPeople))) != mergedBlob

        // Collapse to a single carrier holding the merged blob; delete extras.
        if let primary = records.first {
            if primary.blob != mergedBlob {
                primary.blob = mergedBlob
                primary.updatedAt = Date()
            }
            for extra in records.dropFirst() { delete(extra) }
        } else {
            insert(NamesRecord(blob: mergedBlob))
        }
        return Outcome(merged: merged, localChanged: localChanged)
    }
}
