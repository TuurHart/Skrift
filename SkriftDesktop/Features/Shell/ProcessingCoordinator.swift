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
    }

    private(set) var runState: RunState?
    private(set) var isRunning = false
    var lastError: String?

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
            transcriber: TranscriptionService.shared,
            enhancer: EnhancementService.shared,
            settings: settings,
            people: NamesStore.shared.livePeople(),
            tagWhitelist: []   // vault tag-whitelist scan lands in Phase 8
        )

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

    // ── Export to the Obsidian vault ──
    func export(_ pf: PipelineFile, context: ModelContext) {
        let settings = SettingsStore.shared.load()
        let vault = settings.noteFolder.trimmingCharacters(in: .whitespaces)
        guard !vault.isEmpty else { lastError = "Set your Obsidian vault path in Settings first."; return }

        let markdown = Compiler.compile(file: pf, author: settings.authorName)
        let base = (pf.enhancedTitle?.isEmpty == false ? pf.enhancedTitle! : SkriftFormat.cleanFilename(pf.filename))
        let safe = base.replacingOccurrences(of: "/", with: "-")
        let url = URL(fileURLWithPath: vault).appendingPathComponent(safe + ".md")
        do {
            try Data(markdown.utf8).write(to: url)
            pf.exported = url.path
            pf.exportStatus = .done
            pf.lastActivityAt = Date()
            try? context.save()
        } catch {
            lastError = "Export failed: \(error.localizedDescription)"
        }
    }

    // ── Apply review-time ambiguous-name choices ──
    func applyResolvedNames(_ pf: PipelineFile, decisions: [ResolverDecision], context: ModelContext) {
        // Per-alias (collapsed) choices apply via the Sanitiser. Per-occurrence
        // choices (distinct people per mention — the two-Jacks case) need an
        // offset-aware Sanitiser apply; that's an owed follow-up.
        let aliasDecisions = decisions
            .filter { $0.offset == nil && $0.canonical != nil }
            .map { (alias: $0.alias, canonical: $0.canonical!, short: $0.short) }
        if !aliasDecisions.isEmpty {
            pf.sanitised = Sanitiser.applyResolvedNames(text: pf.bestBodyText, decisions: aliasDecisions)
        }
        pf.ambiguousNames = nil
        pf.sanitiseStatus = .done
        let settings = SettingsStore.shared.load()
        pf.compiledText = Compiler.compile(file: pf, author: settings.authorName)
        try? context.save()
    }
}
