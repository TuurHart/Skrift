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

    static func run(_ repository: NotesRepository, store: NamesStore = .shared) {
        let local = store.load()
        // The reconcile (fold carriers → NamesMerge → collapse to one row) is SHARED
        // with the Mac — `NamesSyncCore`. This adapter owns the store + logging.
        guard let outcome = NamesSyncCore.reconcile(
            localPeople: local.people,
            records: repository.allNamesRecords(),
            insert: { repository.context.insert($0) },
            delete: { repository.context.delete($0) }) else { return }

        if outcome.localChanged {
            _ = store.save(outcome.merged)
            DevLog.log("names: merged remote → local (\(outcome.merged.people.count) people)")
        }
        repository.save()
    }
}
