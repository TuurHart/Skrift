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
    private(set) var isRunning = false
    var lastError: String?
    /// Transient confirmation banner (auto-clears) — shown by RootView so an action
    /// like Export gives visible feedback (N5).
    var toast: String?
    private var toastToken = 0
    /// True while the ASR/LLM weights are resident in memory — drives the sidebar
    /// engine dots (green = loaded, dim = idle/unloaded) so they reflect reality.
    private(set) var modelsLoaded = false

    // Engine seam — the real FluidAudio/MLX services by default; swapped for canned
    // stubs when launched with `-stubEnhancement` (UI piloting / XCUITest), so
    // Process→Ready runs instantly without the 9 GB model.
    private let transcriber: Transcribing
    private let enhancer: Enhancing
    private let diarizer: Diarizing?
    private let stubbedEngines: Bool

    /// Frees the ~9 GB of model weights after the queue goes idle (the Python app
    /// did this). Cancelled when a run starts, rescheduled when it ends.
    private var idleUnloadTask: Task<Void, Never>?
    private static let idleUnloadDelay: Duration = .seconds(60)

    init() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-stubEnhancement") {
            let seed: String
            if let i = args.firstIndex(of: "-seedTranscript"), i + 1 < args.count {
                seed = args[i + 1]
            } else {
                seed = "This is a stubbed transcript for UI piloting. We talked through the desktop rewrite and what to test next week."
            }
            transcriber = StubTranscriber(text: seed)
            enhancer = StubEnhancer()
            diarizer = nil
            stubbedEngines = true
            return
        }
        #endif
        transcriber = TranscriptionService.shared
        enhancer = EnhancementService.shared
        diarizer = DiarizationService.shared
        stubbedEngines = false
    }

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
        guard !isRunning else { lastError = "A run is already going — wait for it to finish."; return }

        let all = (try? context.fetch(FetchDescriptor<PipelineFile>())) ?? []
        let targets = all
            .filter { fileIDs.contains($0.id) && needsProcessing($0) }
            .sorted { $0.uploadedAt < $1.uploadedAt }   // oldest first, like the backend
        guard !targets.isEmpty else { return }

        isRunning = true
        idleUnloadTask?.cancel(); idleUnloadTask = nil   // don't unload mid-run
        runState = RunState(total: targets.count, done: 0, currentTitle: nil)
        // The ANE/GPU belong to the pipeline while a run is live — the shared
        // embedder yields its cold load (the phone's 2026-07-15 starvation lesson).
        TranscriptionActivity.begin()
        defer {
            isRunning = false; runState = nil; scheduleIdleUnload()
            TranscriptionActivity.end()
            // Fresh transcripts/polish just landed — index them.
            ConnectionsIndexService.shared.sweepSoon(context)
        }

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
        // Skipped for stubbed engines (UI piloting) — nothing to load.
        if !stubbedEngines {
            let needsAudio = targets.contains {
                $0.sourceType == .audio && !$0.path.isEmpty && FileManager.default.fileExists(atPath: $0.path)
            }
            // Show the load banner only when the models aren't already resident —
            // ensureLoaded is a no-op when cached, so a "Loading…" flash on every run
            // was misleading (#31).
            let showLoad = !modelsLoaded
            do {
                if needsAudio {
                    if showLoad { runState?.loadingLabel = "transcription model" }
                    try await TranscriptionService.shared.ensureLoaded { f in
                        Task { @MainActor in if showLoad { self.runState?.loadingFraction = f } }
                    }
                }
                if showLoad { runState?.loadingLabel = "enhancement model"; runState?.loadingFraction = nil }
                try await EnhancementService.shared.ensureLoaded(modelRepo: settings.enhancementModelRepo) { f in
                    Task { @MainActor in if showLoad { self.runState?.loadingFraction = f } }
                }
            } catch {
                lastError = "Model load failed: \(error.localizedDescription)"
                return   // defer resets isRunning + runState
            }
            if showLoad { runState?.loadingLabel = nil; runState?.loadingFraction = nil }
        }
        modelsLoaded = true

        for pf in targets {
            runState?.currentTitle = pf.queueTitle
            // Captures: pf.path is the working folder, not an audio file — don't
            // pass it as an audioURL (BatchRunner ignores it, but nil is cleaner).
            let hasAudio = pf.sourceType == .audio && !pf.path.isEmpty
                && FileManager.default.fileExists(atPath: pf.path)
            let audioURL = hasAudio ? URL(fileURLWithPath: pf.path) : nil
            do {
                try await runner.run(pf, audioURL: audioURL,
                                     imageManifest: hasAudio ? Self.imageManifest(for: pf.path) : [],
                                     retranscribe: retranscribeIDs.contains(pf.id))
                if pf.sanitised != nil { pf.sanitiseStatus = .done }
                pf.error = nil
                pf.lastActivityAt = Date()
            } catch {
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
        guard !isRunning else { return }   // silent: this is automatic, not a button press
        let all = (try? context.fetch(FetchDescriptor<PipelineFile>())) ?? []
        let targets = all.filter { fileIDs.contains($0.id) && $0.transcribeStatus != .done }
        guard !targets.isEmpty else { return }

        isRunning = true
        idleUnloadTask?.cancel(); idleUnloadTask = nil
        runState = RunState(total: targets.count, done: 0, currentTitle: nil)
        TranscriptionActivity.begin()
        defer {
            isRunning = false; runState = nil; scheduleIdleUnload()
            TranscriptionActivity.end()
        }

        if !stubbedEngines {
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
        }

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
    /// the next run. No-op when engines are stubbed (nothing loaded).
    private func scheduleIdleUnload() {
        guard !stubbedEngines else { return }
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

    // ── Export to the Obsidian vault (markdown + audio + images) ──
    func export(_ pf: PipelineFile, context: ModelContext) {
        let settings = SettingsStore.shared.load()
        do {
            let result = try VaultExporter.export(pf, settings: settings)
            let name = result.markdownURL.deletingPathExtension().lastPathComponent
            // The engine tells the truth per outcome; the WORDS are shared with the phone
            // (`ExportOutcomeCopy`) so one verb can't mean two things on two devices.
            if result.outcome.isWrittenOrCurrent {
                pf.exported = result.markdownURL.path
                pf.exportStatus = .done
                pf.lastActivityAt = Date()
                try? context.save()
            }
            let msg = ExportOutcomeCopy.message(for: result.outcome, noteName: name,
                                                assetCount: result.imageCount)
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
        guard !isRunning else { lastError = "A run is already going — wait for it to finish."; return }
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
        guard !isRunning else { lastError = "A run is already going — wait for it to finish."; return }
        guard SpeakerTranscript.isAttributed(pf.transcript),
              let flat = SpeakerTranscript.flattened(pf.transcript) else { return }
        pf.transcript = flat
        pf.diarizationSegments = []
        if !pf.path.isEmpty {
            DiarizationSidecar().delete(in: DiarizationSidecar.workingFolder(for: pf), id: pf.id)
        }
        pf.sanitised = nil
        pf.ambiguousNames = nil
        pf.enhancedCopyedit = nil
        pf.enhancedSummary = nil
        pf.compiledText = nil
        pf.sanitiseStatus = .pending
        pf.enhanceStatus = .pending
        try? context.save()
        await process(fileIDs: [pf.id], context: context)   // re-enhance the flat prose as a monologue
    }

    /// Re-run a single LLM step on the RAW transcript and recompile (the ⋯ menu's
    /// "Redo title / copy-edit / summary"). Loads the enhancement model first.
    func redo(_ step: RedoStep, for pf: PipelineFile, context: ModelContext) async {
        guard !isRunning else { lastError = "A run is already going — wait for it to finish."; return }
        let transcript = pf.transcript ?? ""
        guard !transcript.isEmpty else { lastError = "Nothing to redo — transcribe first."; return }

        isRunning = true
        idleUnloadTask?.cancel(); idleUnloadTask = nil
        runState = RunState(total: 1, done: 0, currentTitle: pf.queueTitle)
        TranscriptionActivity.begin()
        defer {
            isRunning = false; runState = nil; scheduleIdleUnload()
            TranscriptionActivity.end()
            ConnectionsIndexService.shared.sweepSoon(context)
        }

        let settings = SettingsStore.shared.load()
        let repo = settings.enhancementModelRepo
        if !stubbedEngines {
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
        }
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
