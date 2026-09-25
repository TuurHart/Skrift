import Foundation
import SwiftData
import os

extension Notification.Name {
    /// Posted when a CloudKit names reconcile changes the local roster, so open UI (the
    /// Settings names list) can live-refresh instead of showing stale data until reopened.
    static let namesDidChangeFromSync = Notification.Name("skrift.namesDidChangeFromSync")
}

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

    /// Merge the CloudKit `NamesRecord` carrier(s) with local `names.json`, write the union
    /// back to both. Returns true when the local roster changed (so a caller can re-scan).
    /// The reconcile (fold carriers → NamesMerge → collapse to one row) is SHARED with the
    /// phone — `NamesSyncCore`. This adapter owns the sync gate + the live-refresh notification.
    @discardableResult
    static func run(store: NamesStore = .shared) -> Bool {
        guard SettingsStore.shared.load().cloudKitMacSyncEnabled,
              let container = MemoCloudStore.container else { return false }
        // Fresh context: `mainContext` doesn't refresh registered rows after a CloudKit import,
        // so a phone names edit (a NamesRecord blob update) would read stale (same trap as the
        // memo sweep). A new context reads the latest import.
        let context = ModelContext(container)
        let local = store.load()
        let records = (try? context.fetch(FetchDescriptor<NamesRecord>())) ?? []

        guard let outcome = NamesSyncCore.reconcile(
            localPeople: local.people, records: records,
            insert: { context.insert($0) },
            delete: { context.delete($0) }) else { return false }

        if outcome.localChanged { _ = store.save(outcome.merged) }
        // Once per launch/foreground/import reconcile (sweep E finding #3): drop
        // tombstones older than the default 90-day window, well past any realistic
        // sync gap. A no-op run makes no write — `pruneOldTombstones` only saves
        // when it actually drops a row.
        let pruned = store.pruneOldTombstones()
        if pruned > 0 {
            Logger(subsystem: "com.skrift.desktop", category: "cloudkit")
                .info("names: pruned \(pruned) old tombstone(s)")
        }
        do { try context.save() }
        catch {
            Logger(subsystem: "com.skrift.desktop", category: "cloudkit")
                .error("names sync save FAILED — carrier not persisted: \(error)")
        }
        // Live-refresh any open Settings names list (the reconcile runs in the background
        // off a CloudKit import, so the view has no other way to know the roster changed).
        if outcome.localChanged { NotificationCenter.default.post(name: .namesDidChangeFromSync, object: nil) }
        return outcome.localChanged
    }
}
