import Foundation

/// Launch hook (called from `SkriftApp.init`) that installs the polish engine on
/// capable devices. OWNED BY THE POLISH LANE — the conductor ships it as a no-op
/// so every other surface compiles + honestly reports "unavailable" until the
/// engine lands; the lane replaces the body with the MLX engine install.
enum PolishBootstrap {
    static func installEngineIfSupported() {
        // Engine not wired yet (Polish lane): PolishCenter.isAvailable stays
        // false and no polish UI appears anywhere.
    }
}
