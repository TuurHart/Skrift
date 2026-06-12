import Foundation

/// Tiny append-only dev-build file logger (user-requested, 2026-06-12): the
/// recording/route P0s could not be diagnosed from "vibes" — this gives REAL
/// on-device traces. One-line API: `DevLog.log("...")`.
///
/// - Writes timestamped lines to `Documents/devlog.txt` — inside the app
///   container, so the existing devicectl pull workflow (the
///   pull-phone-feedback skill) grabs it along with everything else.
/// - Ring-buffer capped: when the file passes ~512 KB it is trimmed to the
///   most recent ~384 KB, aligned to a line boundary (oldest lines drop off).
/// - DEBUG builds only. In Release `log` is an inlined no-op and — because the
///   message is an `@autoclosure` — the string is never even built.
/// - Callable from ANY thread/actor (route-change handlers on main, the
///   recording writer queue, detached tasks): appends are serialized on a
///   private utility queue, never blocking the caller.
enum DevLog {
    /// Trim threshold: the file may briefly exceed this by one line.
    static let capBytes = 512 * 1024
    /// Post-trim size: what survives a trim (the newest lines).
    static let keepBytes = 384 * 1024

    /// Pure ring-buffer trim (unit-tested): when `data` exceeds `cap`, keep
    /// the most recent `keep` bytes, advanced to the next line boundary so
    /// the file never reopens mid-line. At or under the cap the data is
    /// returned unchanged.
    static func trimmed(_ data: Data, cap: Int, keep: Int) -> Data {
        guard data.count > cap else { return data }
        var tail = data.suffix(max(0, keep))
        // Drop the (likely partial) first line. If the only newline is the
        // final byte — one giant line — keep the raw tail rather than nothing.
        if let nl = tail.firstIndex(of: UInt8(ascii: "\n")), nl + 1 < tail.endIndex {
            tail = tail[(nl + 1)...]
        }
        return Data(tail)
    }

    #if DEBUG
    /// `Documents/devlog.txt` — pullable off the device with the rest of the
    /// app container.
    static let fileURL = AppPaths.documentsDirectory.appendingPathComponent("devlog.txt")

    private static let queue = DispatchQueue(label: "skrift.devlog", qos: .utility)
    // Queue-confined (only ever touched inside `queue` blocks).
    private nonisolated(unsafe) static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()
    private nonisolated(unsafe) static var didLogProcessBanner = false

    /// Append one timestamped line. Cheap at the call site: the string is
    /// built on the caller's thread, file I/O happens on the logger queue.
    static func log(_ message: @autoclosure () -> String) {
        let at = Date()
        let text = message()
        queue.async { append(at: at, text: text) }
    }

    /// Block until queued appends hit the disk (tests + pre-pull flushing).
    static func drain() { queue.sync {} }

    private static func append(at: Date, text: String) {
        if !didLogProcessBanner {
            didLogProcessBanner = true
            // Mark process boundaries so a pulled file separates app launches.
            write("\n—— Skrift Dev launch \(stamp.string(from: at)) pid=\(ProcessInfo.processInfo.processIdentifier) ——\n")
        }
        write("\(stamp.string(from: at))  \(text)\n")
        trimIfNeeded()
    }

    private static func write(_ line: String) {
        let data = Data(line.utf8)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            try? data.write(to: fileURL)
            return
        }
        // A fresh handle per line: route/lifecycle events are low-frequency,
        // and an unbuffered append-and-close survives a crash — which is
        // exactly when the log matters.
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private static func trimIfNeeded() {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size]) as? Int,
              size > capBytes,
              let whole = try? Data(contentsOf: fileURL) else { return }
        try? trimmed(whole, cap: capBytes, keep: keepBytes).write(to: fileURL, options: .atomic)
    }
    #else
    /// Release: a no-op the optimizer erases; the autoclosure means the
    /// message string is never built.
    @inline(__always)
    static func log(_ message: @autoclosure () -> String) {}
    #endif
}
