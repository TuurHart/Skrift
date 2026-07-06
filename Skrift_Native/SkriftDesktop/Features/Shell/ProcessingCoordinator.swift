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

    /// A file still needs the auto-run until it reaches Ready (enhance done).
    /// A soft-deleted (Recently Deleted) file is never processed.
    func needsProcessing(_ pf: PipelineFile) -> Bool { pf.deletedAt == nil && pf.enhanceStatus != .done }

    /// On launch, recover notes stranded mid-run by a crash/quit (a `.processing`
    /// step with no run actually active) so the queue can pick them up again. A
    /// pilot found such notes stuck showing "Enhancing" forever.
    func reconcileInterruptedRuns(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<PipelineFile>())) ?? []
        if RunReconciler.resetInterrupted(all) { try? context.save() }
    }

    // ── Process (transcribe → enhance → tag → name-link → compile) ──
    func process(fileIDs: [String], context: ModelContext) async {
        guard !isRunning else { lastError = "A run is already going — wait for it to finish."; return }

        let all = (try? context.fetch(FetchDescriptor<PipelineFile>())) ?? []
        let targets = all
            .filter { fileIDs.contains($0.id) && needsProcessing($0) }
            .sorted { $0.uploadedAt < $1.uploadedAt }   // oldest first, like the backend
        guard !targets.isEmpty else { return }

        isRunning = true
        idleUnloadTask?.cancel(); idleUnloadTask = nil   // don't unload mid-run
        runState = RunState(total: targets.count, done: 0, currentTitle: nil)
        defer { isRunning = false; runState = nil; scheduleIdleUnload() }

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
                                     imageManifest: hasAudio ? Self.imageManifest(for: pf.path) : [])
                if pf.sanitised != nil { pf.sanitiseStatus = .done }
                pf.error = nil
                pf.lastActivityAt = Date()
            } catch {
                pf.error = String(describing: error)
                if (pf.transcript ?? "").isEmpty { pf.transcribeStatus = .error }
                else { pf.enhanceStatus = .error }
                lastError = "Processing failed: \(error.localizedDescription)"
            }
            try? context.save()
            writeBackEnhancement(pf)
            runState?.done += 1
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
            try MacCloudWriteBack.upsert(for: pf, into: container.mainContext, deviceID: DeviceID.current())
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
            pf.exported = result.markdownURL.path
            pf.exportStatus = .done
            pf.lastActivityAt = Date()
            try? context.save()
            let imgs = result.imageCount > 0 ? " · \(result.imageCount) image\(result.imageCount == 1 ? "" : "s")" : ""
            flash("Exported “\(result.markdownURL.deletingPathExtension().lastPathComponent)” to your vault\(imgs)")
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
        pf.transcript = nil
        pf.wordTimings = []
        pf.diarizationSegments = []
        if !pf.path.isEmpty {
            DiarizationSidecar().delete(in: DiarizationSidecar.workingFolder(for: pf), id: pf.id)
        }
        pf.sanitised = nil
        pf.ambiguousNames = nil
        pf.enhancedCopyedit = nil
        pf.enhancedSummary = nil
        pf.titleSuggested = nil
        pf.compiledText = nil
        pf.transcribeStatus = .pending
        pf.sanitiseStatus = .pending
        pf.enhanceStatus = .pending
        pf.error = nil
        try? context.save()
        await process(fileIDs: [pf.id], context: context)
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
        defer { isRunning = false; runState = nil; scheduleIdleUnload() }

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
