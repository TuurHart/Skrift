import Foundation

/// Q380 (C239, C24/C116): WHICH ranges of a note body get the editor's markdown look, ONE rule
/// for both editors (phone `NoteBodyView`, Mac `BodyTextView`). Each app maps a role onto its own
/// fonts and colours; the characters never change (the stored text is the Markdown the export
/// writes). Before this, the phone and the Mac each walked `BodyFormat` / `BodyMarkdown` by hand
/// and drifted (the phone never styled fences or block quotes).
enum MarkdownLook {
    enum Role: Equatable {
        /// A syntax mark (`# `, `**`, `<u>`, a fence line, a quote's `> `): drawn dim.
        case mark
        /// A heading's words, level 1 = `#`.
        case heading(Int)
        /// The words between a B I U S / highlight / code pair.
        case inline(BodyFormat.InlineMark)
        /// Inside a ``` fence: monospaced.
        case fenceContent
        /// A block quote's words: secondary ink.
        case quoteText
    }

    struct Span: Equatable {
        var range: NSRange
        var role: Role
    }

    /// The spans over `text`, ranges relative to `text`. A block-quote line that starts before
    /// `quoteFloor` is left alone (the Mac's leading audiobook quote has its own look).
    static func spans(in text: String, quoteFloor: Int = 0) -> [Span] {
        var out: [Span] = []
        for h in BodyMarkdown.headings(in: text) {
            out.append(Span(range: h.text, role: .heading(h.level)))
            out.append(Span(range: h.marks, role: .mark))
        }
        for s in BodyFormat.inlineMarks(in: text) {
            out.append(Span(range: s.content, role: .inline(s.mark)))
            out.append(Span(range: s.open, role: .mark))
            out.append(Span(range: s.close, role: .mark))
        }
        for f in BodyFormat.fences(in: text) {
            out.append(Span(range: f.content, role: .fenceContent))
            out.append(Span(range: f.open, role: .mark))
            out.append(Span(range: f.close, role: .mark))
        }
        let ns = text as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { line, r, _, _ in
            guard let line, line.hasPrefix("> "), r.location >= quoteFloor else { return }
            out.append(Span(range: NSRange(location: r.location, length: 2), role: .mark))
            out.append(Span(range: NSRange(location: r.location + 2, length: r.length - 2), role: .quoteText))
        }
        return out
    }
}
