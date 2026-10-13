import Foundation

/// The editor's formatting RULES (D115, signed mock Q350-note-editor-apple), pure text in and
/// text out so the phone's selection bar / Aa panel and the Mac's Aa popover write the same
/// Markdown. The body stays plain Markdown (C116): every style is a visible mark the renderers
/// dim (C24). Underline has no Markdown, so it writes `<u>…</u>` (Obsidian renders it), and the
/// dimming treats the two tags as a mark pair like `**`.
enum BodyFormat {

    enum InlineMark: CaseIterable, Hashable {
        case bold, italic, underline, strike
        var open: String {
            switch self { case .bold: "**"; case .italic: "*"; case .underline: "<u>"; case .strike: "~~" }
        }
        var close: String {
            switch self { case .bold: "**"; case .italic: "*"; case .underline: "</u>"; case .strike: "~~" }
        }
    }

    /// What the Aa panel's style rows set on the caret's line.
    enum LineStyle: Equatable { case title, heading, body, bullet, numbered, checklist }

    struct Edit: Equatable { let range: NSRange; let replacement: String }

    /// The new text, the selection to restore, and the edits (in ORIGINAL coordinates, in
    /// ascending order; apply them back to front) so an editor can patch its storage in place.
    struct Result: Equatable {
        let text: String
        let selection: NSRange
        let edits: [Edit]
    }

    // MARK: B I U S

    /// Wrap the selection in `mark`, or unwrap it when it already carries it (marks just
    /// outside the selection, or the selection's own first/last characters). Edge spaces stay
    /// outside the marks; an empty selection inserts an empty pair with the caret inside.
    static func toggle(_ mark: InlineMark, in text: String, selection: NSRange) -> Result {
        let ns = text as NSString
        let sel = trimmed(selection, in: ns)
        let o = (mark.open as NSString).length, c = (mark.close as NSString).length
        if let inner = includedPair(mark, in: ns, sel: sel) {
            let edits = [Edit(range: NSRange(location: sel.location, length: o), replacement: ""),
                         Edit(range: NSRange(location: NSMaxRange(sel) - c, length: c), replacement: "")]
            return Result(text: applying(edits, to: ns), selection: NSRange(location: sel.location, length: inner), edits: edits)
        }
        if wrappedOutside(mark, in: ns, sel: sel) {
            let edits = [Edit(range: NSRange(location: sel.location - o, length: o), replacement: ""),
                         Edit(range: NSRange(location: NSMaxRange(sel), length: c), replacement: "")]
            return Result(text: applying(edits, to: ns), selection: NSRange(location: sel.location - o, length: sel.length), edits: edits)
        }
        let edits = [Edit(range: NSRange(location: sel.location, length: 0), replacement: mark.open),
                     Edit(range: NSRange(location: NSMaxRange(sel), length: 0), replacement: mark.close)]
        return Result(text: applying(edits, to: ns), selection: NSRange(location: sel.location + o, length: sel.length), edits: edits)
    }

    /// Whether the selection already carries `mark` (lights the bar's button).
    static func isActive(_ mark: InlineMark, in text: String, selection: NSRange) -> Bool {
        let ns = text as NSString
        let sel = trimmed(selection, in: ns)
        return includedPair(mark, in: ns, sel: sel) != nil || wrappedOutside(mark, in: ns, sel: sel)
    }

    private static func trimmed(_ r: NSRange, in ns: NSString) -> NSRange {
        var sel = NSRange(location: min(r.location, ns.length), length: 0)
        sel.length = min(r.length, ns.length - sel.location)
        func space(_ i: Int) -> Bool {
            let ch = ns.character(at: i); return ch == 32 || ch == 9 || ch == 10
        }
        while sel.length > 0, space(sel.location) { sel.location += 1; sel.length -= 1 }
        while sel.length > 0, space(NSMaxRange(sel) - 1) { sel.length -= 1 }
        return sel
    }

    private static func stars(in ns: NSString, from i: Int, step: Int) -> Int {
        var n = 0, j = i
        while j >= 0, j < ns.length, ns.character(at: j) == 42 { n += 1; j += step }
        return n
    }

    /// `**`/`*` share a character: bold is on when both sides hold ≥2 stars, italic when the
    /// shorter side holds an odd count (1 or 3).
    private static func starMarkOn(_ mark: InlineMark, left: Int, right: Int) -> Bool {
        let m = min(left, right)
        return mark == .bold ? m >= 2 : m % 2 == 1
    }

    private static func wrappedOutside(_ mark: InlineMark, in ns: NSString, sel: NSRange) -> Bool {
        if mark == .bold || mark == .italic {
            return starMarkOn(mark, left: stars(in: ns, from: sel.location - 1, step: -1),
                              right: stars(in: ns, from: NSMaxRange(sel), step: 1))
        }
        let o = (mark.open as NSString).length, c = (mark.close as NSString).length
        guard sel.location >= o, NSMaxRange(sel) + c <= ns.length else { return false }
        return ns.substring(with: NSRange(location: sel.location - o, length: o)) == mark.open
            && ns.substring(with: NSRange(location: NSMaxRange(sel), length: c)) == mark.close
    }

    /// The inner length when the selection itself starts with the open mark and ends with the close.
    private static func includedPair(_ mark: InlineMark, in ns: NSString, sel: NSRange) -> Int? {
        let o = (mark.open as NSString).length, c = (mark.close as NSString).length
        guard sel.length > o + c else { return nil }
        if mark == .bold || mark == .italic {
            let l = stars(in: ns, from: sel.location, step: 1)
            let r = stars(in: ns, from: NSMaxRange(sel) - 1, step: -1)
            guard l < sel.length, starMarkOn(mark, left: l, right: r) else { return nil }
            return sel.length - o - c
        }
        guard ns.substring(with: NSRange(location: sel.location, length: o)) == mark.open,
              ns.substring(with: NSRange(location: NSMaxRange(sel) - c, length: c)) == mark.close
        else { return nil }
        return sel.length - o - c
    }

    private static func applying(_ edits: [Edit], to ns: NSString) -> String {
        let out = NSMutableString(string: ns)
        for e in edits.reversed() { out.replaceCharacters(in: e.range, with: e.replacement) }
        return out as String
    }

    // MARK: the dim-visible marks

    struct MarkSpan: Equatable {
        let mark: InlineMark
        let open: NSRange
        let content: NSRange
        let close: NSRange
    }

    private static let pairRegexes: [(InlineMark, NSRegularExpression)] = [
        (.bold, try! NSRegularExpression(pattern: #"\*\*(?=[^\s*])(.+?)(?<=[^\s])\*\*"#)),
        (.strike, try! NSRegularExpression(pattern: #"~~(?=\S)(.+?)(?<=\S)~~"#)),
        (.underline, try! NSRegularExpression(pattern: #"<u>(.+?)</u>"#)),
    ]
    private static let italicRegex = try! NSRegularExpression(
        pattern: #"(?<![*\w])\*(?=[^\s*])([^*\n]+?)(?<=[^\s*])\*(?![*\w])"#)

    /// Every inline mark pair in `text` (within one line). The renderers dim `open`/`close` and
    /// style `content`; characters stay verbatim.
    static func inlineMarks(in text: String) -> [MarkSpan] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var out: [MarkSpan] = []
        for (mark, rx) in pairRegexes {
            let o = (mark.open as NSString).length, c = (mark.close as NSString).length
            for m in rx.matches(in: text, range: full) where !ns.substring(with: m.range).contains("\n") {
                out.append(MarkSpan(mark: mark,
                                    open: NSRange(location: m.range.location, length: o),
                                    content: m.range(at: 1),
                                    close: NSRange(location: NSMaxRange(m.range) - c, length: c)))
            }
        }
        // Italic: read with the bold marks masked so `**x**` never looks like `*` pairs.
        let masked = NSMutableString(string: ns)
        for s in out where s.mark == .bold {
            masked.replaceCharacters(in: s.open, with: "\u{1}\u{1}")
            masked.replaceCharacters(in: s.close, with: "\u{1}\u{1}")
        }
        for m in italicRegex.matches(in: masked as String, range: full) {
            out.append(MarkSpan(mark: .italic,
                                open: NSRange(location: m.range.location, length: 1),
                                content: m.range(at: 1),
                                close: NSRange(location: NSMaxRange(m.range) - 1, length: 1)))
        }
        return out.sorted { $0.open.location < $1.open.location }
    }

    // MARK: Aa: the caret line's style

    private static let prefixRegex = try! NSRegularExpression(
        pattern: #"^(?:(#{1,6}) |(- \[[ xX]\] )|([-*+] )|(\d+)[.)] )"#)

    /// The line's style and the length of its Markdown prefix.
    static func parse(line: String) -> (style: LineStyle, prefix: Int, number: Int?) {
        let ns = line as NSString
        guard let m = prefixRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
        else { return (.body, 0, nil) }
        if m.range(at: 1).location != NSNotFound {
            return (m.range(at: 1).length == 1 ? .title : .heading, m.range.length, nil)
        }
        if m.range(at: 2).location != NSNotFound { return (.checklist, m.range.length, nil) }
        if m.range(at: 3).location != NSNotFound { return (.bullet, m.range.length, nil) }
        return (.numbered, m.range.length, Int(ns.substring(with: m.range(at: 4))))
    }

    static func lineStyle(at location: Int, in text: String) -> LineStyle {
        let ns = text as NSString
        let line = ns.lineRange(for: NSRange(location: min(location, ns.length), length: 0))
        return parse(line: ns.substring(with: line).trimmingCharacters(in: .newlines)).style
    }

    /// Set the caret line's style. Picking the list the line already is turns it back into body
    /// text (Apple Notes' toggle); a line never stacks two prefixes. A numbered line continues
    /// the number of the line above it.
    static func setStyle(_ style: LineStyle, in text: String, selection: NSRange) -> Result {
        let ns = text as NSString
        let caret = min(selection.location, ns.length)
        let lineR = ns.lineRange(for: NSRange(location: caret, length: 0))
        let line = ns.substring(with: lineR).trimmingCharacters(in: .newlines)
        let current = parse(line: line)
        var target = style
        if target == current.style, [.bullet, .numbered, .checklist].contains(target) { target = .body }
        var number = 1
        if target == .numbered, lineR.location > 0 {
            let prev = ns.lineRange(for: NSRange(location: lineR.location - 1, length: 0))
            if let n = parse(line: ns.substring(with: prev).trimmingCharacters(in: .newlines)).number { number = n + 1 }
        }
        let prefix: String
        switch target {
        case .title: prefix = "# "
        case .heading: prefix = "## "
        case .body: prefix = ""
        case .bullet: prefix = "- "
        case .numbered: prefix = "\(number). "
        case .checklist: prefix = "- [ ] "
        }
        let edit = Edit(range: NSRange(location: lineR.location, length: current.prefix), replacement: prefix)
        let delta = (prefix as NSString).length - current.prefix
        let textStart = lineR.location + current.prefix
        let loc = caret >= textStart ? caret + delta : lineR.location + (prefix as NSString).length
        let out = applying([edit], to: ns)
        let len = min(selection.length, (out as NSString).length - loc)
        return Result(text: out, selection: NSRange(location: loc, length: max(0, len)), edits: [edit])
    }

    // MARK: D112: move a photo between paragraphs

    /// Move picture `marker`'s paragraph so it lands before paragraph `index` of the body
    /// WITHOUT it (0 = the top, past the end = the bottom). Every other paragraph, and every
    /// other marker, keeps its order; an absent marker leaves the body as it was.
    static func movePhoto(marker: Int, in body: String, toParagraph index: Int) -> String {
        let literal = BodyV2Marker.literal(marker)
        var paras = body.components(separatedBy: "\n\n")
        guard let from = paras.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == literal })
        else { return body }
        let block = paras.remove(at: from)
        paras.insert(block, at: max(0, min(index, paras.count)))
        return paras.joined(separator: "\n\n")
    }
}
