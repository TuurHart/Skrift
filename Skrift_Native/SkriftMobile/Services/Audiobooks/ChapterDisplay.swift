import Foundation

/// Reader-facing chapter titles (pure, host-less unit-tested in
/// `ChapterDisplayTests`). Synthesized multi-file chapter names carry the whole
/// source filename ("TheBeginningOfInfinity chapter 01" × 30 — unreadable in
/// the chapter menu, device finding 2026-06-12). Derivation:
///
/// 1. strip a known audio extension from each name,
/// 2. strip the longest common prefix shared by ALL the book's chapter names
///    (trimmed back to a separator boundary so it never splits a word or a
///    number),
/// 3. prettify the remainder: "chapter_01" / bare "01" → "Chapter 1",
///    otherwise the de-prefixed remainder itself (underscores → spaces).
///
/// Safety: the prefix is stripped ONLY when every remainder still carries a
/// digit — chapter files are numbered by nature, while real (m4b-embedded)
/// titles that merely share words ("The Spark" / "The Creation") must never
/// lose them. Real titles therefore pass through unchanged.
enum ChapterDisplay {
    /// Extensions worth stripping — ONLY known audio types, so a real title
    /// that happens to end ".Two" keeps its tail.
    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "wav", "flac", "ogg", "oga", "opus",
        "wma", "aiff", "aif", "mp4", "caf",
    ]

    private static let separators = Set<Character>(" _-.–—·")

    /// Display titles for a book's chapter names, same order/count as the
    /// input. `index` fallbacks ("Chapter N") use the position when a name
    /// prettifies to nothing.
    static func displayTitles(_ raw: [String]) -> [String] {
        let bases = raw.map {
            stripAudioExtension($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard bases.count >= 2 else {
            return bases.enumerated().map { prettify($1, index: $0) }
        }

        let prefix = boundaryTrimmed(longestCommonPrefix(bases))
        guard !prefix.isEmpty else {
            return bases.enumerated().map { prettify($1, index: $0) }
        }

        let remainders = bases.map {
            trimLeadingSeparators(String($0.dropFirst(prefix.count)))
        }
        // De-prefix only when every remainder still identifies its chapter
        // (carries a digit); else the names weren't filename-numbered parts.
        guard remainders.allSatisfy({
            !$0.isEmpty && $0.rangeOfCharacter(from: .decimalDigits) != nil
        }) else {
            return bases.enumerated().map { prettify($1, index: $0) }
        }
        return remainders.enumerated().map { prettify($1, index: $0) }
    }

    /// "chapter_01" / "chapter 1" / "01" / "7" → "Chapter N"; anything else is
    /// cleaned up (underscores → spaces, collapsed whitespace, separator trim)
    /// and kept — "01 - Creation" stays "01 - Creation". Empty → "Chapter
    /// (index+1)".
    static func prettify(_ name: String, index: Int) -> String {
        let cleaned = trimSeparators(
            name.replacingOccurrences(of: "_", with: " ")
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        )
        guard !cleaned.isEmpty else { return "Chapter \(index + 1)" }

        // Extended `#/…/#` delimiters: bare-slash regex literals need an
        // opt-in flag under SWIFT_VERSION 5.9.
        if let match = cleaned.wholeMatch(of: #/(?i)chapter[\s\-]*0*(\d{1,6})/#),
           let n = Int(match.1) {
            return "Chapter \(n)"
        }
        if let match = cleaned.wholeMatch(of: #/0*(\d{1,6})/#), let n = Int(match.1) {
            return "Chapter \(n)"
        }
        return cleaned
    }

    /// Drop a trailing ".mp3"-style extension when it's a known audio type.
    static func stripAudioExtension(_ name: String) -> String {
        let ns = name as NSString
        guard audioExtensions.contains(ns.pathExtension.lowercased()) else { return name }
        return ns.deletingPathExtension
    }

    /// Character-wise longest common prefix of all strings ("" when none).
    static func longestCommonPrefix(_ strings: [String]) -> String {
        guard let first = strings.first else { return "" }
        var prefix = Array(first)
        for s in strings.dropFirst() {
            let chars = Array(s)
            var i = 0
            while i < min(prefix.count, chars.count), prefix[i] == chars[i] { i += 1 }
            prefix = Array(prefix[..<i])
            if prefix.isEmpty { break }
        }
        return String(prefix)
    }

    /// Trim a raw common prefix back to (and including) its LAST separator, so
    /// stripping never splits mid-word or mid-number ("ch0" of "ch01"/"ch02"
    /// would otherwise leave "1"/"2" looking like different numbers than they
    /// are; "Cre" of "Creation"/"Crescendo" must strip nothing at all).
    static func boundaryTrimmed(_ prefix: String) -> String {
        guard let last = prefix.lastIndex(where: { separators.contains($0) }) else { return "" }
        return String(prefix[...last])
    }

    private static func trimLeadingSeparators(_ s: String) -> String {
        String(s.drop(while: { separators.contains($0) }))
    }

    private static func trimSeparators(_ s: String) -> String {
        var out = Substring(s)
        while let first = out.first, separators.contains(first) { out = out.dropFirst() }
        while let last = out.last, separators.contains(last) { out = out.dropLast() }
        return String(out)
    }
}
