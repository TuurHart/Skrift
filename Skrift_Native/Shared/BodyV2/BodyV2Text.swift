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
    /// ≥3 line breaks → one blank line; the paragraph after a picture paragraph loses its
    /// leading run (v1's wrap `one.\n\n[[img_001]]\n\n That` — C10, D143); ends trimmed.
    static func normalised(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = t.components(separatedBy: "\n").map { line -> String in
            let ns = line as NSString
            let leadingLength = leadingRun.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))?.range.length ?? 0
            if leadingLength > 0 {
                let rest = ns.substring(from: leadingLength)
                if listItemLine.firstMatch(in: rest, range: NSRange(location: 0, length: (rest as NSString).length)) != nil {
                    return ns.substring(to: leadingLength) + collapseHorizontal(rest)
                }
            }
            return collapseHorizontal(line)
        }
        t = lines.joined(separator: "\n")
        t = blankLines.stringByReplacingMatches(
            in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "\n\n")
        t = afterPicture.stringByReplacingMatches(
            in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "$1")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let leadingRun = try! NSRegularExpression(pattern: #"^[\t\p{Zs}]*"#)
    private static let horizontalRun = try! NSRegularExpression(pattern: #"[\t\p{Zs}]+"#)
    private static let blankLines = try! NSRegularExpression(pattern: #"\n{3,}"#)

    private static func collapseHorizontal(_ s: String) -> String {
        horizontalRun.stringByReplacingMatches(
            in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
    }

    /// A picture paragraph (a line of only `[[img_NNN]]`), its blank line, then the next
    /// paragraph's leading horizontal run — unless that line is a list item (D143). The run is
    /// possessive so a partial match can't slip past the list-item check.
    private static let afterPicture = try! NSRegularExpression(
        pattern: #"(?m)(^\[\[img_\d+\]\]\n\n)[\t\p{Zs}]++(?![-*+]\s|\d+[.)]\s)"#)

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
    ///
    /// `clipStarts` (C124): in a merged multi-clip note each clip begins a paragraph. The first
    /// token whose word starts at or after a clip's start opens one, whatever the pause or the
    /// sentence state, and whether or not the text already holds newlines (a picture paragraph
    /// may have been placed first). The first word of the note never gets a break.
    static func breakLocations(in text: String, words: [WordTiming], clipStarts: [Double] = []) -> [Int] {
        guard !words.isEmpty else { return [] }
        let ns = text as NSString
        let all = try! NSRegularExpression(pattern: #"\S+"#)
            .matches(in: text, range: NSRange(location: 0, length: ns.length))
        // A speaker turn header (`**Speaker 1:**`, `**[[Maria]]:**`) is text the recogniser never
        // emitted: its tokens must not count against the words, or every turn shifts the pairing.
        let headers = (try? NSRegularExpression(pattern: #"\*\*[^\n*]+:\*\*"#))?
            .matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range) ?? []
        func inHeader(_ r: NSRange) -> Bool { headers.contains { NSIntersectionRange($0, r).length > 0 } }
        let tokens = all.filter { !inHeader($0.range) }
        var forced = Set<Int>()                       // token indexes that open a clip
        for start in clipStarts where start > 0 {
            if let i = words.firstIndex(where: { $0.start >= start - 0.05 }), i > 0, i < tokens.count {
                // Already the first word of a turn or a line: that is a paragraph start already.
                let loc = tokens[i].range.location
                var back = loc
                while back > 0, ns.character(at: back - 1) == 32 || ns.character(at: back - 1) == 9 { back -= 1 }
                let atLineStart = back == 0 || ns.character(at: back - 1) == 10
                let afterHeader = headers.contains { $0.location + $0.length == back }
                if !atLineStart, !afterHeader { forced.insert(i) }
            }
        }
        if text.contains("\n") { return forced.sorted().map { tokens[$0].range.location } }
        var out: [Int] = []
        var sentences = 0
        var prevEnded = false
        for (i, m) in tokens.enumerated() where i < words.count {
            if forced.contains(i)
                || (i > 0 && prevEnded
                    && (words[i].start - words[i - 1].end >= gap || sentences >= maxSentences)) {
                out.append(m.range.location)
                sentences = 0
            }
            prevEnded = endsSentence(Substring(ns.substring(with: m.range)))
            if prevEnded { sentences += 1 }
        }
        return out
    }
}
