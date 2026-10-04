import Foundation

/// Launch-argument parsing for both apps (the headless harnesses, the screenshot rigs, the
/// test seams). Accepts both `-key value` and `-key=value`.
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

    /// The `n` arguments that follow `key` (`-readalongcheck <audio> <sidecar>` is n = 2).
    /// nil when the flag is absent or fewer than `n` arguments follow it.
    func values(after key: String, count n: Int) -> [String]? {
        guard let i = firstIndex(of: key), i + n < count else { return nil }
        return Array(self[(i + 1)...(i + n)])
    }
}

enum LaunchArgs {
    static var all: [String] { ProcessInfo.processInfo.arguments }

    /// `-key` present (or `-key=…`).
    static func has(_ key: String, in args: [String] = LaunchArgs.all) -> Bool { args.boolFlag(key) }

    /// The argument after `-key`, or the `value` of `-key=value`.
    static func value(after key: String, in args: [String] = LaunchArgs.all) -> String? {
        args.stringValue(key)
    }

    /// The `n` arguments after `-key`.
    static func values(after key: String, count n: Int, in args: [String] = LaunchArgs.all) -> [String]? {
        args.values(after: key, count: n)
    }

    /// `-isolatedRun` (DEBUG, Mac): the Dev app runs on in-memory, non-CloudKit stores and
    /// scratch temp dirs, so a corpus-seeded eyeball run never touches the real Dev data.
    static let isolatedFlag = "-isolatedRun"
    static var isolatedRun: Bool { has(isolatedFlag) }

    /// True inside an XCTest host: CloudKit, the embedder and the launch sweeps stay off.
    static var isXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
