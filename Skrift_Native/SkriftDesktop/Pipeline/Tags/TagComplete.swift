import Foundation

/// Inline `#` tag completion — the PURE half of the body's Obsidian-style tag
/// popup (`BodyTextView` owns the AppKit completion session). Obsidian's tag
/// rules apply: letters/numbers/`_`/`-`/`/` (nested), NO spaces, case-insensitive.
/// Host-less (Pipeline, not Features) so the unit bundle tests it directly.
enum TagComplete {

    /// Prefix-matched candidates for the popup: original casing + caller order
    /// preserved (pass most-used-first), case-insensitively deduped, SPACE-FREE
    /// only (a spaced tag like "more tags" can't be an inline hashtag), capped
    /// so the list stays a menu.
    static func completions(partial: String, candidates: [String], max: Int = 8) -> [String] {
        let p = partial.lowercased()
        var seen = Set<String>()
        var out: [String] = []
        for c in candidates {
            let t = c.trimmingCharacters(in: .whitespaces)
            let lt = t.lowercased()
            guard !t.isEmpty, !t.contains(where: \.isWhitespace),
                  !seen.contains(lt), lt.hasPrefix(p) else { continue }
            seen.insert(lt)
            out.append(t)
            if out.count >= max { break }
        }
        return out
    }

    /// The word-portion range of a `#word` run ending at `caret` (UTF-16) — the
    /// partial the completion replaces — or nil when the caret isn't in one.
    /// The `#` must be preceded by whitespace/newline or start-of-text (so "C#"
    /// never triggers) and followed by ≥1 tag char (so a markdown "# " heading
    /// never does).
    static func hashtagPartialRange(in text: String, caret: Int) -> NSRange? {
        let ns = text as NSString
        guard caret > 0, caret <= ns.length else { return nil }
        var i = caret - 1
        var count = 0
        while i >= 0, isTagChar(ns.character(at: i)) { i -= 1; count += 1 }
        guard count >= 1, i >= 0, ns.character(at: i) == 35 /* # */ else { return nil }
        if i > 0 {
            let prev = ns.character(at: i - 1)
            guard prev == 32 || prev == 10 || prev == 9 else { return nil }
        }
        return NSRange(location: i + 1, length: count)
    }

    /// Obsidian's tag alphabet: alphanumerics + `_` `-` `/`.
    static func isTagChar(_ c: unichar) -> Bool {
        guard let scalar = UnicodeScalar(c) else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || c == 95 || c == 45 || c == 47
    }
}
