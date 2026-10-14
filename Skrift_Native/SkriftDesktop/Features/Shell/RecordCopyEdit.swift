#if DEBUG
import Foundation

extension RunFile {
    /// `-recordcopyedit <corpusRoot> -isolatedRun` (Q423, C7/C286/C166): seed a scratch
    /// in-memory store from the synthetic corpus, run v1's Process over every note with the LIVE
    /// MLX model, record each model call's raw output as
    /// `<corpusRoot>/goldens/model/<sha256(prompt+input)>.txt` and each note's shipped title /
    /// summary / body as `<corpusRoot>/goldens/v1-copyedit/<slug>.txt`.
    ///
    /// The corpus path is this flag's value, NOT `-corpus`: `-corpus` also seeds the app's own
    /// store at launch, and that launch sweep holds the same memo ids in the process-wide
    /// `MemoCloudReconciler.ingestInFlight`, so the scratch sweep skipped every rated note.
    /// Refuses without `-isolatedRun` (never the live Dev store). Run the RAW binary from the
    /// build's derived data, never `open -a`.
    nonisolated static func runRecordCopyEditIfRequested() {
        guard let path = Harness.value("-recordcopyedit") else { return }
        Harness.main {
            let log = Harness.log
            guard LaunchArgs.isolatedRun else { log(">>> -recordcopyedit needs -isolatedRun"); exit(2) }
            guard !LaunchArgs.has("-corpus") else { log(">>> -recordcopyedit takes the corpus path itself; drop -corpus"); exit(2) }
            let corpus = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            let root = corpus.appendingPathComponent("goldens", isDirectory: true)
            let cache = ModelOutputCache(directory: root.appendingPathComponent("model", isDirectory: true))
            let goldens = root.appendingPathComponent("v1-copyedit", isDirectory: true)
            try FileManager.default.createDirectory(at: goldens, withIntermediateDirectories: true)
            let settings = AppSettings()
            log("== RECORDCOPYEDIT model \(settings.enhancementModelRepo) → \(root.path)")
            try await EnhancementService.shared.ensureLoaded(modelRepo: settings.enhancementModelRepo)
            let enhancer = GenerateEnhancer(generate: cache.recording(EnhancementService.shared.generator))
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("q423-record-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let start = Date()
            let results = try await CopyEditCorpusRun.run(corpus: corpus, enhancer: enhancer, scratch: scratch) { slug in
                log("  \(slug)  (+\(Int(Date().timeIntervalSince(start)))s)")
            }
            for r in results {
                try Data(r.record.utf8).write(to: goldens.appendingPathComponent("\(r.slug).txt"))
            }
            let errors = results.filter { $0.error != nil }.map(\.slug)
            log(">>> recorded \(results.count) notes (\(results.filter(\.hasRow).count) with a row), errors: \(errors)")
        }
    }
}
#endif
