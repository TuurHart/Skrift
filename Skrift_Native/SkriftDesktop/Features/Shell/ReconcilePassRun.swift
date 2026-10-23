#if DEBUG
import Foundation
import SwiftData

extension RunFile {
    /// `-reconcilepass <corpusRoot> -isolatedRun` (Q431): the Mac's reconcile pass — reconcile v2,
    /// built the way the app's wiring builds it (`MemoCloudReconciler.v2Pass`) — over the synthetic
    /// corpus, headless, then exit. Scratch in-memory stores and a temp output folder: never the
    /// live Dev store, the Dev names file, the vault or the connections index. Three checks:
    /// an inline pass makes every rated live note's row, a second pass changes nothing, and the
    /// background first-enable ingest (deferred pass + `ingestInBackground`) makes the same rows.
    /// Run the RAW binary from the build's derived data, never `open -a`.
    nonisolated static func runReconcilePassIfRequested() {
        guard let path = Harness.value("-reconcilepass") else { return }
        Harness.main {
            let log = Harness.log
            guard LaunchArgs.isolatedRun else { log(">>> -reconcilepass needs -isolatedRun"); exit(2) }
            guard !LaunchArgs.has("-corpus") else { log(">>> -reconcilepass takes the corpus path itself; drop -corpus"); exit(2) }
            let corpus = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("q431-pass-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let people = try JSONDecoder().decode([Person].self, from: Data(contentsOf: corpus.appendingPathComponent("names.json")))

            func stores() throws -> (ModelContainer, ModelContext, ModelContainer, ModelContext) {
                let cloud = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                               configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
                let local = try ModelContainer(for: PipelineFile.self,
                                               configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
                let ctx = ModelContext(cloud)
                try CorpusSeed.seed(from: corpus, into: ctx, recordingsDirectory: scratch.appendingPathComponent("rec"))
                return (cloud, ctx, local, ModelContext(local))
            }
            func expected(_ ctx: ModelContext) throws -> Int {
                try ctx.fetch(FetchDescriptor<Memo>()).filter { $0.deletedAt == nil && NoteConsent.isRated($0) }.count
            }

            // 1 + 2: inline pass, then a pass over the settled stores.
            let (cloudA, ctxA, localA, rowsA) = try stores()
            let want = try expected(ctxA)
            let start = Date()
            let (_, first) = MemoCloudReconciler.v2Pass(cloud: ctxA, local: rowsA, people: people, author: "Corpus Author",
                                                        thisDevice: "corpus-mac", outputDir: scratch.appendingPathComponent("outA"),
                                                        firstImportDone: true, deferIngest: false)
            let made = try rowsA.fetchCount(FetchDescriptor<PipelineFile>())
            log("== pass 1: created \(first.sweep.created), rows \(made) / \(want) rated live, failures \(first.sweep.ingestFailures), stranded \(first.sweep.stranded), orphans \(first.orphansTrashed), authored \(first.authored), \(Int(Date().timeIntervalSince(start) * 1000)) ms")
            let (_, second) = MemoCloudReconciler.v2Pass(cloud: ctxA, local: rowsA, people: people, author: "Corpus Author",
                                                         thisDevice: "corpus-mac", outputDir: scratch.appendingPathComponent("outA"),
                                                         firstImportDone: true, deferIngest: false)
            log("== pass 2: created \(second.sweep.created), updated \(second.sweep.updatedIDs.count), watermarked \(second.sweep.watermarked)")
            _ = (cloudA, localA)

            // 3: the deferred pass + the app's background ingest.
            let (cloudB, ctxB, localB, rowsB) = try stores()
            let (context, deferred) = MemoCloudReconciler.v2Pass(cloud: ctxB, local: rowsB, people: people, author: "Corpus Author",
                                                                 thisDevice: "corpus-mac", outputDir: scratch.appendingPathComponent("outB"),
                                                                 firstImportDone: true, deferIngest: true)
            let created = await MemoCloudReconciler.ingestInBackground(deferred.sweep.pendingNewIDs, container: cloudB,
                                                                        local: rowsB, context: context, indexAfter: false).value
            let rowsAfter = try rowsB.fetchCount(FetchDescriptor<PipelineFile>())
            log("== deferred: pending \(deferred.sweep.pendingNewIDs.count), background created \(created), rows \(rowsAfter)")
            _ = localB

            let ok = made == want && first.sweep.ingestFailures == 0 && first.sweep.stranded == 0
                && second.sweep.created == 0 && second.sweep.updatedIDs.isEmpty && rowsAfter == want
            log(ok ? ">>> PASS" : ">>> FAIL")
            exit(ok ? 0 : 1)
        }
    }
}
#endif
