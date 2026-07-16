import Foundation
import SwiftData
import CoreData
import AppKit
import os

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

    /// Pull every eligible synced memo into the local pipeline store, and reconcile the
    /// CloudKit names + vocabulary carriers into the Mac's local stores. No-op unless the user
    /// enabled CloudKit-Mac sync AND the CloudKit container is available. Returns the count of
    /// memos ingested.
    @discardableResult
    static func reconcile() -> Int {
        // The Connections index sweep rides every reconcile trigger (launch /
        // foreground / CloudKit import) — AFTER the cloud work, so just-imported
        // memos index in the same pass. Self-gated (consent + model on disk) and
        // hash-diffed ⇒ a redundant fire is nearly free. Runs even when cloud
        // sync is off: locally-ingested files need indexing too.
        defer { ConnectionsIndexService.shared.sweepSoon(SharedStore.container.mainContext) }
        let settings = SettingsStore.shared.load()
        guard settings.cloudKitMacSyncEnabled, let cloud = MemoCloudStore.container else { return 0 }
        // Names (people + voiceprints) + custom vocab now flow over CloudKit (replacing the
        // Bonjour /api/names path). Both are guarded + idempotent, so running them on every
        // sweep is cheap; they converge with the phone through the shared merge.
        NamesCloudSync.run()
        VocabularyCloudSync.run()
        let local = SharedStore.container.mainContext
        // READ THROUGH A FRESH CONTEXT. A CloudKit import writes to the persistent STORE but does
        // NOT refresh `mainContext`'s already-registered `Memo` objects — so `cloud.mainContext`
        // returns STALE memos and the sweep never sees a phone's LATER delete / tag / edit (only a
        // first-seen memo is fresh — which is exactly why Mac→phone synced but phone→Mac didn't,
        // 2026-07-15 device test). A brand-new context has an empty row cache, so every fetch hits
        // the store and reads the latest import.
        let cloudContext = ModelContext(cloud)
        let outcome = sweep(from: cloudContext, into: local,
                            processEverything: settings.processAllSyncedMemosEnabled,
                            people: NamesStore.shared.livePeople(), author: settings.authorName,
                            thisDeviceID: DeviceID.current())
        Logger(subsystem: "com.skrift.desktop", category: "cloudkit").log(
            "reconcile: ingested \(outcome.created, privacy: .public), reflected \(outcome.updatedIDs.count, privacy: .public)")
        // A phone edit re-linked + recompiled an existing row (Part B). Persist it, and if it
        // was already in the vault, re-export so Obsidian reflects the edit too ("everywhere").
        if !outcome.updatedIDs.isEmpty {
            try? local.save()
            reexportEdited(outcome.updatedIDs, in: local, settings: settings)
        }
        return outcome.created
    }

    /// Re-export the vault markdown for rows a phone edit just changed — but only those already
    /// exported (`.done`), so we never push an un-reviewed note into the vault. Best-effort:
    /// an export failure is logged by the caller path, never fatal to the sweep.
    private static func reexportEdited(_ ids: [String], in context: ModelContext, settings: AppSettings) {
        let files = (try? context.fetch(FetchDescriptor<PipelineFile>(
            predicate: #Predicate { ids.contains($0.id) }))) ?? []
        // Locked rows are skipped outright (the exporter would refuse anyway — this keeps the
        // sweep quiet). A note UNLOCKED on the phone re-exports right here on the same sweep.
        // Trashed rows are skipped too — a note the phone just binned must not be re-written into
        // the vault (a restore clears `deletedAt`, so it re-exports on the sweep that restores it).
        for pf in files where pf.exportStatus == .done && !pf.locked && pf.deletedAt == nil {
            if let result = try? VaultExporter.export(pf, settings: settings) {
                pf.exported = result.markdownURL.path
                pf.lastActivityAt = Date()
            }
        }
        try? context.save()
    }
}
