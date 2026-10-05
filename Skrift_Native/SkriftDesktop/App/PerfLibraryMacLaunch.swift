#if DEBUG
import Foundation
import SwiftData

/// Q313 Mac glue for `-perfLibrary` on Skrift Dev. The generator is the shared `PerfLibrarySeeder`;
/// it writes `Memo` / `MemoAsset` rows into the Mac's CloudKit-off perf store
/// (`MemoCloudStore.container` under the flag), then the ordinary `MemoCloudReconciler` sweep
/// ingests the rated ones into `PipelineFile` rows exactly as it does for a synced memo. Every
/// recording-shaped memo carries a tiny real audio asset (`tinyAudioForEveryRecording`) because the
/// ingest builds no row for a voice memo whose audio blob is missing.
///
/// First launch only: the seeded marker (`perf.store.seeded`) makes later launches open the store
/// as it is. Progress goes to stdout and `perf-progress.txt` beside the store (Skrift Dev's
/// Application Support folder).
enum PerfLibraryMacLaunch {
    @MainActor
    static func seedThenStartReconciler() {
        guard let cloud = MemoCloudStore.container else {
            PerfLibrary.logProgress("perf library: no perf container, nothing seeded")
            return
        }
        guard !PerfLibrary.isSeeded else {
            PerfLibrary.logProgress(PerfLibrary.alreadySeededLine)
            MemoCloudReconciler.start()
            return
        }
        PerfLibrary.logProgress("seeding start")
        let began = Date()
        Task.detached(priority: .userInitiated) {
            let context = ModelContext(cloud)
            context.autosaveEnabled = false
            var plan = PerfLibrarySeeder.Plan()
            plan.tinyAudioForEveryRecording = true
            do {
                let summary = try PerfLibrarySeeder.seed(into: context, recordingsDirectory: nil, plan: plan) { phase, done, total in
                    PerfLibrary.logProgress("perf library: \(phase) \(done)/\(total)")
                }
                PerfLibrary.writeNames(PerfLibrarySeeder.makePeople(count: plan.people, now: Date()))
                PerfLibrary.markSeeded()
                PerfLibrary.logProgress("perf library seeded: \(summary.memos) notes, \(summary.assets) assets, \(summary.people) people in \(Int(Date().timeIntervalSince(began)))s")
            } catch {
                PerfLibrary.logProgress("perf library seed FAILED: \(error)")
            }
            await MainActor.run { MemoCloudReconciler.start() }
        }
    }
}
#endif
