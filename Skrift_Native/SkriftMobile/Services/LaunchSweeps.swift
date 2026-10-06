import Foundation
import SwiftData

/// Q316 — the order and cadence of the phone's corpus sweeps at cold launch, on return to the
/// app, and after a CloudKit import burst. The bodies run on `SweepActor` (off the main
/// thread); this decides WHEN, and makes sure the first frame never waits on any of it.
///
/// - The recording-recovery sweep (C99) is NOT started here. `SkriftApp` runs it first and
///   calls `launch` only after it returned, so a rebuilt take is already in the store when
///   the asset / photo sweeps look.
/// - Runs are chained (`enqueue`): a foreground that arrives while the launch pass is still
///   going waits for it instead of racing it.
/// - `LaunchWorkGate` is marked at launch (and again when the pass ends, since the pass's own
///   asset captures move the asset count), so the first real foreground does not repeat the
///   launch sweeps.
@MainActor
enum LaunchSweeps {
    private static var actors: [ObjectIdentifier: SweepActor] = [:]
    private static var tail: Task<Void, Never>?

    /// One actor per container (tests build their own in-memory containers).
    static func sweepActor(for repository: NotesRepository) -> SweepActor {
        let key = ObjectIdentifier(repository.container)
        if let existing = actors[key] { return existing }
        let made = SweepActor(container: repository.container)
        actors[key] = made
        return made
    }

    @discardableResult
    private static func enqueue(_ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        tail = task
        return task
    }

    /// Cold launch (after recovery). Returns at once; the returned task finishes when the
    /// whole pass has (tests await it, the app does not).
    @discardableResult
    static func launch(_ repository: NotesRepository,
                       checkpoint: AssetCaptureCheckpoint = .standard) -> Task<Void, Never> {
        _ = LaunchWorkGate.shouldRunSweeps(repository: repository)   // mark: the first foreground is not a first run
        return enqueue {
            let sweeps = sweepActor(for: repository)
            await memoCorpusPass(repository, sweeps: sweeps, checkpoint: checkpoint)
            await fadingPass(repository, sweeps: sweeps)
            _ = LaunchWorkGate.shouldRunSweeps(repository: repository)   // absorb this pass's own asset rows
        }
    }

    /// A return to the app. `gated` is true when the memo corpus moved since the last mark
    /// (`LaunchWorkGate`); the caller then also runs its own cheap cloud-sync steps. The
    /// time-gated sweep (Fading purge clocks) runs on EVERY foreground.
    @discardableResult
    static func foreground(_ repository: NotesRepository,
                           checkpoint: AssetCaptureCheckpoint = .standard)
        -> (task: Task<Void, Never>, gated: Bool) {
        let gated = LaunchWorkGate.shouldRunSweeps(repository: repository)
        let task = enqueue {
            let sweeps = sweepActor(for: repository)
            await fadingPass(repository, sweeps: sweeps)
            if gated {
                await memoCorpusPass(repository, sweeps: sweeps, checkpoint: checkpoint)
            }
        }
        return (task, gated)
    }

    /// After a CloudKit import burst (the coalesced pass in `CloudSyncMonitor`).
    @discardableResult
    static func importBurst(_ repository: NotesRepository,
                            checkpoint: AssetCaptureCheckpoint = .standard) -> Task<Void, Never> {
        enqueue {
            await memoCorpusPass(repository, sweeps: sweepActor(for: repository), checkpoint: checkpoint)
        }
    }

    /// Dedupe, then asset sync, then photo OCR discovery: the old main-actor order.
    private static func memoCorpusPass(_ repository: NotesRepository, sweeps: SweepActor,
                                       checkpoint: AssetCaptureCheckpoint) async {
        let deduped = await sweeps.dedupe()
        let wroteAssets = await sweeps.syncAssets(checkpoint: checkpoint)
        // The main context saw none of these writes through its own save(); bump its caches.
        if deduped || wroteAssets { repository.save() }
        await PhotoTextIndexer.runOffMain(repository, sweeps: sweeps)
    }

    private static func fadingPass(_ repository: NotesRepository, sweeps: SweepActor) async {
        if await sweeps.fade() > 0 { repository.save() }
    }
}
