#if DEBUG
import Foundation

/// Headless end-to-end pipeline run. Launched with `-runfile <audioPath>`, builds
/// a transient PipelineFile, runs the real BatchRunner (FluidAudio + mlx-swift) on
/// it, prints the result to stderr, and exits. Validates the whole pipeline without
/// GUI automation or SwiftData. (DEBUG only; transient — writes nothing.)
///
/// IMPORTANT: do NOT block the main thread waiting for the run — FluidAudio's ASR
/// posts completion callbacks to main, so blocking main deadlocks at inference.
/// We schedule a detached Task, let `init` return so the run loop spins, and
/// `exit(0)` when finished.
enum RunFile {
    nonisolated static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-runfile"), i + 1 < args.count else { return }
        let path = args[i + 1]

        Task.detached(priority: .userInitiated) {
            func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

            log("== RUNFILE \(path) ==")
            guard FileManager.default.fileExists(atPath: path) else { log("audio not found"); exit(1) }

            let pf = PipelineFile(id: "runfile", filename: URL(fileURLWithPath: path).lastPathComponent,
                                  path: path, sourceType: .audio)
            let settings = SettingsStore.shared.load()
            let runner = BatchRunner(
                transcriber: TranscriptionService.shared,
                enhancer: EnhancementService.shared,
                settings: settings,
                people: NamesStore.shared.livePeople(),
                tagWhitelist: []
            )
            let t0 = Date()
            do {
                try await runner.run(pf, audioURL: URL(fileURLWithPath: path))
                log(String(format: ">>> elapsed: %.1fs", Date().timeIntervalSince(t0)))
                log(">>> steps: transcribe=\(pf.transcribeStatus.rawValue) enhance=\(pf.enhanceStatus.rawValue)")
                log(">>> TRANSCRIPT:\n\(pf.transcript ?? "(nil)")")
                log(">>> TITLE: \(pf.enhancedTitle ?? "(nil)")")
                log(">>> SUMMARY: \(pf.enhancedSummary ?? "(nil)")")
                log(">>> TAG SUGGESTIONS: \(pf.tagSuggestions ?? [])")
                log(">>> AMBIGUOUS NAMES: \((pf.ambiguousNames ?? []).map { $0.alias })")
                log(">>> SANITISED:\n\(pf.sanitised ?? "(nil)")")
                log(">>> COMPILED (\((pf.compiledText ?? "").count) chars):\n\(pf.compiledText ?? "(nil)")")

                // Optional: -vault <path> exports to a real (test) vault.
                if let vi = args.firstIndex(of: "-vault"), vi + 1 < args.count {
                    var s = settings
                    s.noteFolder = args[vi + 1]
                    if s.audioFolder.isEmpty { s.audioFolder = "Voice Memos" }
                    if s.attachmentsFolder.isEmpty { s.attachmentsFolder = "Attachments" }
                    let r = try VaultExporter.export(pf, settings: s)
                    log(">>> EXPORTED md: \(r.markdownURL.path)")
                    log(">>> EXPORTED audio: \(r.audioURL?.path ?? "(none)")  images: \(r.imageCount)")
                }
            } catch {
                log(">>> ERROR: \(error)")
            }
            exit(0)
        }
    }
}
#endif
