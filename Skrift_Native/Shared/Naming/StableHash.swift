import Foundation

/// One launch-stable hash + one initials rule for avatars and book covers, on both apps.
/// Swift's `hashValue` is seeded per process, so it must never pick a colour.
enum StableHash {
    /// The Mac's original 31-hash over unicode scalars, kept so existing Mac avatar colours do not change.
    static func value(_ s: String) -> Int {
        s.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
    }

    /// Palette index for `key`; always in `0..<count` (0 when `count` <= 0).
    static func index(_ key: String, count: Int) -> Int {
        count > 0 ? value(key) % count : 0
    }

    /// Avatar initials: first letter of the first two words, uppercased; "?" when empty.
    /// `[[Name]]` link brackets are ignored.
    static func initials(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
        let chars = cleaned.split(separator: " ").prefix(2).compactMap(\.first)
        return chars.isEmpty ? "?" : String(chars).uppercased()
    }
}
