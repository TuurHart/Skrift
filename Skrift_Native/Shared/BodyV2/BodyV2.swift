import Foundation

/// Body v2 (rewrite target 1): the text a note STORES, built once at commit. A picture is its
/// own paragraph, always (`\n\n[[img_NNN]]\n\n`, C10); the renderers and the export read it
/// as-is, so there is no render-time snap. Lives beside v1 (C2): nothing in the app calls it
/// until the swap item.
///
/// Placement:
/// - speech the user never edited, with word times: every manifest picture is placed from
///   its moment — after the sentence being spoken at `offsetSeconds` (C11, C16). A moment
///   before the first word (offset 0 = no moment) puts it at the TOP (C12). Same spot →
///   consecutive paragraphs in manifest order (C13). Speech paragraphs first (C20), so the
///   pictures never change where speech breaks.
/// - everything else (typed, edited, share captures, speech without word times): a marker
///   keeps its place in the sequence (C12, editor caret); one inside a sentence moves to that
///   sentence's end. A share capture's markerless pictures go to the TOP. A typed note is
///   never given a marker it doesn't have.
/// - inside a list item / quote block the picture goes after the item / the block (D3); in a
///   conversation, after the sentence within the turn (C169).
/// Whitespace is normalised last, once (C19).
enum BodyV2 {

    enum Source: Equatable { case speech, typed, shareCapture }

    struct Input {
        var text: String
        var words: [WordTiming] = []
        var manifest: [ImageManifestEntry] = []
        var source: Source
        var userEdited: Bool = false
    }

    static func committed(_ input: Input) -> String {
        let text = input.text.replacingOccurrences(of: "\r\n", with: "\n")
        let count = input.manifest.count
        let timed = input.source == .speech && !input.userEdited && !input.words.isEmpty
        let runs = BodyV2Marker.runs(in: text, manifestCount: count)

        if !timed {
            if !runs.isEmpty, runs.allSatisfy({ isBlock($0, in: text) }) {
                return BodyV2Text.normalised(text)                  // already stored in v2 shape
            }
            if runs.isEmpty, input.userEdited || input.source == .typed || count == 0 {
                return BodyV2Text.normalised(text)
            }
        }

        let (bare, lifted) = lift(text, runs: runs)
        let ns = bare as NSString
        var spots: [(at: Int?, n: Int)] = []                        // nil = the top
        if timed {
            let ends = wordEnds(in: ns, words: input.words)
            for (i, entry) in input.manifest.enumerated() {
                let spoken = input.words.lastIndex { $0.start < entry.offsetSeconds }
                if let w = spoken, let end = ends[w] {
                    spots.append((spot(after: end - 1, in: ns), i + 1))
                } else {
                    spots.append((nil, i + 1))
                }
            }
        } else {
            let present = Set(lifted.map(\.n))
            if !input.userEdited, input.source != .typed {
                for n in 1...max(count, 1) where n <= count && !present.contains(n) { spots.append((nil, n)) }
            }
            for item in lifted {
                spots.append((item.at.map { loc in spot(after: max(loc - 1, 0), in: ns) }, item.n))
            }
        }
        let breaks = timed ? BodyV2Text.breakLocations(in: bare, words: input.words) : []
        return BodyV2Text.normalised(build(ns, spots: spots, breaks: breaks))
    }

    // MARK: - lifting markers out

    /// Strips the resolving marker runs, joining the text around each with the break the text
    /// itself had there. A v1-injected `\n\n[[img]]\n\n` wrap belongs to the marker, not to the
    /// prose, unless the line around it is structure (list item, quote, heading, speaker turn).
    /// Returns the bare text (trimmed) and each marker's location in it (nil = at the top).
    static func lift(_ text: String, runs: [BodyV2Marker.Run]) -> (String, [(at: Int?, n: Int)]) {
        let ns = text as NSString
        var out = ""
        var cursor = 0
        var lifted: [(at: Int?, n: Int)] = []
        for run in runs {
            out += ns.substring(with: NSRange(location: cursor, length: run.range.location - cursor))
            let atTop = out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let loc = (out as NSString).length
            lifted += run.numbers.map { (atTop ? nil : loc, $0) }
            let end = run.range.location + run.range.length
            if run.range.location > 0, end < ns.length {
                var newlines = run.newlinesBefore + run.newlinesAfter
                let structural = isStructure(lineBefore(run.range.location, in: ns))
                    || isStructure(ns.substring(from: end))
                if run.newlinesBefore >= 2, run.newlinesAfter >= 2, !structural { newlines -= 4 }
                out += newlines >= 2 ? "\n\n" : newlines == 1 ? "\n" : " "
            }
            cursor = end
        }
        out += ns.substring(from: cursor)
        let lead = (out as NSString).length - (out.drop { $0.isWhitespace || $0.isNewline }.utf16.count)
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        let length = (trimmed as NSString).length
        return (trimmed, lifted.map { ($0.at.map { min(max(0, $0 - lead), length) }, $0.n) })
    }

    /// A run already in v2 shape: its own paragraph, after a finished sentence / line of
    /// structure (or at the top), before a blank line (or at the end).
    static func isBlock(_ run: BodyV2Marker.Run, in text: String) -> Bool {
        let ns = text as NSString
        let end = run.range.location + run.range.length
        let before = run.range.location == 0
            || (run.newlinesBefore >= 2 && endsAtBoundary(ns.substring(to: run.range.location)))
        return before && (end == ns.length || run.newlinesAfter >= 2)
    }

    private static func endsAtBoundary(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = t.last(where: { !closers.contains($0) }) else { return true }
        if isStructure(String(t.split(separator: "\n", omittingEmptySubsequences: false).last ?? "")) { return true }
        return ".?!…:".contains(last)
    }

    // MARK: - where a picture goes

    private static let closers: Set<Character> = ["\"", "”", "'", "’", ")", "]", "»"]
    private static let closerUnits: Set<unichar> = [34, 0x201D, 39, 0x2019, 41, 93, 0xBB]
    private static let listLine = try! NSRegularExpression(pattern: #"^\s*(?:[-*+]\s|\d+[.)]\s)"#)
    private static let structureLine = try! NSRegularExpression(
        pattern: #"^\s*(?:[-*+]\s|\d+[.)]\s|>|#|\*\*[^*\n]+:\*\*)"#)

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }
    static func isStructure(_ line: String) -> Bool { matches(structureLine, line) }

    private static func lineBefore(_ loc: Int, in ns: NSString) -> String {
        let (s, _) = lineBounds(max(loc - 1, 0), in: ns)
        return ns.substring(with: NSRange(location: s, length: max(0, loc - s)))
    }

    private static func lineBounds(_ p: Int, in ns: NSString) -> (Int, Int) {
        var s = min(p, ns.length)
        while s > 0, ns.character(at: s - 1) != 10 { s -= 1 }
        var e = min(p, ns.length)
        while e < ns.length, ns.character(at: e) != 10 { e += 1 }
        return (s, e)
    }

    /// The location just after the sentence containing UTF-16 location `p` (C11) — or after
    /// the list item / the whole quote block it sits in (D3). A line end closes a sentence.
    static func spot(after p: Int, in ns: NSString) -> Int {
        let (s, lineEnd) = lineBounds(p, in: ns)
        var e = lineEnd
        let line = ns.substring(with: NSRange(location: s, length: e - s))
        if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
            while e < ns.length {
                let (ns2, ne) = lineBounds(e + 1, in: ns)
                let next = ns.substring(with: NSRange(location: ns2, length: ne - ns2))
                guard next.trimmingCharacters(in: .whitespaces).hasPrefix(">") else { break }
                e = ne
            }
            return e
        }
        if matches(listLine, line) { return e }
        var i = p
        while i < e {
            let c = ns.character(at: i)
            if c == 46 || c == 63 || c == 33 || c == 0x2026 {      // . ? ! …
                var j = i + 1
                while j < e, closerUnits.contains(ns.character(at: j)) { j += 1 }
                if j >= e || isSpace(ns.character(at: j)) { return j }
                i = j
                continue
            }
            i += 1
        }
        return e
    }

    /// End location of each timed word in `ns`, matched in order as a whole token.
    static func wordEnds(in ns: NSString, words: [WordTiming]) -> [Int?] {
        var cursor = 0
        return words.map { w in
            var from = cursor
            while from <= ns.length {
                let r = ns.range(of: w.word, range: NSRange(location: from, length: ns.length - from))
                guard r.location != NSNotFound, r.length > 0 else { return nil }
                let end = r.location + r.length
                let okBefore = r.location == 0 || !isWordUnit(ns.character(at: r.location - 1))
                let okAfter = end >= ns.length || !isWordUnit(ns.character(at: end))
                if okBefore && okAfter { cursor = end; return end }
                from = r.location + 1
            }
            return nil
        }
    }

    private static func isSpace(_ c: unichar) -> Bool { c == 32 || c == 9 || c == 10 || c == 0xA0 }
    private static func isWordUnit(_ c: unichar) -> Bool {
        guard let s = Unicode.Scalar(c) else { return true }
        return CharacterSet.alphanumerics.contains(s)
    }

    // MARK: - assembling

    /// Writes `ns` with each picture group as its own paragraph at its spot (trailing and
    /// leading whitespace there consumed) and a blank line at each speech break.
    static func build(_ ns: NSString, spots: [(at: Int?, n: Int)], breaks: [Int]) -> String {
        var groups: [Int: [Int]] = [:]
        var top: [Int] = []
        for s in spots.sorted(by: { $0.n < $1.n }) {
            if let at = s.at { groups[at, default: []].append(s.n) } else { top.append(s.n) }
        }
        var out = ""
        var i = 0
        for e in Set(groups.keys).union(breaks).sorted() where e >= i {
            let seg = ns.substring(with: NSRange(location: i, length: e - i))
            if let pics = groups[e] {
                out += trimTrailing(seg, newlines: false) + "\n\n" + BodyV2Marker.block(pics) + "\n\n"
                i = e
                while i < ns.length, isSpace(ns.character(at: i)) { i += 1 }
            } else {
                out += trimTrailing(seg, newlines: true) + "\n\n"
                i = e
            }
        }
        out += ns.substring(from: i)
        if !top.isEmpty {
            out = BodyV2Marker.block(top) + "\n\n" + out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return out
    }

    private static func trimTrailing(_ s: String, newlines: Bool) -> String {
        var t = Substring(s)
        while let c = t.last, c == " " || c == "\t" || (newlines && c.isNewline) { t = t.dropLast() }
        return String(t)
    }
}
