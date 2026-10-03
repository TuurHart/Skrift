import Foundation

/// ISO-8601 timestamps formatted exactly like JavaScript's `Date.toISOString()`
/// (`2026-06-06T12:00:00.000Z`). The names sync compares `lastModifiedAt`
/// strings lexicographically, so this must stay byte-compatible everywhere a
/// timestamp is written — which is why it's ONE shared copy for both apps
/// (each used to carry an identical duplicate).
enum ISO8601 {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func now() -> String { string(from: Date()) }
    static func string(from date: Date) -> String { formatter.string(from: date) }
    static func date(from string: String) -> Date? { formatter.date(from: string) }

    /// For READING a metadata/creation date written either way: fractional seconds first, else
    /// plain. `date(from:)` stays fractional-only (names sync compares strings lexicographically).
    static func lenientDate(from string: String) -> Date? {
        formatter.date(from: string) ?? plainFormatter.date(from: string)
    }
}
