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
        // all of it (`ReconcileV2.pass`). Author/reflect failures are logged inside and
        // never take down the ingest/reflect sweep this function exists for.
        // C159/C283 (Q489): a roster change since the last pass (synced in above, or a Mac names
        // edit) re-links every processed row once, BEFORE the sweep, so every row is linked with
        // the roster the sweep reflects with. The rows already in the vault are re-exported after
        // it, with the phone-edited ones, through the same gate and the engine's edit guard. The
        // row fetch happens only when the roster did change.
        var relinked: [String] = []
        if RosterRelink.hasChanged(people) {
            relinked = RosterRelink.runIfChanged((try? local.fetch(FetchDescriptor<PipelineFile>())) ?? [],
                                                 people: people, author: settings.authorName)
            if !relinked.isEmpty {
                AppLog.cloudkit.log("reconcile: roster changed, re-linked \(relinked.count, privacy: .public) notes")
                try? local.save()
            }
        }
        // Q431 (C2): the pass is reconcile v2 (`Shared/ReconcileV2`); v1 stays in place until
        // Q432 deletes it. The carriers above ran first (C185), the roster re-link too.
        let (context, pass) = v2Pass(cloud: cloudContext, local: local, people: people, author: settings.authorName,
                                     thisDevice: thisDevice, outputDir: AppPaths.audioOutputDirectory,
                                     firstImportDone: firstCloudImportDone, deferIngest: deferIngest)
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
        let reexport = Array(Set(pass.reexportIDs).union(relinked))
        if !reexport.isEmpty {
            reexportEdited(reexport, in: local, cloud: cloudContext, settings: settings)
        }
        // The lifecycle sweep reuses this pass's memo snapshot on an open (G12) instead of its
        // own full fetch; it still runs only when a person opened the app (v3 doctrine).
        LifecycleSweepScheduler.reconcileDidFetch(memos: pass.snapshot.allMemos, context: cloudContext)
        // The Connections index sweep, AFTER the cloud work, so just-imported memos index in
        // the same pass — from the rows + memos this pass already fetched (G11). Self-gated
        // (consent + model on disk) and hash-diffed ⇒ a redundant fire is nearly free.
        ConnectionsIndexService.shared.sweepSoon(
            local, reuse: .init(files: pass.snapshot.rows, memos: pass.snapshot.allMemos,
                                enhancements: pass.snapshot.enhancements))

        if !outcome.pendingNewIDs.isEmpty {
            ingestInBackground(outcome.pendingNewIDs, container: cloud, context: context)
        }
        if !perfLibrary {
            adoptOrphanedTranscriptions(pass.snapshot.allMemos, container: cloud, context: cloudContext,
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
        let assets = ReconcileV2.AssetIndex(context)
        let plan = MacOrphanTranscription.plan(
            memos: memos, hasAudio: { assets.has($0, MemoAsset.Kind.audio, minBytes: 0) },
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

    /// G3: read the new memos' blobs + write their working folders on a background context
    /// (`ReconcileV2.Ingest.prepare`, file work only), then make the rows on the main actor in
    /// one synchronous block with ONE save (`ReconcileV2.Ingest.commit`, C294). The in-flight set
    /// keeps an overlapping pass from ingesting the same memo or trashing its row meanwhile.
    private static let backgroundIngestBatch = 50

    /// D218 (C155): the Mac's copy (`SyncHealth.copyVerb`) after an iCloud switch. Adopts the new
    /// account (syncing resumes), then every live row of this Mac becomes a memo there. Only on
    /// his tap; the next sweep reconciles as usual.
    @MainActor static func copyToCurrentAccount() {
        SyncHealthMonitor.shared.adoptCurrentAccount()
        guard let cloud = MemoCloudStore.syncContainer else {
            AppLog.cloudkit.error("account copy: no cloud store (sync off or still stopped)")
            return
        }
        let local = SharedStore.container.mainContext
        let rows = (try? local.fetch(FetchDescriptor<PipelineFile>())) ?? []
        let copied = ReconcileV2.AccountCopy.copy(rows, into: ModelContext(cloud), deviceID: DeviceID.current())
        try? local.save()
        AppLog.cloudkit.log("account copy: \(copied, privacy: .public) notes into the new account")
        reconcileSoon()
    }

    /// The Mac's live notes (what an account switch leaves here), for the What now sheet.
    @MainActor static func liveRowCount() -> Int {
        (try? SharedStore.container.mainContext.fetchCount(
            FetchDescriptor<PipelineFile>(predicate: #Predicate { $0.deletedAt == nil }))) ?? 0
    }

    /// The pass exactly as `reconcile()` runs it (the headless `-reconcilepass` check runs it too).
    static func v2Pass(cloud: ModelContext, local: ModelContext, people: [Person], author: String,
                       thisDevice: String, outputDir: URL, firstImportDone: Bool,
                       deferIngest: Bool) -> (ReconcileV2.Context, ReconcileV2.PassOutcome) {
        let context = ReconcileV2.Context(people: people, author: author, thisDeviceID: thisDevice, now: Date(),
                                          outputDir: outputDir, inFlight: ReconcileV2.ingestInFlight)
        return (context, ReconcileV2.pass(cloud: cloud, local: local, context: context,
                                          firstImportDone: firstImportDone, deferNew: deferIngest,
                                          syncStopped: SyncStopFlag.isStopped))
    }

    /// Returns the ingest's task (rows created), so a headless check can wait for it.
    @discardableResult
    static func ingestInBackground(_ ids: [UUID], container: ModelContainer,
                                   local given: ModelContext? = nil,
                                   context: ReconcileV2.Context, indexAfter: Bool = true) -> Task<Int, Never> {
        ReconcileV2.ingestInFlight.formUnion(ids)
        let outputDir = context.outputDir
        return Task { @MainActor in
            let local = given ?? SharedStore.container.mainContext
            var created = 0
            // Batches of 50: each gets a fresh background context (so at most 50 memos' blobs
            // are held at once on a first-enable backlog) and ONE main-actor save.
            for start in stride(from: 0, to: ids.count, by: backgroundIngestBatch) {
                let chunk = Array(ids[start..<min(start + backgroundIngestBatch, ids.count)])
                let attempts = await Task.detached(priority: .userInitiated) { () -> [ReconcileV2.Ingest.Attempt] in
                    let bg = ModelContext(container)
                    let memos = (try? bg.fetch(FetchDescriptor<Memo>(predicate: #Predicate { chunk.contains($0.id) }))) ?? []
                    let byID = Dictionary(memos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    return chunk.map { id in
                        guard let memo = byID[id] else { return .waiting(id) }
                        let assets = (try? bg.fetch(FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == id }))) ?? []
                        return ReconcileV2.Ingest.attempt(id) { try ReconcileV2.Ingest.prepare(memo, assets: assets, outputDir: outputDir) }
                    }
                }.value
                // Fresh memos and polish, read now: a memo trashed or un-rated meanwhile is skipped.
                let cloud = ModelContext(container)
                let memos = MemoDuplicates.canonicalRows((try? cloud.fetch(FetchDescriptor<Memo>(
                    predicate: #Predicate { chunk.contains($0.id) }))) ?? [])
                let enhancements = (try? cloud.fetch(FetchDescriptor<MemoEnhancement>(
                    predicate: #Predicate { chunk.contains($0.memoID) }))) ?? []
                var outcome = ReconcileV2.Outcome()
                ReconcileV2.Ingest.commit(attempts, memos: memos,
                                          enhancements: Dictionary(enhancements.map { ($0.memoID, $0) },
                                                                   uniquingKeysWith: { a, _ in a }),
                                          into: local, context: context, outcome: &outcome, save: true)
                ReconcileV2.ingestInFlight.subtract(chunk)
                created += outcome.created
                AppLog.cloudkit.log(
                    "reconcile: background ingest \(outcome.created, privacy: .public) of \(chunk.count, privacy: .public), stranded \(outcome.stranded, privacy: .public), ingest-failures \(outcome.ingestFailures, privacy: .public)")
                NotificationCenter.default.post(name: .cloudMemosDidChangeFromSync, object: nil)
            }
            if created > 0, indexAfter { ConnectionsIndexService.shared.sweepSoon(local) }
            return created
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
