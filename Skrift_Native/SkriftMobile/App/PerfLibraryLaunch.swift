#if DEBUG
import SwiftUI
import SwiftData

/// Q313 phone glue for `-perfLibrary`: seeds the perf store once (off the main thread, with a
/// progress line) and holds the app root back until it is done. The generator itself is
/// `PerfLibrarySeeder` (Shared/Corpus); the store/paths/gates are `PerfLibrary` (Shared/Model).
@MainActor
final class PerfLibraryLaunch: ObservableObject {
    static let shared = PerfLibraryLaunch()

    /// True from launch until the seed has finished (always false when there is nothing to seed).
    @Published private(set) var isSeeding = false
    @Published private(set) var line = ""

    private var started = false

    /// Call once from `SkriftApp.init`. A no-op without `-perfLibrary`, on a failed store, and on
    /// every launch after the first (the seeded marker exists).
    func begin(container: ModelContainer, isUsable: Bool) {
        guard PerfLibrary.isActive, !started else { return }
        started = true
        guard isUsable, !PerfLibrary.isSeeded else {
            PerfLibrary.logProgress("perf library already seeded — opening it as is")
            return
        }
        isSeeding = true
        line = "Seeding perf library…"
        PerfLibrary.logProgress("seeding start")
        let recordings = AppPaths.recordingsDirectory
        let started = Date()
        Task.detached(priority: .userInitiated) {
            // Its own context on this container: the UI never touches the store until we finish.
            let context = ModelContext(container)
            context.autosaveEnabled = false
            do {
                let summary = try PerfLibrarySeeder.seed(into: context, recordingsDirectory: recordings) { phase, done, total in
                    let text = "perf library: \(phase) \(done)/\(total)"
                    PerfLibrary.logProgress(text)
                    DevLog.log(text)
                    Task { @MainActor in PerfLibraryLaunch.shared.line = "Seeding perf library — \(phase) \(done) / \(total)" }
                }
                PerfLibrary.writeNames(PerfLibrarySeeder.makePeople(count: 150, now: Date()))
                PerfLibrary.markSeeded()
                let secs = Int(Date().timeIntervalSince(started))
                let done = "perf library seeded: \(summary.memos) notes, \(summary.assets) assets, \(summary.people) people in \(secs)s"
                PerfLibrary.logProgress(done)
                DevLog.log(done)
            } catch {
                PerfLibrary.logProgress("perf library seed FAILED: \(error)")
                DevLog.log("perf library seed FAILED: \(error)")
            }
            await MainActor.run { PerfLibraryLaunch.shared.isSeeding = false }
        }
    }
}

/// Shown instead of the app while the perf library is being generated (first launch only).
struct PerfSeedingView: View {
    @ObservedObject var launch: PerfLibraryLaunch
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(launch.line).font(.footnote.monospacedDigit()).multilineTextAlignment(.center)
            Text("Skrift Dev, perf library (never synced)").font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
#endif
