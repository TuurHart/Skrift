#if DEBUG
import Foundation

extension RunFile {
    /// `-recordcopyeditv2 <corpusRoot> -isolatedRun` (Q424, C7/C286/C166): copy-edit v2 over the
    /// corpus on a scratch in-memory store. A model call already recorded replays; only
    /// a MISS runs the live model and is recorded into `goldens/model/` (v2 reads the same prompts;
    /// its title and summary read prose without picture markers or links, C29/C178, so those
    /// calls are new). Each note's v2 title / summary / body goes to `goldens/v2-copyedit/`.
    ///
    /// The corpus path is this flag's value, NOT `-corpus`: `-corpus` also seeds the app's own
    /// store at launch, and that launch sweep holds the same memo ids in the process-wide
    /// `MemoCloudReconciler.ingestInFlight`, so the scratch sweep skipped every rated note.
    /// Refuses without `-isolatedRun` (never the live Dev store). Run the RAW binary from the
    /// build's derived data, never `open -a`. v1's `-recordcopyedit` went with v1 (Q427); its
    /// goldens (`goldens/v1-copyedit/`) stay as the reference v2 is classed against (C5).
    nonisolated static func runRecordCopyEditV2IfRequested() {
        guard let path = Harness.value("-recordcopyeditv2") else { return }
        Harness.main {
            let log = Harness.log
            guard LaunchArgs.isolatedRun else { log(">>> -recordcopyeditv2 needs -isolatedRun"); exit(2) }
            guard !LaunchArgs.has("-corpus") else { log(">>> -recordcopyeditv2 takes the corpus path itself; drop -corpus"); exit(2) }
            let corpus = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            let root = corpus.appendingPathComponent("goldens", isDirectory: true)
            let cache = ModelOutputCache(directory: root.appendingPathComponent("model", isDirectory: true))
            let records = root.appendingPathComponent("v2-copyedit", isDirectory: true)
            try FileManager.default.createDirectory(at: records, withIntermediateDirectories: true)
            let settings = AppSettings()
            try await EnhancementService.shared.ensureLoaded(modelRepo: settings.enhancementModelRepo)
            let live = cache.recording(EnhancementService.shared.generator)
            func recorded() -> Int { (try? FileManager.default.contentsOfDirectory(atPath: cache.directory.path).count) ?? 0 }
            let before = recorded()
            let generate: ModelGenerate = { prompt, text, cap in
                if let hit = cache.lookup(prompt: prompt, input: text) { return hit }
                return try await live(prompt, text, cap)
            }
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("q424-record-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let results = try await CopyEditCorpusRun.run(corpus: corpus, enhancer: GenerateEnhancer(generate: generate),
                                                          scratch: scratch,
                                                          step: CopyEditV2Mac.corpusStep(generate: generate)) { slug in
                log("  \(slug)")
            }
            for r in results {
                try Data(r.record.utf8).write(to: records.appendingPathComponent("\(r.slug).txt"))
            }
            log(">>> v2 recorded \(results.count) notes, \(recorded() - before) new model outputs, errors: \(results.filter { $0.error != nil }.map(\.slug))")
        }
    }
}
#endif
