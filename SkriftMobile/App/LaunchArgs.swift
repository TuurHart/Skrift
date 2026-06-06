import Foundation

/// Launch-argument parsing, mirroring the Pike Companion test harness. Accepts
/// both `-key value` and `-key=value` forms.
extension Array where Element == String {
    func boolFlag(_ key: String) -> Bool {
        contains { $0 == key || $0.hasPrefix("\(key)=") }
    }

    func stringValue(_ key: String) -> String? {
        if let i = firstIndex(of: key), i + 1 < count { return self[i + 1] }
        if let raw = first(where: { $0.hasPrefix("\(key)=") }) {
            return String(raw.dropFirst("\(key)=".count))
        }
        return nil
    }

    func intValue(_ key: String) -> Int? { stringValue(key).flatMap(Int.init) }
}

/// Test seams the app reads at launch (`MOBILE_NATIVE_REWRITE_PLAN.md` §5). The
/// Simulator has no Neural Engine and FluidAudio pulls ~600MB, so UI tests SEED
/// state via these flags rather than running real ASR.
enum LaunchFlags {
    private static var args: [String] { ProcessInfo.processInfo.arguments }

    /// Fresh in-memory SwiftData store per launch — deterministic UI tests, and
    /// the demo seeder runs every time (the persistent store would otherwise
    /// survive across runs and the idempotent seeder would skip).
    static var inMemoryStore: Bool { args.boolFlag("-inMemoryStore") }
    static var seedDemoMemos: Bool { args.boolFlag("-seedDemoMemos") }
    static var seedDemoNames: Bool { args.boolFlag("-seedDemoNames") }
    /// Stub the Mac sync layer so UI tests don't need a live backend.
    static var mockMac: Bool { args.boolFlag("-mockMac") }
}
