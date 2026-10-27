import Foundation

/// Q526b: warm Parakeet at app launch and on every return to foreground, so a recording
/// started seconds after opening the app has a loaded model (device 2026-10-27: the live
/// caption showed nothing for ~15 s because the first record cold-loaded Parakeet).
///
/// Single-flight: a request while a warm-up is in flight does nothing. The warm-up counts as
/// transcription activity from the moment `request` returns (the counter is raised
/// synchronously, before the background task starts), so the Connections embedder's cold
/// load — which polls `TranscriptionActivity.isActive` — waits behind it.
final class ASRPrewarm: @unchecked Sendable {
    typealias Probe = @Sendable () async -> Bool
    typealias Load = @Sendable () async throws -> Void

    static let shared = ASRPrewarm(
        isWarm: { await TranscriptionService.shared.isWarm },
        // Never trigger the ~600 MB first-run download from a launch hook: onboarding owns it.
        mayLoad: { UserDefaults.standard.bool(forKey: "modelEverReady") },
        load: { try await TranscriptionService.shared.ensureLoaded() })

    private let isWarm: Probe
    private let mayLoad: @Sendable () -> Bool
    private let load: Load
    private let lock = NSLock()
    private var inFlight = false
    private var requestCount = 0
    private var loadCount = 0

    init(isWarm: @escaping Probe, mayLoad: @escaping @Sendable () -> Bool = { true },
         load: @escaping Load) {
        self.isWarm = isWarm
        self.mayLoad = mayLoad
        self.load = load
    }

    /// Fire-and-forget. Cheap and non-blocking: safe to call from the main actor.
    /// Returns the task for tests to await; nil when a warm-up is already in flight or
    /// the model was never downloaded.
    @discardableResult
    func request(reason: String) -> Task<Void, Never>? {
        lock.lock()
        requestCount += 1
        if inFlight {
            lock.unlock()
            DevLog.log("asr: pre-warm (\(reason)) skipped — warm-up already in flight")
            return nil
        }
        guard mayLoad() else {
            lock.unlock()
            DevLog.log("asr: pre-warm (\(reason)) skipped — model not downloaded yet")
            return nil
        }
        inFlight = true
        lock.unlock()
        TranscriptionActivity.begin()   // synchronous: the embedder gate sees it immediately
        return Task.detached(priority: .utility) { [self] in
            defer {
                TranscriptionActivity.end()
                lock.lock(); inFlight = false; lock.unlock()
            }
            if await isWarm() {
                DevLog.log("asr: pre-warm (\(reason)) — already warm")
                return
            }
            lock.lock(); loadCount += 1; lock.unlock()
            DevLog.log("asr: pre-warm (\(reason)) — loading")
            do { try await load() } catch { DevLog.log("asr: pre-warm (\(reason)) FAILED \(error)") }
        }
    }

    var loads: Int { lock.lock(); defer { lock.unlock() }; return loadCount }
}
