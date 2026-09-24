import Foundation

/// C19 whitespace at commit + C20 speech paragraphing, the two text rules body v2 applies.
enum BodyV2Text {

    // MARK: - C19

    /// A list-item line (bullet `- * +`, a task box, or `1.`/`1)`) — the only line shape whose
    /// leading whitespace is INDENTATION, not noise. A leading tab/run before plain text renders
    /// as a code block in Obsidian, so every other line still collapses its leading run too.
    private static let listItemLine = try! NSRegularExpression(pattern: #"^(?:[-*+]\s|\d+[.)]\s)"#)

    /// The ONE whitespace rule, applied once at commit: CRLF/CR → LF; horizontal runs → one
    /// space, EXCEPT a list item's leading run (kept verbatim, so a nested list survives — C19);
    /// ≥3 line breaks → one blank line; ends trimmed.
    static func normalised(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = t.components(separatedBy: "\n").map { line -> String in
            guard let leadingRange = line.range(of: #"^[\t\p{Zs}]*"#, options: .regularExpression) else { return line }
            let leading = line[leadingRange]
            let rest = String(line[leadingRange.upperBound...])
            let isListItem = listItemLine.firstMatch(in: rest, range: NSRange(location: 0, length: (rest as NSString).length)) != nil
            let collapsedRest = rest.replacingOccurrences(of: #"[\t\p{Zs}]+"#, with: " ", options: .regularExpression)
            return isListItem ? leading + collapsedRest
                : line.replacingOccurrences(of: #"[\t\p{Zs}]+"#, with: " ", options: .regularExpression)
        }
        t = lines.joined(separator: "\n")
        t = t.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - C20

    /// The paragraph gap on every device (D5).
    static let gap: TimeInterval = 2.0
    static let maxSentences = 4

    private static let closers: Set<Character> = ["\"", "”", "'", "’", ")", "]", "»"]

    /// True when `word` ends a sentence: last non-closer character is `. ? !`.
    static func endsSentence(_ word: Substring) -> Bool {
        guard let last = word.reversed().first(where: { !closers.contains($0) }) else { return false }
        return last == "." || last == "?" || last == "!"
    }

    /// UTF-16 locations of the tokens that open a new paragraph: the previous token ended a
    /// sentence AND (the pause before this word ≥ `gap` OR the paragraph already holds
    /// `maxSentences`). Text that already has a newline is untouched (empty result); so is
    /// text with no word times (typed text is never paragraphed). Tokens pair with `words`
    /// by index, as the recogniser emitted them.
    static func breakLocations(in text: String, words: [WordTiming]) -> [Int] {
        guard !words.isEmpty, !text.contains("\n") else { return [] }
        let ns = text as NSString
        let tokens = try! NSRegularExpression(pattern: #"\S+"#)
            .matches(in: text, range: NSRange(location: 0, length: ns.length))
        var out: [Int] = []
        var sentences = 0
        var prevEnded = false
        for (i, m) in tokens.enumerated() where i < words.count {
            if i > 0, prevEnded,
               words[i].start - words[i - 1].end >= gap || sentences >= maxSentences {
                out.append(m.range.location)
                sentences = 0
            }
            prevEnded = endsSentence(Substring(ns.substring(with: m.range)))
            if prevEnded { sentences += 1 }
        }
        return out
    }
}
