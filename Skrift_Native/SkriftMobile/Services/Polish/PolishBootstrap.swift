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
            guard PolishGate.isSupported else { return }
            PolishCenter.shared.install(engine: MLXPolishEngine())
        }
    }
}
