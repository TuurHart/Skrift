import Foundation
import SwiftData
import CoreData
import AppKit
import os

extension Notification.Name {
    /// Posted after every reconcile sweep, so UI reading CLOUD memos directly (the Queue
    /// band's unrated list, the one-trash count) can live-refresh. Its rated sibling needs
    /// no notification: ingesting a rated memo changes `files.count`, which the sidebar
    /// already watches — which is precisely why UNRATED memos were the ones stuck until
    /// relaunch. Mirrors `.namesDidChangeFromSync`.
    static let cloudMemosDidChangeFromSync = Notification.Name("skrift.cloudMemosDidChangeFromSync")
}

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
            if importDone {
                // Q397 (ICLOUD_MERGE A1): the first finished import unlocks the backfill for
                // this store file (idempotent after that).
                CloudFirstImport.markDone(storeURL: AppPaths.memoCloudStoreFile,
                                          stampURL: AppPaths.memoCloudFirstImportStamp)
                Task { @MainActor in reconcileSoon(.cloudKitImport) }
            }
        }

        // App became active — the desktop analogue of the phone's foreground sweep.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in reconcileSoon(.activation) }
        }

        // Launch sweep — async, doesn't block App.init(). C52: coalesced like the other two, so
        // launch and the first activation (they fire together) run ONE sweep, not two.
        Task { @MainActor in reconcileSoon(.launch) }
    }

    /// Q397 (ICLOUD_MERGE A1): may the reconcile's backfill author yet? True once the cloud
    /// store has finished its first CloudKit import (`CloudFirstImport` stamp). DEBUG only:
    /// `-assumeFirstCloudImport` forces it on for headless runs, and the CloudKit-off perf
    /// library never imports, so it counts as done there.
    static var firstCloudImportDone: Bool {
        #if DEBUG
        if PerfLibrary.isActive || ProcessInfo.processInfo.arguments.contains("-assumeFirstCloudImport") {
            return true
        }
        #endif
        return CloudFirstImport.isDone(storeURL: AppPaths.memoCloudStoreFile,
                                       stampURL: AppPaths.memoCloudFirstImportStamp)
    }

    /// One pending sweep, re-armed per trigger (`ReconcileCoalescer`, C52): CloudKit import
    /// events land in bursts (see the phone's identical coalescing in CloudSyncMonitor), and
    /// each used to dispatch its own full-store sweep back-to-back. No timer anywhere: a sweep
    /// only ever follows a trigger.
    @MainActor static func reconcileSoon(_ trigger: ReconcileTrigger = .localChange) {
        let c = coalescer ?? ReconcileCoalescer { _ = reconcile() }
        coalescer = c
        c.request(trigger)
    }

    /// Pull every eligible synced memo into the local pipeline store, and reconcile the
    /// CloudKit names + vocabulary carriers into the Mac's local stores. No-op unless the user
    /// enabled CloudKit-Mac sync AND the CloudKit container is available. Returns the count of
    /// memos ingested.
    /// `deferIngest` (default, the app's triggers): never-seen memos ingest on a BACKGROUND
    /// context (blob reads + working-folder writes off the main actor), committed in one
    /// batch with one save (g-mac-pipeline G3, Q364). The headless harness passes false to
    /// get the old synchronous ingest, so its returned count is the rows just created.
    @discardableResult
    static func reconcile(deferIngest: Bool = true) -> Int {
        guard let cloud = MemoCloudStore.syncContainer else {
            // The Connections index sweep rides every reconcile trigger — even with cloud
            // sync off: locally-ingested files need indexing too.
            ConnectionsIndexService.shared.sweepSoon(SharedStore.container.mainContext)
            return 0
        }
        let settings = SettingsStore.shared.load()
        // Names (people + voiceprints) + custom vocab now flow over CloudKit (replacing the
        // Bonjour /api/names path). Both are guarded + idempotent, so running them on every
        // sweep is cheap; they converge with the phone through the shared merge.
        #if DEBUG
        let perfLibrary = PerfLibrary.isActive   // Q313: the perf library never runs the CloudKit carrier syncs
        #else
        let perfLibrary = false
        #endif
        if !perfLibrary {
            NamesCloudSync.run()
            VocabularyCloudSync.run()
            PolishPromptsCloudSync.run()
        }
        let local = SharedStore.container.mainContext
        // READ THROUGH A FRESH CONTEXT. A CloudKit import writes to the persistent STORE but does
        // NOT refresh `mainContext`'s already-registered `Memo` objects — so `cloud.mainContext`
        // returns STALE memos and the sweep never sees a phone's LATER delete / tag / edit (only a
        // first-seen memo is fresh — which is exactly why Mac→phone synced but phone→Mac didn't,
        // 2026-07-15 device test). A brand-new context has an empty row cache, so every fetch hits
        // the store and reads the latest import.
        let cloudContext = MemoCloudReconciler.freshCloudContext(cloud)
        let people = NamesStore.shared.livePeople()
        let thisDevice = DeviceID.current()
        // The sweep, the reflect save, and Q5 (2026-07-21): the Mac AUTHORS a Memo for any
        // local PipelineFile that doesn't have one yet (the +Upload button / drag-drop / folder
        // import — none of those mint a Memo at ingest time) and reflects a Mac-completed
        // transcript onto an already-authored Memo so it reaches the phone. One Memo fetch for
        // all of it (`MemoCloudReconciler.pass`). Author/reflect failures are logged inside and
        // never take down the ingest/reflect sweep this function exists for.
        let pass: PassOutcome
        do {
            pass = try MemoCloudReconciler.pass(from: cloudContext, into: local, people: people,
                                                author: settings.authorName, thisDeviceID: thisDevice,
                                                deferNewIngest: deferIngest,
                                                firstImportDone: firstCloudImportDone)
        } catch {
            AppLog.cloudkit.error("reconcile: pass FAILED: \(error)")
            MacSyncMonitor.shared.reportSweep(failure: error.localizedDescription)
            return 0
        }
        let outcome = pass.sweep
        // R40 / C168: a sweep that could not read the store pulled nothing. The sweep logged it;
        // the sync state shows it ("couldn't start" + this text as the detail line) until a
        // later sweep reads the store again. Nothing below has a snapshot to work from.
        MacSyncMonitor.shared.reportSweep(failure: outcome.fetchFailure)
        if outcome.fetchFailure != nil { return 0 }
        AppLog.cloudkit.log(
            "reconcile: ingested \(outcome.created, privacy: .public), pending \(outcome.pendingNewIDs.count, privacy: .public), reflected \(outcome.updatedIDs.count, privacy: .public), ingest-failures \(outcome.ingestFailures, privacy: .public)")
        if pass.authored > 0 || pass.reflectedTranscripts > 0 {
            AppLog.cloudkit.log(
                "reconcile: authored \(pass.authored, privacy: .public), reflected-transcripts \(pass.reflectedTranscripts, privacy: .public)")
        }
        // UNRATED memos never become a `PipelineFile`, so nothing about them changes
        // `files.count` — the one thing the sidebar watched. A phone memo you hadn't
        // rated therefore stayed invisible on the Mac until the app was RELAUNCHED
        // (Tuur, 2026-07-27: "I restarted it and now the note arrived"). Announce every
        // sweep so surfaces that read cloud memos directly — the Queue band's unrated
        // list / one-trash count — refresh live. Cheap: the observers just re-fetch.
        NotificationCenter.default.post(name: .cloudMemosDidChangeFromSync, object: nil)
        // A phone edit re-linked + recompiled an existing row (Part B, saved by the pass). If it
        // was already in the vault, re-export so Obsidian reflects the edit too ("everywhere").
        if !outcome.updatedIDs.isEmpty {
            reexportEdited(outcome.updatedIDs, in: local, cloud: cloudContext, settings: settings)
        }
        // The lifecycle sweep reuses this pass's memo snapshot on an open (G12) instead of its
        // own full fetch; it still runs only when a person opened the app (v3 doctrine).
        LifecycleSweepScheduler.reconcileDidFetch(memos: pass.memos, context: cloudContext)
        // The Connections index sweep, AFTER the cloud work, so just-imported memos index in
        // the same pass — from the rows + memos this pass already fetched (G11). Self-gated
        // (consent + model on disk) and hash-diffed ⇒ a redundant fire is nearly free.
        ConnectionsIndexService.shared.sweepSoon(
            local, reuse: .init(files: pass.localFiles, memos: pass.memos, enhancements: pass.enhancements))

        if !outcome.pendingNewIDs.isEmpty {
            ingestInBackground(outcome.pendingNewIDs, container: cloud, people: people,
                               author: settings.authorName, thisDeviceID: thisDevice)
        }
        if !perfLibrary {
            adoptOrphanedTranscriptions(pass.memos, container: cloud, context: cloudContext,
                                        thisDevice: thisDevice)
        }
        return outcome.created
    }

    /// C264 backstop: a memo another device left `.transcribing` and went quiet on for 30
    /// minutes (`OrphanedTranscribing`) is transcribed here from its synced audio, so it never
    /// spins forever. User-edited ones are only released (C263). Skipped while a pipeline run
    /// holds the engine; the next reconcile retries.
    private static func adoptOrphanedTranscriptions(_ memos: [Memo], container: ModelContainer,
                                                    context: ModelContext, thisDevice: String) {
        let kinds = AssetKindIndex(context)
        let plan = MacOrphanTranscription.plan(
            memos: memos, hasAudio: { kinds.kinds($0).contains(MemoAsset.Kind.audio) },
            thisDevice: thisDevice, now: Date())
        if !plan.release.isEmpty {
            do { try MacOrphanTranscription.release(plan.release, in: context) }
            catch { AppLog.cloudkit.error("reconcile: orphan release FAILED: \(error)") }
        }
        guard !plan.rerun.isEmpty, !TranscriptionActivity.isActive else { return }
        Task { @MainActor in
            TranscriptionActivity.begin()
            let landed = await MacOrphanTranscription.adopt(plan.rerun, in: ModelContext(container),
                                                            transcriber: TranscriptionService.shared,
                                                            thisDevice: thisDevice)
            TranscriptionActivity.end()
            // Nothing else loaded the model for this, so nothing else would free it.
            if !TranscriptionActivity.isActive { await TranscriptionService.shared.unload() }
            AppLog.cloudkit.log(
                "reconcile: adopted \(landed, privacy: .public) of \(plan.rerun.count, privacy: .public) orphaned transcription(s)")
            if landed > 0 { reconcileSoon() }
        }
    }

    /// G3: read the new memos' blobs + write their working folders on a background context,
    /// then insert all rows on the main actor with ONE save. `ingestInFlight` keeps an
    /// overlapping sweep from ingesting the same memo meanwhile.
    private static let backgroundIngestBatch = 50

    private static func ingestInBackground(_ ids: [UUID], container: ModelContainer, people: [Person],
                                           author: String, thisDeviceID: String) {
        ingestInFlight.formUnion(ids)
        let upload = UploadService()
        Task { @MainActor in
            let local = SharedStore.container.mainContext
            var created = 0
            // Batches of 50: each gets a fresh background context (so at most 50 memos' blobs
            // are held at once on a first-enable backlog) and ONE main-actor save.
            for start in stride(from: 0, to: ids.count, by: backgroundIngestBatch) {
                let chunk = Array(ids[start..<min(start + backgroundIngestBatch, ids.count)])
                let prepared = await MemoCloudReconciler.prepareInBackground(ids: chunk, container: container,
                                                                             upload: upload)
                let outcome = MemoCloudReconciler.commitPrepared(prepared, cloud: ModelContext(container),
                                                                 into: local, people: people, author: author,
                                                                 thisDeviceID: thisDeviceID, upload: upload)
                ingestInFlight.subtract(chunk)
                created += outcome.created
                AppLog.cloudkit.log(
                    "reconcile: background ingest \(outcome.created, privacy: .public) of \(chunk.count, privacy: .public), stranded \(outcome.stranded, privacy: .public), ingest-failures \(outcome.ingestFailures, privacy: .public)")
                NotificationCenter.default.post(name: .cloudMemosDidChangeFromSync, object: nil)
            }
            if created > 0 { ConnectionsIndexService.shared.sweepSoon(local) }
        }
    }

    /// Re-export the vault markdown for rows a phone edit just changed — but only those already
    /// exported (`.done`), so we never push an un-reviewed note into the vault. Best-effort:
    /// a failed export is logged RIGHT HERE (nothing upstream logs it), never fatal to the sweep.
    private static func reexportEdited(_ ids: [String], in context: ModelContext,
                                       cloud: ModelContext, settings: AppSettings) {
        let files = (try? context.fetch(FetchDescriptor<PipelineFile>(
            predicate: #Predicate { ids.contains($0.id) }))) ?? []
        // The SAME gate a person's Export press passes (`ExportGate`, Q156: this used to
        // check locked + trashed only, so a note whose rating the phone withdrew was still
        // re-written). A refused row is skipped quietly: locked (a note UNLOCKED on the phone
        // re-exports on the same sweep), trashed (a note the phone just binned must not be
        // re-written; a restore clears `deletedAt`), unrated, held with two versions.
        // One export run for the whole sweep (Q365): ledger + names decoded once, ledger written once.
        let session = ExportSession()
        defer { session.finish() }
        for pf in files where pf.exportStatus == .done {
            if let failure = VaultExporter.fullGateFailure(for: pf, cloud: cloud, settings: settings, session: session) {
                AppLog.cloudkit
                    .info("re-export skipped \(pf.id, privacy: .public): gate \(String(describing: failure), privacy: .public)")
                continue
            }
            do {
                let result = try VaultExporter.export(pf, settings: settings, session: session)
                // The engine's refusals are the CONTRACT working, not failures: a
                // vault-edited note stays the user's, a filed-away note stays where
                // they put it. Only a real write updates the recorded path.
                if result.outcome.isWrittenOrCurrent {
                    pf.exported = result.markdownURL.path
                    pf.lastActivityAt = Date()
                } else {
                    AppLog.cloudkit
                        .info("re-export skipped \(pf.id, privacy: .public): \(String(describing: result.outcome), privacy: .public)")
                }
            } catch {
                AppLog.cloudkit
                    .error("re-export FAILED \(pf.id, privacy: .public) — vault now stale for this note: \(error)")
            }
        }
        do { try context.save() }
        catch {
            AppLog.cloudkit
                .error("re-export save FAILED: \(error)")
        }
    }
}
