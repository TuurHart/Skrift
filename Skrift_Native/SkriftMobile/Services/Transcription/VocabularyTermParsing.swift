import Foundation

/// Pure parsing for a custom-vocabulary entry. A word the user adds in
/// Settings → Custom words may carry the forms Parakeet mis-hears, using the
/// "Canonical: alias1, alias2" syntax (the same shape FluidAudio's own
/// simple-format vocabulary files use):
///
///     "Skrift"                 → canonical "Skrift",  aliases []
///     "Skrift: script, scrift" → canonical "Skrift",  aliases ["script", "scrift"]
///
/// Aliases widen the rescorer's string-similarity gate so a mis-hearing that
/// edit-distance alone wouldn't catch still surfaces the canonical as a
/// replacement candidate. The canonical is always what gets written.
///
/// Host-less + unit-tested (`VocabularyTermParsingTests`). Mirrors the desktop
/// `Models/VocabularyTermParsing.swift` byte-for-byte in behaviour so both
/// boosters correct identically.
enum VocabularyTermParsing {
    struct Parsed: Equatable {
        let canonical: String
        let aliases: [String]
    }

    /// Split `entry` into its canonical word and any aliases. The canonical is
    /// everything before the first colon; aliases are the comma-separated
    /// remainder. Trims whitespace, drops empties, de-dups aliases
    /// case-insensitively, and drops an alias identical to the canonical.
    static func parse(_ entry: String) -> Parsed {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.firstIndex(of: ":") else {
            return Parsed(canonical: trimmed, aliases: [])
        }
        let canonical = String(trimmed[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = String(trimmed[trimmed.index(after: colon)...])
        var seen = Set<String>([canonical.lowercased()])
        let aliases = rest
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        guard !canonical.isEmpty else { return Parsed(canonical: trimmed, aliases: []) }
        return Parsed(canonical: canonical, aliases: aliases)
    }

    /// The canonical word for an entry — used wherever the booster needs the
    /// written form only (e.g. de-dup, display).
    static func canonical(_ entry: String) -> String { parse(entry).canonical }
}

/// Levenshtein-based string similarity, mirroring FluidAudio's
/// `1 - editDistance / maxLength` (the same measure its rescorer gates on).
enum VocabularySimilarity {
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(a.lowercased()), y = Array(b.lowercased())
        if x.isEmpty && y.isEmpty { return 1 }
        let maxLen = max(x.count, y.count)
        guard maxLen > 0 else { return 1 }
        let dist = levenshtein(x, y)
        return 1.0 - Double(dist) / Double(maxLen)
    }

    private static func levenshtein(_ x: [Character], _ y: [Character]) -> Int {
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = Swift.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[y.count]
    }
}

/// Trust guard for a booster replacement. FluidAudio's small-vocab rescorer runs
/// an aggressive **spotter-anchored rescue** pass (acoustic-only, no
/// string-similarity gate) that, once the booster is actually warm, mangles
/// ordinary speech containing none of the custom words — e.g. on a 2026-06-13
/// Mac probe the words [Skrift, Tiuri, Rox] turned "room"→"Rox" and
/// "its alias."→"Tiuri" on a clip that says none of them. We can't disable that
/// pass from outside FluidAudio, so the booster keeps a replacement only when it
/// also clears the SAFE bar: string-similarity ≥ 0.55 to the canonical OR a
/// near-exact hit on a user-supplied alias. Distant acoustic-only guesses are
/// dropped. The escape hatch for a genuinely distant mis-hearing is to add it as
/// an alias ("Skrift: scrubbed").
enum VocabularyTrust {
    /// Similarity floor — set just ABOVE FluidAudio's Route-1 floor (0.50). At
    /// exactly 0.50 a short vocab word collides with common words ("room"↔"Rox"
    /// is 0.50), so the +0.05 drops those borderline acoustic guesses while
    /// keeping the user's real pair "script"↔"Skrift" (0.667) with margin.
    static let similarityFloor = 0.55
    /// A transcript word this close to an alias counts as an explicit alias hit.
    static let aliasHitFloor = 0.85

    static func isTrusted(original: String, canonical: String, aliases: [String]) -> Bool {
        if VocabularySimilarity.similarity(original, canonical) >= similarityFloor { return true }
        return aliases.contains { VocabularySimilarity.similarity(original, $0) >= aliasHitFloor }
    }
}
