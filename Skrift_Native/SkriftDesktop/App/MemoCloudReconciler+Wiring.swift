import Foundation
import SwiftData
import CoreData
import AppKit

/// App-only wiring for `MemoCloudReconciler` — the triggers + the `reconcile()` entry point
/// that resolve the app's two containers (`MemoCloudStore` / `SharedStore`) and the user's
/// settings. Kept out of the pure-`sweep` file so the host-less test bundle (which has neither
/// container) still compiles the reconciler core (`MAC_CLOUDKIT_PLAN.md`, 8d).
extension MemoCloudReconciler {
    /// Register the launch + foreground + CloudKit-import triggers (idempotent). Each fires a
    /// guarded sweep, so it's safe to call even when CloudKit-Mac sync is off (the sweep
    /// no-ops). Call once at app launch.
    ///
    /// Every sweep is dispatched as an async `Task { @MainActor }` (NOT a synchronous
    /// `assumeIsolated`/direct call), so it never blocks `App.init()` or the notification
    /// delivery — the window renders first, then the sweep runs. SwiftData access stays on the
    /// main actor by design (the codebase funnels all SwiftData onto main to avoid cross-context
    /// corruption — see SyncHandlers). The sweep dedups, so after the first ingest later sweeps
    /// write nothing; a large first-enable backlog is the one case worth moving the blob
    /// materialization off-main (deferred — would need a non-main context, which the on-main rule
    /// forbids without care).
    static func start() {
        guard !didStart else { return }
        didStart = true

        // A CloudKit import just finished → new/changed memos may have arrived. (Only the
        // CloudKit-backed MemoCloud container posts these; the local PipelineFile store doesn't.)
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            let importDone = event.endDate != nil && event.type == .import && event.succeeded
            if importDone { Task { @MainActor in _ = reconcile() } }
        }

        // App became active — the desktop analogue of the phone's foreground sweep.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in Task { @MainActor in _ = reconcile() } }

        Task { @MainActor in _ = reconcile() }   // launch sweep — async, doesn't block App.init()
    }

    /// Pull every eligible synced memo into the local pipeline store. No-op unless the user
    /// enabled CloudKit-Mac sync AND the CloudKit container is available. Returns the count
    /// ingested.
    @discardableResult
    static func reconcile() -> Int {
        let settings = SettingsStore.shared.load()
        guard settings.cloudKitMacSyncEnabled, let cloud = MemoCloudStore.container else { return 0 }
        return sweep(from: cloud.mainContext, into: SharedStore.container.mainContext,
                     processEverything: settings.processAllSyncedMemosEnabled)
    }
}
