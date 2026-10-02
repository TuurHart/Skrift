import SwiftUI
import SwiftData
import os

/// Drives the auto-run pipeline over SwiftData `PipelineFile`s and the Obsidian
/// export. Wraps `BatchRunner` with the real engines, persists each file as it
/// completes, and publishes live run progress for the sidebar.
@MainActor
@Observable
final class ProcessingCoordinator {
    struct RunState: Equatable {
        var total: Int
        var done: Int
        var currentTitle: String?
        /// Non-nil while a model is loading/downloading (shown before processing).
        var loadingLabel: String?
        /// Download fraction 0…1; nil = indeterminate (loading from cache).
        var loadingFraction: Double?
    }

    private(set) var runState: RunState?
    /// A run is live exactly while `runState` is set (`beginRun`/`endRun` pair them).
    var isRunning: Bool { runState != nil }
    private static let busyMessage = "A run is already going — wait for it to finish."
    var lastError: String?
    /// What the last import did (Q137 / C199): shown as a dismissible banner at the top of the
    /// notes list, so a drop with no note open still says what happened. Only set when
    /// something was skipped or failed.
    var importReport: ImportReport?
    /// Transient confirmation banner (auto-clears) — shown by RootView so an action
    /// like Export gives visible feedback (N5).
    var toast: String?
    private var toastToken = 0
    /// True while the ASR/LLM weights are resident in memory — drives the sidebar
    /// engine dots (green = loaded, dim = idle/unloaded) so they reflect reality.
    private(set) var modelsLoaded = false

    // Engine seam — the real FluidAudio/MLX services.
    private let transcriber: Transcribing = TranscriptionService.shared
    private let enhancer: Enhancing = EnhancementService.shared
    private let diarizer: Diarizing? = DiarizationService.shared

    /// Frees the ~9 GB of model weights after the queue goes idle (the Python app
    /// did this). Cancelled when a run starts, rescheduled when it ends.
    private var idleUnloadTask: Task<Void, Never>?
    private static let idleUnloadDelay: Duration = .seconds(60)

    #if DEBUG
    /// Snapshot helper — a coordinator with a preset run state for verification.
    static func preview(_ rs: RunState) -> ProcessingCoordinator {
        let c = ProcessingCoordinator(); c.runState = rs; return c
    }
    #endif

    /// A file still needs the auto-run until it reaches Ready (enhance done). A
    /// soft-deleted (Recently Deleted) file is never processed, and — the
    /// unrated-take doctrine, 2026-07-28 — neither is an unrated Mac recording:
    /// "pressing process shouldn't enhance unrated notes… do it the same as the
    /// phone" (Tuur). Forwards to the pure `WayOutRules` copy so the MLX-free
    /// `SkriftDesktopTests` target (which doesn't compile this class) can test
    /// the actual logic directly.
    func needsProcessing(_ pf: PipelineFile) -> Bool {
        WayOutRules.needsProcessing(pf) && !EditConflictHold.isHeld(pf.id)   // D139: two versions → wait for the pick
    }

    /// On launch, recover notes stranded mid-run by a crash/quit (a `.processing`
    /// step with no run actually active) so the queue can pick them up again. A
    /// pilot found such notes stuck showing "Enhancing" forever.
    func reconcileInterruptedRuns(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<PipelineFile>())) ?? []
        if RunReconciler.resetInterrupted(all) { try? context.save() }
    }

    // ── Process (transcribe → enhance → tag → name-link → compile) ──
    /// `retranscribeIDs` — files in `fileIDs` that must force a fresh ASR pass even
    /// though their `transcribeStatus` is already `.done` (the ⋯ menu's "Re-transcribe",
    /// C51/R9). Normal auto-run processing passes none.
    func process(fileIDs: [String], context: ModelContext, retranscribeIDs: Set<String> = []) async {
        await submit(.process(ids: fileIDs, retranscribe: retranscribeIDs), context: context, announce: true)
    }

    // ── One run at a time; everything else WAITS (Q77) ──
    // A request that arrives mid-run used to be refused ("A run is already going") or, for an
    // import's own transcription, dropped without a word — so with several memos only the first
    // right-click Process took ("worked flaky", Tuur 2026-09-30). It now queues in `waiting`
    // and the caller that owns the live run drains it, oldest first, before letting go. A Redo
    // takes the same slot (`turn.acquire()`) and drains the same way (Q208).
    private var turn = RunTurn()

    private func submit(_ job: RunQueue.Job, context: ModelContext, announce: Bool) async {
        guard turn.request(job) else {
            if announce { flash("Queued — starts when the current run finishes") }
            return
        }
        await run(job, context: context)
        await drainWaiting(context: context)
    }

    /// Holder of the run slot only: run every waiting job, oldest first, then release the slot.
    private func drainWaiting(context: ModelContext) async {
        while let next = turn.advance() { await run(next, context: context) }
    }

    private func run(_ job: RunQueue.Job, context: ModelContext) async {
        switch job {
        case .process(let ids, let retranscribe):
            await runProcess(fileIDs: ids, context: context, retranscribeIDs: retranscribe)
        case .transcribe(let ids):
            await runTranscribe(fileIDs: ids, context: context)
        case .split(let id):
            await runSplit(id: id, context: context)
        }
    }

    /// Start of every run: keep the models resident, publish the run bar, and tell the shared
    /// embedder to yield the ANE/GPU (the phone's 2026-07-15 starvation lesson).
    private func beginRun(total: Int, currentTitle: String? = nil) {
        idleUnloadTask?.cancel(); idleUnloadTask = nil   // don't unload mid-run
        runState = RunState(total: total, done: 0, currentTitle: currentTitle)
        TranscriptionActivity.begin()
    }

    /// End of every run. `sweepContext` = the run produced fresh transcripts/polish, so index
    /// them (a transcribe-only run does not).
    private func endRun(sweepContext: ModelContext? = nil) {
        runState = nil; scheduleIdleUnload()
        TranscriptionActivity.end()
        if let sweepContext { ConnectionsIndexService.shared.sweepSoon(sweepContext) }
    }

    private func runProcess(fileIDs: [String], context: ModelContext, retranscribeIDs: Set<String> = [],
                            splitIDs: Set<String> = []) async {
        let all = (try? context.fetch(FetchDescriptor<PipelineFile>())) ?? []
        let targets = all
            // A split re-runs a note that is already Ready, so it bypasses the "still needs
            // processing" gate (only a trashed note is refused).
            .filter { fileIDs.contains($0.id) && (needsProcessing($0) || (splitIDs.contains($0.id) && $0.deletedAt == nil)) }
            .sorted { $0.uploadedAt < $1.uploadedAt }   // oldest first, like the backend
        guard !targets.isEmpty else { return }

        beginRun(total: targets.count)
        defer { endRun(sweepContext: context) }   // fresh transcripts/polish just landed — index them

        let settings = SettingsStore.shared.load()
        // Scan the vault for existing tag names so TagMatcher suggests real vault
        // tags (off the main actor — file I/O). Empty when no vault is configured.
        let vaultRoot = settings.noteFolder
        let tagWhitelist: [String] = vaultRoot.isEmpty ? [] : await Task.detached(priority: .utility) {
            VaultTagScanner.scan(root: URL(fileURLWithPath: vaultRoot))
        }.value
        // Seed the roster from the vault's People/ note titles (NAMING_MODEL.md decision 5):
        // the optional Obsidian seed for the portable names DB, so opt-out auto-links people
        // the user already keeps a note for. Privacy: titles only, app code, no AI — the
        // scanner lists filenames off the main actor and never reads a note's body.
        if !vaultRoot.isEmpty {
            let titles = await Task.detached(priority: .utility) {
                PeopleFolderScanner.titles(vaultRoot: URL(fileURLWithPath: vaultRoot))
            }.value
            NamesStore.shared.seedRoster(titles: titles)
        }
        let runner = BatchRunner(
            transcriber: transcriber,
            enhancer: enhancer,
            settings: settings,
            people: NamesStore.shared.livePeople(),
            tagWhitelist: tagWhitelist,
            diarizer: diarizer
        )

        // Pre-load the engines up front so the first run shows download/load
        // progress in the run bar (instant when the models are already cached).
        let needsAudio = targets.contains {
            $0.sourceType == .audio && !$0.path.isEmpty && FileManager.default.fileExists(atPath: $0.path)
        }
        // Show the load banner only when the models aren't already resident —
        // ensureLoaded is a no-op when cached, so a "Loading…" flash on every run
        // was misleading (#31).
        let showLoad = !modelsLoaded
        do {
            if needsAudio {
                if showLoad { runState?.loadingLabel = SharedCopy.processingStep("transcription model", 1, of: 2) }
                try await TranscriptionService.shared.ensureLoaded { f in
                    Task { @MainActor in if showLoad { self.runState?.loadingFraction = f } }
                }
            }
            if showLoad {
                // "1 of 2" / "2 of 2" only when both models load this run.
                runState?.loadingLabel = needsAudio ? SharedCopy.processingStep("enhancement model", 2, of: 2) : "enhancement model"
                runState?.loadingFraction = nil
            }
            try await EnhancementService.shared.ensureLoaded(modelRepo: settings.enhancementModelRepo) { f in
                Task { @MainActor in if showLoad { self.runState?.loadingFraction = f } }
            }
        } catch {
            lastError = "Model load failed: \(error.localizedDescription)"
            return   // defer ends the run
        }
        if showLoad { runState?.loadingLabel = nil; runState?.loadingFraction = nil }
        modelsLoaded = true

        for pf in targets {
            runState?.currentTitle = pf.queueTitle
            // Captures: pf.path is the working folder, not an audio file — don't
            // pass it as an audioURL (BatchRunner ignores it, but nil is cleaner).
            let hasAudio = pf.sourceType == .audio && !pf.path.isEmpty
                && FileManager.default.fileExists(atPath: pf.path)
            let audioURL = hasAudio ? URL(fileURLWithPath: pf.path) : nil
            let isSplit = splitIDs.contains(pf.id)
            var cancelCheck: (@Sendable () -> Bool)? = nil
            if isSplit, let flag = splitFlags[pf.id] { cancelCheck = { flag.isCancelled } }
            do {
                try await runner.run(pf, audioURL: audioURL,
                                     imageManifest: hasAudio ? Self.imageManifest(for: pf.path) : [],
                                     clipStarts: hasAudio ? IngestService.clipStarts(forAudioAt: pf.path) : [],
                                     retranscribe: retranscribeIDs.contains(pf.id),
                                     requireSplit: isSplit,
                                     cancelCheck: cancelCheck)
                if pf.sanitised != nil { pf.sanitiseStatus = .done }
                pf.error = nil
                pf.lastActivityAt = Date()
                if isSplit { finishSplit(pf, error: nil, context: context) }
            } catch {
                if isSplit, let e = error as? BatchRunnerError, e == .oneVoice || e == .cancelled {
                    // Not a failure: the note is untouched (BatchRunner decided before writing).
                    finishSplit(pf, error: e, context: context)
                    try? context.save()
                    runState?.done += 1
                    continue
                }
                if isSplit { finishSplit(pf, error: error, context: context) }
                pf.error = String(describing: error)
                // A missing audio file is always a TRANSCRIBE error (C51/R9), even when an
                // older transcript is still sitting on the row (a re-transcribe whose audio
                // vanished mid-race) — the emptiness heuristic below is for every other failure.
                if error is BatchRunnerError { pf.transcribeStatus = .error }
                else if (pf.transcript ?? "").isEmpty { pf.transcribeStatus = .error }
                else { pf.enhanceStatus = .error }
                lastError = "Processing failed: \(error.localizedDescription)"
            }
            try? context.save()
            writeBackEnhancement(pf)
            runState?.done += 1
        }
    }

    /// CAPTURE a just-recorded file: transcribe (+ diarize) and stop. The phone does exactly
    /// this the moment you stop recording, and the Mac now matches it — a recording is UNRATED,
    /// so `process()` will never touch it, and without this it would sit wordless forever.
    ///
    /// Only the transcription model is loaded; the enhancement model stays cold, because
    /// nothing here enhances. The transcript is reflected onto the synced `Memo` so the words
    /// reach the phone like any other capture.
    func transcribe(fileIDs: [String], context: ModelContext) async {
        // Automatic, not a button press, so no banner — but never dropped: it waits its turn.
        await submit(.transcribe(ids: fileIDs), context: context, announce: false)
    }

    private func runTranscribe(fileIDs: [String], context: ModelContext) async {
        let all = (try? context.fetch(FetchDescriptor<PipelineFile>())) ?? []
        let targets = all.filter { fileIDs.contains($0.id) && $0.transcribeStatus != .done }
        guard !targets.isEmpty else { return }

        beginRun(total: targets.count)
        defer { endRun() }

        runState?.loadingLabel = modelsLoaded ? nil : "transcription model"
        do {
            try await TranscriptionService.shared.ensureLoaded { f in
                Task { @MainActor in self.runState?.loadingFraction = f }
            }
        } catch {
            lastError = "Transcription model failed to load: \(error.localizedDescription)"
            return
        }
        runState?.loadingLabel = nil; runState?.loadingFraction = nil

        let settings = SettingsStore.shared.load()
        let runner = BatchRunner(transcriber: transcriber, enhancer: enhancer, settings: settings,
                                 people: NamesStore.shared.livePeople(), tagWhitelist: [],
                                 diarizer: diarizer)
        for pf in targets {
            runState?.currentTitle = pf.queueTitle
            let hasAudio = !pf.path.isEmpty && FileManager.default.fileExists(atPath: pf.path)
            do {
                try await runner.run(pf, audioURL: hasAudio ? URL(fileURLWithPath: pf.path) : nil,
                                     imageManifest: hasAudio ? Self.imageManifest(for: pf.path) : [],
                                     clipStarts: hasAudio ? IngestService.clipStarts(forAudioAt: pf.path) : [],
                                     stopAfterTranscribe: true)
                pf.error = nil
                pf.lastActivityAt = Date()
            } catch {
                pf.error = String(describing: error)
                pf.transcribeStatus = .error
                lastError = "Transcription failed: \(error.localizedDescription)"
            }
            try? context.save()
            runState?.done += 1
        }
        // Push the words onto the synced Memos so they reach the phone.
        if let cloudCtx = MemoCloudStore.container?.mainContext {
            let reflected = (try? MacMemoAuthor.reflectTranscripts(files: targets, into: cloudCtx)) ?? 0
            try? cloudCtx.save()
            // The quiet sidebar row renders the MEMO (`WayOutRules.displayTitle` over
            // the sidebar's own fetched array), while the pane renders this row live —
            // two channels. The reflect above just gave the memo its real words, so
            // ANNOUNCE it the way the reconcile sweep does, or the row keeps saying
            // "Voice note" until some unrelated refresh lands (ROUND 9 item 3's
            // "weird lag": same title, two arrival times).
            if reflected > 0 {
                NotificationCenter.default.post(name: .cloudMemosDidChangeFromSync, object: nil)
            }
        }
    }

    /// Sync the Mac's polish for a just-enhanced memo-sourced file back to the phone via
    /// CloudKit (MAC_CLOUDKIT_PLAN.md 8c). No-op unless the user opted into CloudKit-Mac sync
    /// (same gate as the reconcile loop — a Mac with iCloud configured but the toggle OFF must
    /// not touch CloudKit), the container is available, and the file is a synced memo. The
    /// phone's MemoExporter already prefers the resulting MemoEnhancement over the raw
    /// transcript, so a paired Mac auto-upgrades its export.
    private func writeBackEnhancement(_ pf: PipelineFile) {
        guard pf.enhanceStatus == .done,
              SettingsStore.shared.load().cloudKitMacSyncEnabled,
              let container = MemoCloudStore.container else { return }
        // Don't swallow CloudKit failures silently — a lost write-back means the phone
        // never sees the polish. Log it so it's diagnosable (a durable retry queue is the
        // documented Phase-2 follow-up). A `nil` return is an intentional skip (not a synced
        // memo / nothing to write), not a failure.
        do {
            // `passRan: true` — the guard above already proved `enhanceStatus == .done`,
            // so reaching here IS "a pass ran on this file", empty result or not.
            try MacCloudWriteBack.upsert(for: pf, into: container.mainContext,
                                         deviceID: DeviceID.current(), passRan: true)
        } catch {
            Logger(subsystem: "com.skrift.desktop", category: "cloudkit")
                .error("write-back failed for \(pf.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// The per-file `image_manifest.json` next to the audio (written by phone uploads
    /// and by video ingest) — fed to the transcriber so `[[img_NNN]]` markers land in
    /// the transcript at the right words. Empty when absent/unreadable (no images).
    private static func imageManifest(for path: String) -> [ImageManifestEntry] {
        guard !path.isEmpty else { return [] }
        let url = URL(fileURLWithPath: path).deletingLastPathComponent()
            .appendingPathComponent("image_manifest.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ImageManifestEntry].self, from: data)) ?? []
    }

    /// After the queue is idle for `idleUnloadDelay`, free the ASR + LLM weights so
    /// they don't sit pinned (~9 GB) for the rest of the session. Reloads lazily on
    /// the next run.
    private func scheduleIdleUnload() {
        idleUnloadTask?.cancel()
        idleUnloadTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleUnloadDelay)
            if Task.isCancelled { return }
            await TranscriptionService.shared.unload()
            await EnhancementService.shared.unload()
            self?.modelsLoaded = false
            self?.idleUnloadTask = nil
        }
    }

    // ── Split speakers (Q87, mock Q86-split-speakers.html) ──
    // A per-note switch: ON = the Mac listens again (fresh ASR + diarization) and writes the
    // note as turns. Rides the same one-run-at-a-time queue as Process (`RunQueue`, Q77), shows a
    // ticking time instead of a fake percentage, and can be cancelled. A run that finds one voice
    // writes NOTHING (`BatchRunnerError.oneVoice`).

    enum SplitPhase: Equatable {
        case waiting                    // queued behind another run
        case running(since: Date)       // drives the ticking m:ss
    }
    /// Notes with a split in flight. Observed by the header switch + the body.
    private(set) var splitPhases: [String: SplitPhase] = [:]
    /// The one-line result under the switch ("Only one voice found…", "Cancelled…"); self-clearing.
    private(set) var splitNotices: [String: String] = [:]
    private var splitNoticeTokens: [String: Int] = [:]
    private var splitFlags: [String: SplitCancelFlag] = [:]

    #if DEBUG
    /// Snapshot helper: force the split progress / notice states for the headless renders.
    func debugSetSplit(id: String, phase: SplitPhase?, notice: String? = nil) {
        splitPhases[id] = phase
        splitNotices[id] = notice
    }
    #endif

    /// Turn Split speakers ON for a note (the confirm was already answered).
    func splitSpeakers(_ pf: PipelineFile, context: ModelContext) async {
        guard splitPhases[pf.id] == nil, pf.sourceType == .audio, NoteConsent.isRated(pf) else { return }
        splitNotices[pf.id] = nil
        SplitSpeakers.request(pf)                 // C102: the per-note opt-in
        try? context.save()
        splitPhases[pf.id] = .waiting
        splitFlags[pf.id] = SplitCancelFlag()
        await submit(.split(id: pf.id), context: context, announce: false)
    }

    private func runSplit(id: String, context: ModelContext) async {
        // Cancelled while it waited in the queue.
        guard splitPhases[id] != nil, splitFlags[id]?.isCancelled != true else {
            splitPhases[id] = nil; splitFlags[id] = nil; return
        }
        splitPhases[id] = .running(since: Date())
        await runProcess(fileIDs: [id], context: context, retranscribeIDs: [id], splitIDs: [id])
        splitPhases[id] = nil          // whatever happened, the spinner is over
        splitFlags[id] = nil
    }

    /// Cancel: a waiting split leaves the queue; a running one is abandoned at its next
    /// checkpoint, and the note is exactly as it was because nothing is written until then.
    func cancelSplit(_ pf: PipelineFile, context: ModelContext) {
        guard splitPhases[pf.id] != nil else { return }
        splitFlags[pf.id]?.cancel()
        turn.removeSplit(id: pf.id)
        splitPhases[pf.id] = nil
        SplitSpeakers.withdraw(pf)
        try? context.save()
        setSplitNotice(pf.id, SplitSpeakersCopy.cancelled)
    }

    private func finishSplit(_ pf: PipelineFile, error: Error?, context: ModelContext) {
        let userCancelled = splitFlags[pf.id]?.isCancelled == true
        let outcome = SplitSpeakers.settle(pf, error: error)
        switch outcome {
        case .split:
            reflectSplitToMemo(pf)
        case .oneVoice:
            if !userCancelled { setSplitNotice(pf.id, SplitSpeakersCopy.oneVoice) }
        case .cancelled, .failed:
            break
        }
        try? context.save()
    }

    private func setSplitNotice(_ id: String, _ text: String) {
        splitNotices[id] = text
        splitNoticeTokens[id, default: 0] += 1
        let token = splitNoticeTokens[id]
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            // Only the latest notice for this note clears itself (same idea as `flash`).
            if self?.splitNoticeTokens[id] == token { self?.splitNotices[id] = nil }
        }
    }

    /// The split/flatten is a deliberate change of the note's words: put it on the synced Memo,
    /// or the next reflect sweep puts the old flat transcript back (`SplitSpeakers.reflectTranscript`).
    private func reflectSplitToMemo(_ pf: PipelineFile) {
        guard SettingsStore.shared.load().cloudKitMacSyncEnabled,
              let cloud = MemoCloudStore.container?.mainContext else { return }
        SplitSpeakers.reflectTranscript(of: pf, into: cloud)
    }

    /// Name a speaker from the gutter: ALL of their turns take `name`, the person is created in
    /// Names when new, the body is re-linked (full name on the first turn, short after), and — for
    /// a "Speaker N" whose audio we still have — the voice is learned from this note.
    func nameSpeaker(_ pf: PipelineFile, displayed: String, as name: String, context: ModelContext) {
        let before = NamesStore.shared.livePeople()
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let known = before.first { NamesMerge.keyName($0.canonical).localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
        if known == nil {
            let first = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
            NamesStore.shared.upsert(canonical: trimmed, aliases: [trimmed, first], short: first)
        }
        let canonical = known.map { NamesMerge.keyName($0.canonical) } ?? trimmed
        let slot = Self.diarizationSlot(of: displayed)
        guard SplitSpeakers.nameSpeaker(pf, displayed: displayed, as: canonical,
                                        people: NamesStore.shared.livePeople()) else { return }
        resanitiseForNames(pf, context: context)
        MacCloudEditSync.shared.note(pf)
        reflectSplitToMemo(pf)
        flash("\(displayed) is \(canonical) now")
        if let slot, !pf.path.isEmpty, !pf.diarizationSegments.isEmpty {
            let audio = URL(fileURLWithPath: pf.path), segments = pf.diarizationSegments
            Task.detached(priority: .utility) {
                guard let vec = try? await DiarizationService.shared.embedSpeaker(audioURL: audio, segments: segments, slot: slot),
                      !vec.isEmpty else { return }
                NamesStore.shared.addVoiceEmbedding(
                    canonical: canonical,
                    embedding: VoiceEmbedding(vector: vec.map(Double.init), condition: "conversation",
                                              addedAt: ISO8601.now()))
            }
        }
    }

    /// "Move just this line to another speaker" — only the tapped turn changes hands.
    func moveLine(_ pf: PipelineFile, turnIndex: Int, to other: String, context: ModelContext) {
        guard SplitSpeakers.moveLine(pf, turnIndex: turnIndex, to: other,
                                     people: NamesStore.shared.livePeople()) else { return }
        resanitiseForNames(pf, context: context)
        MacCloudEditSync.shared.note(pf)
        reflectSplitToMemo(pf)
    }

    /// The diarization slot behind a displayed speaker: "Speaker N" is slot N-1 (the label
    /// BatchRunner writes); nil for a voice the Mac already matched (nothing new to learn).
    private static func diarizationSlot(of displayed: String) -> Int? {
        guard SpeakerTranscript.isUnnamed(displayed),
              let n = Int(displayed.dropFirst("Speaker ".count)), n >= 1 else { return nil }
        return n - 1
    }

    // ── Export to the Obsidian vault (markdown + audio + images) ──
    /// Q56/R90: `VaultExporter.export` does synchronous file copies + compile + vault
    /// write — the same class of work `IngestService` already runs off-main via
    /// `Task.detached`. This is `async` so a multi-select export loop (SidebarView)
    /// awaits each file in turn without blocking the main thread on any one of them;
    /// the `-runfile … -export` headless harness (`RunFile.swift`) awaits it directly.
    func export(_ pf: PipelineFile, context: ModelContext) async {
        let settings = SettingsStore.shared.load()
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try VaultExporter.export(pf, settings: settings)
            }.value
            // The engine tells the truth per outcome; the WORDS are shared with the phone
            // (`ExportOutcomeCopy`) so one verb can't mean two things on two devices.
            if result.outcome.isWrittenOrCurrent {
                pf.exported = result.markdownURL.path
                pf.exportStatus = .done
                pf.lastActivityAt = Date()
                try? context.save()
            }
            let msg = ExportOutcomeCopy.message(for: result.outcome, assetCount: result.imageCount)
            // A REFUSAL means the export did not happen, so it must not fade on its own —
            // three seconds for a permanent blocker is how "filed out of your Skrift folder"
            // went unnoticed until Tuur hit it head-on (2026-08-28).
            if msg.isRefusal { lastError = msg.text } else { flash(msg.text) }
        } catch {
            lastError = "Export failed: \(error.localizedDescription)"
            flash((error as? LocalizedError)?.errorDescription ?? "Export failed")
        }
    }

    /// Show a transient banner for ~3.5s (latest call wins).
    func flash(_ message: String) {
        toast = message
        toastToken += 1
        let t = toastToken
        Task { try? await Task.sleep(for: .seconds(3.5)); if toastToken == t { toast = nil } }
    }

    // (Review-time name decisions live in the body popover — chunk 4. No batch step here.)

    // ── ⋯ overflow actions: re-transcribe + per-step redo ──
    enum RedoStep { case title, copyEdit, summary }

    /// Re-run the whole pipeline on one file (re-transcribe → re-enhance). Clears
    /// every derivative of the OLD transcript first — word timings, diarization
    /// segments (+ the `diar_<id>.json` sidecar), sanitised body, ambiguous names,
    /// copy-edit/summary/suggested-title, compiled draft — so a re-run can't mix
    /// stale state with the fresh transcript. (Stale diarization segments fed wrong
    /// voice-enrollment slices; a stale sanitised body kept showing the OLD text
    /// when a fresh run failed midway.)
    func retranscribe(_ pf: PipelineFile, context: ModelContext) async {
        guard !isRunning else { lastError = Self.busyMessage; return }
        // Missing audio file is an ERROR on the row, not a silent clear (C51/R9) — checked
        // before touching anything, so a re-transcribe over a deleted file leaves the note
        // (transcript + every derivative) exactly as it was.
        guard !pf.path.isEmpty, FileManager.default.fileExists(atPath: pf.path) else {
            pf.error = "Re-transcribe failed: audio file not found."
            pf.transcribeStatus = .error
            try? context.save()
            lastError = pf.error
            return
        }
        // Nothing is cleared here. `BatchRunner.run(retranscribe: true)` only drops the OLD
        // transcript's derivatives (word timings, diarization, sanitised body, copy-edit,
        // summary, suggested title, compiled draft) once the fresh ASR pass actually
        // succeeds — a run that fails partway must leave the note untouched (C51/R9).
        // Just re-open the gates so `needsProcessing` picks this note back up.
        pf.sanitiseStatus = .pending
        pf.enhanceStatus = .pending
        pf.error = nil
        try? context.save()
        await process(fileIDs: [pf.id], context: context, retranscribeIDs: [pf.id])
    }

    /// "Flatten to monologue": UNDO a wrong speaker split (Sortformer over-split a
    /// single-speaker note into `**Speaker 1/2:**`). Drops the turn headers → plain prose,
    /// clears the diarization, then RE-ENHANCES as a monologue (copy-edit + title + summary +
    /// ordinary name-link + recompile). The WORDS are fine, so transcribe is NOT re-run — no
    /// re-ASR. (Conversation mode is off by default now, so `process` won't re-diarize.)
    func flattenToMonologue(_ pf: PipelineFile, context: ModelContext) async {
        guard !isRunning else { lastError = Self.busyMessage; return }
        // The state change is `SplitSpeakers.flatten` (pure, unit-tested): words + fixes +
        // name choices stay, Names is never touched. What is left is re-enhancing as one voice.
        guard SplitSpeakers.flatten(pf) else { return }
        try? context.save()
        reflectSplitToMemo(pf)
        await process(fileIDs: [pf.id], context: context)   // re-enhance the flat prose as a monologue
    }

    /// Re-run a single LLM step on the RAW transcript and recompile (the ⋯ menu's
    /// "Redo title / copy-edit / summary"). Loads the enhancement model first.
    func redo(_ step: RedoStep, for pf: PipelineFile, context: ModelContext) async {
        guard turn.acquire() else { lastError = Self.busyMessage; return }
        await runRedo(step, for: pf, context: context)
        // Anything that was asked for during the Redo (a recording-stop transcribe, an import's
        // auto-transcribe) waits in the queue: run it now (Q208).
        await drainWaiting(context: context)
    }

    private func runRedo(_ step: RedoStep, for pf: PipelineFile, context: ModelContext) async {
        let transcript = pf.transcript ?? ""
        guard !transcript.isEmpty else { lastError = "Nothing to redo — transcribe first."; return }

        beginRun(total: 1, currentTitle: pf.queueTitle)
        defer { endRun(sweepContext: context) }

        let settings = SettingsStore.shared.load()
        let repo = settings.enhancementModelRepo
        let showLoad = !modelsLoaded
        if showLoad { runState?.loadingLabel = "enhancement model" }
        do {
            try await EnhancementService.shared.ensureLoaded(modelRepo: repo) { f in
                Task { @MainActor in if showLoad { self.runState?.loadingFraction = f } }
            }
        } catch {
            lastError = "Model load failed: \(error.localizedDescription)"; return
        }
        if showLoad { runState?.loadingLabel = nil; runState?.loadingFraction = nil }
        modelsLoaded = true

        do {
            switch step {
            case .title:
                let t = try await enhancer.title(transcript, prompts: settings.prompts, modelRepo: repo)
                pf.titleSuggested = t
                pf.enhancedTitle = t   // redo title → adopt the fresh one
            case .copyEdit:
                // A speaker-attributed (conversation) transcript SKIPS copy-edit — the
                // LLM strips its `**Name:**` turn prefixes (same guard as BatchRunner).
                // Only an AUDIO memo can be a conversation (a note with bold headings is not).
                let isConversation = pf.sourceType == .audio && SpeakerTranscript.isAttributed(transcript)
                let c = isConversation
                    ? transcript
                    : try await enhancer.copyEdit(transcript, prompts: settings.prompts, modelRepo: repo)
                pf.enhancedCopyedit = c
                // re-link names on the fresh copy-edit so the body stays consistent
                // (honoring the note's persisted "unlink all mentions" choices)
                let working = c.isEmpty ? transcript : c
                let people = NamesStore.shared.livePeople()
                let san = isConversation
                    ? Sanitiser.processConversation(text: working, people: people, neverLink: Set(pf.unlinkedNames), namePicks: pf.namePicks)
                    : Sanitiser.process(text: working, people: people, neverLink: Set(pf.unlinkedNames), namePicks: pf.namePicks)
                pf.sanitised = san.sanitised
                pf.ambiguousNames = san.ambiguous.isEmpty ? nil : san.ambiguous
            case .summary:
                pf.enhancedSummary = try await enhancer.summary(transcript, prompts: settings.prompts, modelRepo: repo)
            }
            pf.compiledText = Compiler.compile(file: pf, author: settings.authorName, knownPeople: NamesStore.shared.livePeople())
            pf.lastActivityAt = Date()
            try? context.save()
            writeBackEnhancement(pf)   // re-sync the edited title/copy-edit/summary to the phone (8c)
        } catch {
            lastError = "Redo failed: \(error.localizedDescription)"
        }
    }

    // MARK: Opt-out naming — re-link the open note

    /// Re-run the deterministic OPT-OUT name-link + recompile on the PRISTINE working text
    /// (copy-edit → transcript) with the note's current `unlinkedNames` — no LLM. Used to
    /// re-scan the OPEN note after a names edit (so a newly-added person auto-links) and after
    /// a review name decision. Conversations take the turn-aware linker (matched speakers
    /// auto-link). (Chunk 4 threads the note's `namePicks` through here.)
    func resanitiseForNames(_ pf: PipelineFile, context: ModelContext? = nil) {
        let working = pf.enhancedCopyedit ?? pf.transcript ?? ""
        guard !working.isEmpty else { return }
        let people = NamesStore.shared.livePeople()
        let isConversation = pf.sourceType == .audio && SpeakerTranscript.isAttributed(working)
        let san = isConversation
            ? Sanitiser.processConversation(text: working, people: people, neverLink: Set(pf.unlinkedNames), namePicks: pf.namePicks)
            : Sanitiser.process(text: working, people: people, neverLink: Set(pf.unlinkedNames), namePicks: pf.namePicks)
        pf.sanitised = san.sanitised
        pf.ambiguousNames = san.ambiguous.isEmpty ? nil : san.ambiguous
        pf.compiledText = Compiler.compile(file: pf, author: SettingsStore.shared.load().authorName, knownPeople: people)
        if let context { pf.lastActivityAt = Date(); try? context.save() }
    }

    /// Roster-collision re-scan (NAMING_MODEL.md build-guard): after a names change, if a name
    /// went from one owner to a same-name collision, re-derive every already-processed memo that
    /// auto-linked it — its now-ambiguous `[[link]]` falls back to a dotted suggestion to re-pick
    /// — and flag the count so the silent mis-resolution can't slip by. `previousPeople` is the
    /// live roster snapshot taken BEFORE the change.
    func rescanRoster(previousPeople old: [Person], context: ModelContext) {
        let new = NamesStore.shared.livePeople()
        let collided = RosterAudit.newlyAmbiguous(old: old, new: new)
        guard !collided.isEmpty else { return }
        let all = (try? context.fetch(FetchDescriptor<PipelineFile>())) ?? []
        let affected = RosterAudit.affectedFiles(all, newlyAmbiguous: collided, people: new)
        guard !affected.isEmpty else { return }
        for f in affected { resanitiseForNames(f) }
        try? context.save()
        flash("\(affected.count) note\(affected.count == 1 ? "" : "s") now share a name — re-check the dotted names")
    }
}

/// Cross-thread "the user pressed Cancel" for one split run (`BatchRunner` reads it off the main actor).
final class SplitCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
