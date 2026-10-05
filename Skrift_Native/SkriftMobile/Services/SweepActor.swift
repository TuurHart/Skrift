import Foundation
import SwiftData
import os

/// Q316 — where the phone's corpus sweeps run: OFF the main thread.
///
/// Measured on the iPhone 13 with 2,000 notes (plan/perf2/MEASURED.md): cold launch spent
/// 4.1 s to first frame and a return from the home screen ~4 s of main-thread time in
/// `AssetMaterializer` (1.4 s of lstat + blob work), `allMemos`, `FadingSweep`,
/// `recoverStuckTranscriptions`, `PhotoTextIndexer` and `MemoDeduper`, all on `@MainActor`.
///
/// Rules this actor keeps (data safety first):
/// - **One serial executor.** Every sweep is a synchronous method on this actor, so two sweeps
///   never interleave, and the main actor never waits on one.
/// - **A fresh `ModelContext` per call**, never a long-lived one: no stale identity map across
///   sweeps, and the blobs a capture pass faults in are freed when the call returns.
/// - **No SwiftData object crosses the boundary.** Methods take and return plain values
///   (UUIDs, `PhotoTextIndexer.Job`, dates, counts); the main context re-fetches by id when
///   it needs a model object.
/// - **Explicit saves** inside each sweep. The main context sees them through the shared store.
/// - The recording-recovery sweep (C99) is NOT here and never waits on this: it runs first,
///   on the main actor, before `LaunchSweeps` starts anything.
actor SweepActor {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    /// `MemoDeduper`'s core. True if it trashed a clone (the caller bumps main's caches).
    func dedupe() -> Bool {
        SweepProbe.record("dedupe")
        let context = ModelContext(container)
        guard MemoDeduper.dedupe(in: context) else { return false }
        try? context.save()
        return true
    }

    /// Both `AssetMaterializer` directions. Capture examines only memos changed since the
    /// checkpoint (full when there is none, or the last full pass is older than
    /// `AssetMaterializer.fullSweepInterval`). Returns true if it wrote a `MemoAsset`.
    func syncAssets(checkpoint: AssetCaptureCheckpoint, now: Date = Date()) -> Bool {
        SweepProbe.record("assets")
        let context = ModelContext(container)
        AssetMaterializer.materializeMissing(in: context)
        let since = checkpoint.changedSince(now: now)
        let wrote = AssetMaterializer.captureMissing(in: context, changedSince: since, saveBatches: true)
        checkpoint.record(runAt: now, wasFull: since == nil)
        return wrote
    }

    /// `PhotoTextIndexer`'s discovery half: photos still waiting for OCR whose file is on disk.
    func photoJobs() -> [PhotoTextIndexer.Job] {
        SweepProbe.record("photoText")
        return PhotoTextIndexer.discoverJobs(in: ModelContext(container))
    }

    /// `FadingSweep`'s core. Returns the count of notes moved to Recently Deleted.
    @discardableResult
    func fade(now: Date = Date()) -> Int {
        SweepProbe.record("fading")
        return FadingSweep.run(in: ModelContext(container), now: now)
    }

    /// `MemoSaver.recoverStuckTranscriptions`'s discovery half (read-only).
    func stuckTranscriptionPlan() -> MemoSaver.StuckTranscriptionPlan {
        SweepProbe.record("stuckTranscriptions")
        return MemoSaver.stuckTranscriptionPlan(in: ModelContext(container))
    }
}

/// Where the asset-capture sweep left off, persisted so a launch examines only what changed.
/// `lastRun` is the START time of the last pass (an edit landing mid-pass is seen next time);
/// `lastFull` is the last pass that examined every memo (the weekly backstop for a sidecar
/// written long after its memo was last touched).
struct AssetCaptureCheckpoint: Sendable {
    let defaults: UserDefaults
    let key: String

    static var standard: AssetCaptureCheckpoint {
        #if DEBUG
        // Q313: the generated perf store is a different corpus; never share its checkpoint.
        let tag = PerfLibrary.isActive ? "perf" : "main"
        #else
        let tag = "main"
        #endif
        return AssetCaptureCheckpoint(defaults: .standard, key: "assetCapture.checkpoint.\(tag)")
    }

    private var lastRun: Date? { defaults.object(forKey: key + ".run") as? Date }
    private var lastFull: Date? { defaults.object(forKey: key + ".full") as? Date }

    /// nil = examine every memo (no checkpoint yet, or the weekly full pass is due).
    func changedSince(now: Date) -> Date? {
        guard let lastRun, let lastFull,
              now.timeIntervalSince(lastFull) < AssetMaterializer.fullSweepInterval,
              lastRun <= now else { return nil }
        return lastRun
    }

    func record(runAt: Date, wasFull: Bool) {
        defaults.set(runAt, forKey: key + ".run")
        if wasFull { defaults.set(runAt, forKey: key + ".full") }
    }
}

/// Test probe: which sweep bodies ran, and whether each ran on the main thread.
enum SweepProbe {
    struct Event: Equatable, Sendable {
        let name: String
        let onMainThread: Bool
    }
    private static let storage = OSAllocatedUnfairLock(initialState: [Event]())
    static var events: [Event] { storage.withLock { $0 } }
    static func reset() { storage.withLock { $0.removeAll() } }
    static func record(_ name: String) {
        let onMain = Thread.isMainThread
        storage.withLock { $0.append(Event(name: name, onMainThread: onMain)) }
    }
}
