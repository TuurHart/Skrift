import Foundation
import SwiftData

/// Mac side of the CloudKit **names** carrier — the phone↔Mac names path over CloudKit that
/// replaces the Bonjour `/api/names` endpoints. Reconciles the Mac's local `names.json`
/// (`NamesStore`) with the shared `NamesRecord` blob carrier, using the SAME merge the
/// Bonjour sync used — `NamesMerge.mergeByCanonical` (per-canonical LWW + voiceEmbeddings
/// union) — so phone↔Mac↔iPad all converge identically and `names.json` (the contract
/// artifact) stays the Mac's local source of truth. A faithful mirror of the phone's
/// `NamesCloudSync`.
///
/// Runs from `MemoCloudReconciler` on launch / foreground / CloudKit-import, and after a
/// Mac-side names edit. No-op unless the user enabled CloudKit-Mac sync AND the container is
/// available (the same gate as the memo sweep). Idempotent: an unchanged merge re-encodes to
/// the same bytes, so nothing is written and CloudKit doesn't churn.
@MainActor
enum NamesCloudSync {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e
    }()

    /// Deterministic `NamesData` (sorted people, max timestamp) — used to write the carrier
    /// and to compare "did anything change" without relying on `now()`.
    private static func normalized(_ people: [Person]) -> NamesData {
        NamesData(lastModifiedAt: NamesMerge.topLevelTimestamp(people),
                  people: NamesMerge.sortPeople(people))
    }

    /// Merge the CloudKit `NamesRecord` carrier(s) with local `names.json`, write the union
    /// back to both. Returns true when the local roster changed (so a caller can re-scan).
    @discardableResult
    static func run(store: NamesStore = .shared) -> Bool {
        guard SettingsStore.shared.load().cloudKitMacSyncEnabled,
              let container = MemoCloudStore.container else { return false }
        let context = container.mainContext
        let local = store.load()

        // Fold local people together with every carrier row (handles the rare
        // duplicate-carrier case — two devices each created one before syncing).
        let records = (try? context.fetch(FetchDescriptor<NamesRecord>())) ?? []
        var people = local.people
        for record in records {
            guard let remote = try? JSONDecoder().decode(NamesData.self, from: record.blob) else { continue }
            people = NamesMerge.mergeByCanonical(local: people, remote: remote.people)
        }

        let merged = normalized(people)
        guard let mergedBlob = try? encoder.encode(merged) else { return false }

        // 1. Update local names.json only when the merge actually changed it.
        var changed = false
        if (try? encoder.encode(normalized(local.people))) != mergedBlob {
            _ = store.save(merged)
            changed = true
        }

        // 2. Collapse to a single carrier holding the merged blob; delete extras.
        if let primary = records.first {
            if primary.blob != mergedBlob {
                primary.blob = mergedBlob
                primary.updatedAt = Date()
            }
            for extra in records.dropFirst() { context.delete(extra) }
        } else {
            context.insert(NamesRecord(blob: mergedBlob))
        }
        try? context.save()
        return changed
    }
}
