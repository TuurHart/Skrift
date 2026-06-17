import Foundation
import SwiftData

/// Reconciles the local `names.json` (`NamesStore`) with the CloudKit-synced
/// `NamesRecord` carrier (Phase 1e) so people + enrolled voices sync across the
/// user's devices. Runs on launch + foreground, alongside `AssetMaterializer`.
///
/// The merge is the SAME one the Mac sync uses — `NamesMerge.mergeByCanonical`
/// (per-canonical LWW + voiceEmbeddings union) — so device↔device and phone↔Mac
/// converge identically, and `names.json` (the contract artifact) stays the local
/// source of truth. Idempotent: an unchanged merge re-encodes to the same bytes, so
/// nothing is written and CloudKit doesn't churn. The local file write and the
/// record write are each gated on an actual change.
///
/// Duplicate carriers (two devices each created one before syncing) are merged in
/// and collapsed to a single row — no data is lost because their contents are folded
/// through the merge first.
@MainActor
enum NamesCloudSync {

    /// Deterministic, sorted-keys encoding of a people list as `NamesData` — used both
    /// to write the carrier and to compare for "did anything change" without relying on
    /// `Equatable`. Deterministic (no `now()`): an unchanged set yields identical bytes.
    private static func normalizedData(_ people: [Person]) -> NamesData {
        NamesData(lastModifiedAt: NamesMerge.topLevelTimestamp(people),
                  people: NamesMerge.sortPeople(people))
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static func run(_ repository: NotesRepository, store: NamesStore = .shared) {
        let local = store.load()

        // Fold the local people together with every carrier row (handles the rare
        // duplicate-carrier case). Order doesn't matter — the merge is commutative
        // enough (LWW by timestamp + union), so the result converges.
        let records = repository.allNamesRecords()
        var people = local.people
        for record in records {
            guard let remote = try? JSONDecoder().decode(NamesData.self, from: record.blob) else { continue }
            people = NamesMerge.mergeByCanonical(local: people, remote: remote.people)
        }

        let merged = normalizedData(people)
        guard let mergedBlob = try? encoder.encode(merged) else { return }

        // 1. Update the local names.json only if the merge actually changed it.
        if (try? encoder.encode(normalizedData(local.people))) != mergedBlob {
            _ = store.save(merged)
            DevLog.log("names: merged remote → local (\(merged.people.count) people)")
        }

        // 2. Collapse to a single carrier holding the merged blob; delete extras.
        if let primary = records.first {
            if primary.blob != mergedBlob {
                primary.blob = mergedBlob
                primary.updatedAt = Date()
            }
            for extra in records.dropFirst() { repository.context.delete(extra) }
        } else {
            repository.context.insert(NamesRecord(blob: mergedBlob))
        }
        repository.save()
    }
}
