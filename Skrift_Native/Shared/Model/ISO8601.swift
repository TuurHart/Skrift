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

    static func now() -> String { string(from: Date()) }
    static func string(from date: Date) -> String { formatter.string(from: date) }
    static func date(from string: String) -> Date? { formatter.date(from: string) }
}
