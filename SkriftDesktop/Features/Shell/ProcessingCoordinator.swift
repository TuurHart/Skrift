import SwiftUI
import SwiftData

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

    // Engine seam — the real FluidAudio/MLX services by default; swapped for canned
    // stubs when launched with `-stubEnhancement` (UI piloting / XCUITest), so
    // Process→Ready runs instantly without the 9 GB model.
    private let transcriber: Transcribing
    private let enhancer: Enhancing
    private let stubbedEngines: Bool

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
            stubbedEngines = true
            return
        }
        #endif
        transcriber = TranscriptionService.shared
        enhancer = EnhancementService.shared
        stubbedEngines = false
    }

    #if DEBUG
    /// Snapshot helper — a coordinator with a preset run state for verification.
    static func preview(_ rs: RunState) -> ProcessingCoordinator {
        let c = ProcessingCoordinator(); c.runState = rs; return c
    }
    #endif

    /// A file still needs the auto-run until it reaches Ready (enhance done).
    func needsProcessing(_ pf: PipelineFile) -> Bool { pf.enhanceStatus != .done }

    // ── Process (transcribe → enhance → tag → name-link → compile) ──
    func process(fileIDs: [String], context: ModelContext) async {
        guard !isRunning else { lastError = "A run is already going — wait for it to finish."; return }

        let all = (try? context.fetch(FetchDescriptor<PipelineFile>())) ?? []
        let targets = all
            .filter { fileIDs.contains($0.id) && needsProcessing($0) }
            .sorted { $0.uploadedAt < $1.uploadedAt }   // oldest first, like the backend
        guard !targets.isEmpty else { return }

        isRunning = true
        runState = RunState(total: targets.count, done: 0, currentTitle: nil)
        defer { isRunning = false; runState = nil }

        let settings = SettingsStore.shared.load()
        let runner = BatchRunner(
            transcriber: transcriber,
            enhancer: enhancer,
            settings: settings,
            people: NamesStore.shared.livePeople(),
            tagWhitelist: []   // vault tag-whitelist scan is a follow-up
        )

        // Pre-load the engines up front so the first run shows download/load
        // progress in the run bar (instant when the models are already cached).
        // Skipped for stubbed engines (UI piloting) — nothing to load.
        if !stubbedEngines {
            let needsAudio = targets.contains {
                $0.sourceType != .note && !$0.path.isEmpty && FileManager.default.fileExists(atPath: $0.path)
            }
            do {
                if needsAudio {
                    runState?.loadingLabel = "transcription model"
                    try await TranscriptionService.shared.ensureLoaded { f in
                        Task { @MainActor in self.runState?.loadingFraction = f }
                    }
                }
                runState?.loadingLabel = "enhancement model"
                runState?.loadingFraction = nil
                try await EnhancementService.shared.ensureLoaded(modelRepo: settings.enhancementModelRepo) { f in
                    Task { @MainActor in self.runState?.loadingFraction = f }
                }
            } catch {
                lastError = "Model load failed: \(error.localizedDescription)"
                return   // defer resets isRunning + runState
            }
            runState?.loadingLabel = nil
            runState?.loadingFraction = nil
        }

        for pf in targets {
            runState?.currentTitle = pf.queueTitle
            let hasAudio = pf.sourceType != .note && !pf.path.isEmpty
                && FileManager.default.fileExists(atPath: pf.path)
            let audioURL = hasAudio ? URL(fileURLWithPath: pf.path) : nil
            do {
                try await runner.run(pf, audioURL: audioURL)
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
            runState?.done += 1
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
        } catch {
            lastError = "Export failed: \(error.localizedDescription)"
        }
    }

    // ── Apply review-time ambiguous-name choices ──
    func applyResolvedNames(_ pf: PipelineFile, decisions: [ResolverDecision], context: ModelContext) {
        var text = pf.bestBodyText

        // Collapsed (per-alias) choices — one person for every mention of the alias.
        let aliasDecisions = decisions
            .filter { $0.offset == nil && $0.canonical != nil }
            .map { (alias: $0.alias, canonical: $0.canonical!, short: $0.short) }
        if !aliasDecisions.isEmpty {
            text = Sanitiser.applyResolvedNames(text: text, decisions: aliasDecisions)
        }

        // Expanded (per-occurrence) choices — distinct people per mention (two Jacks).
        let expanded = decisions.filter { $0.offset != nil }
        if !expanded.isEmpty {
            var byAlias: [String: [(canonical: String?, short: String?)]] = [:]
            for (_, group) in Dictionary(grouping: expanded, by: { $0.alias.lowercased() }) {
                let ordered = group.sorted { ($0.offset ?? 0) < ($1.offset ?? 0) }
                let aliasName = ordered.first?.alias ?? ""
                byAlias[aliasName] = ordered.map { ($0.canonical, $0.short) }
            }
            text = Sanitiser.applyResolvedOccurrences(text: text, byAlias: byAlias)
        }

        pf.sanitised = text
        pf.ambiguousNames = nil
        pf.sanitiseStatus = .done
        let settings = SettingsStore.shared.load()
        pf.compiledText = Compiler.compile(file: pf, author: settings.authorName)
        try? context.save()
    }
}
