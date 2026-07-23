import Foundation

/// Launch hook (called from `SkriftApp.init`) that installs the polish engine on capable
/// devices. On an M-series iPad (`PolishGate.isSupported`) it installs `MLXPolishEngine`;
/// on the phone + simulator the gate is false, so `PolishCenter.isAvailable` stays false
/// and no polish UI appears anywhere. Engine init is cheap (registers a memory-warning
/// observer only) — NO model load at launch.
enum PolishBootstrap {
    static func installEngineIfSupported() {
        // Hop to the main actor: `PolishGate.isSupported` reads `UIDevice` and
        // `PolishCenter` is `@MainActor`. Runs a beat after launch — nothing at launch
        // reads `isAvailable` synchronously, and this keeps the call site (SHELL's
        // `SkriftApp.init`) isolation-agnostic.
        Task { @MainActor in
            #if DEBUG
            // Screenshot rig (`-fakePolishEngine`): the Simulator's gate is false
            // by design, which left every Process surface un-eyeballable — the
            // header button, its running state, the note bar's progress line.
            // This installs a canned engine (no MLX, no model) so those states
            // can be SEEN before they reach Tuur's iPad.
            if LaunchFlags.fakePolishEngine {
                PolishCenter.shared.install(engine: FakePolishEngine())
                return
            }
            #endif
            guard PolishGate.isSupported else { return }
            PolishCenter.shared.install(engine: MLXPolishEngine())
        }
    }
}

#if DEBUG
/// Canned stand-in for `MLXPolishEngine` — same seam, no model. Each step
/// sleeps briefly so a screenshot can catch the determinate progress.
struct FakePolishEngine: PolishEngine {
    func isModelOnDisk() async -> Bool { !LaunchFlags.fakePolishNeedsDownload }

    func downloadModel(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        for p in stride(from: 0.0, through: 1.0, by: 0.1) {
            onProgress(p)
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    func polish(transcript: String,
                onStep: @escaping @Sendable (PolishStep, Double) -> Void) async throws -> PolishResult {
        for step in PolishStep.allCases {
            onStep(step, Double(step.rawValue) / Double(PolishStep.total))
            try? await Task.sleep(for: .seconds(3))
        }
        return PolishResult(copyedit: transcript,
                            title: "Fake title",
                            summary: "Fake summary")
    }
}
#endif
