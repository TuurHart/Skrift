#if DEBUG
import Foundation
import SwiftData
import ZIPFoundation

extension RunFile {
    /// `-exportall <corpusRoot> -isolatedRun` (Q516): "Export all notes…" headless over the
    /// synthetic corpus, through the Settings row's own gather (`ExportAllRow.items`) and the
    /// shared run (`ExportAllRun`), then reads the zip back and exits. Scratch in-memory stores
    /// and a temp folder: never the live Dev store, the vault or a save panel. Run the RAW binary
    /// from the build's derived data, never `open -a`. `-keepzip <path>` copies the zip out.
    nonisolated static func runExportAllIfRequested() {
        guard let path = Harness.value("-exportall") else { return }
        Harness.main {
            let log = Harness.log
            guard LaunchArgs.isolatedRun else { log(">>> -exportall needs -isolatedRun"); exit(2) }
            let corpus = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("q516-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let people = try JSONDecoder().decode([Person].self, from: Data(contentsOf: corpus.appendingPathComponent("names.json")))
            let cloud = ModelContext(try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
            let local = ModelContext(try ModelContainer(for: PipelineFile.self,
                                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
            try CorpusSeed.seed(from: corpus, into: cloud, recordingsDirectory: scratch.appendingPathComponent("rec"))
            _ = MemoCloudReconciler.v2Pass(cloud: cloud, local: local, people: people, author: "Corpus Author",
                                           thisDevice: "corpus-mac", outputDir: scratch.appendingPathComponent("work"),
                                           firstImportDone: true, deferIngest: false)
            let live = try cloud.fetch(FetchDescriptor<Memo>()).filter { $0.deletedAt == nil }.count

            let run = ExportAllRun()
            var states: [String] = []
            let finished: URL = await withCheckedContinuation { done in
                run.start(gather: { ExportAllRow.items(local: local, cloud: cloud, people: people, author: "Corpus Author") },
                          onFinished: { done.resume(returning: $0) })
                Task { @MainActor in
                    while run.isBuilding { states.append("\(run.state)"); try? await Task.sleep(nanoseconds: 20_000_000) }
                }
            }
            let archive = try Archive(url: finished, accessMode: .read)
            let notes = archive.filter { $0.path.hasSuffix(".md") }.count
            let files = archive.reduce(0) { n, _ in n + 1 }
            let bytes = (try? FileManager.default.attributesOfItem(atPath: finished.path)[.size] as? Int) ?? 0
            log("== zip \(finished.lastPathComponent): \(notes) notes / \(live) live memos, \(files) entries, \(bytes / 1024) KB")
            log("== progress seen: \(states.count) samples, last \(states.last ?? "none")")
            if let keep = Harness.value("-keepzip") {
                try? FileManager.default.removeItem(atPath: keep)
                try FileManager.default.copyItem(at: finished, to: URL(fileURLWithPath: keep))
            }
            run.finish()
            let cleaned = !FileManager.default.fileExists(atPath: ExportAllRun.tempFolder.path)
            log("== after finish: temp folder removed \(cleaned), state \(run.state)")
            let ok = notes == live && cleaned && run.state == .ready
            log(ok ? ">>> PASS" : ">>> FAIL")
            exit(ok ? 0 : 1)
        }
    }
}
#endif
