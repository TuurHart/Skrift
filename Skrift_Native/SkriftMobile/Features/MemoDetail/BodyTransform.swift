import Foundation

/// The ONE raw⇄display transform for the note body: scans the raw text for
/// inline `[[img_NNN]]` photo markers AND `- [ ]` / `- [x]` task prefixes
/// (line-start, Obsidian syntax), so the attributed builder and the raw↔display
/// offset mapping can never drift apart (they were separate implementations
/// before checklists arrived).
///
/// Display shape: each marker/prefix collapses to exactly ONE attachment glyph
/// (U+FFFC); everything else passes through verbatim.
enum BodyTransform {
    enum Segment: Equatable {
        case text(String)
        case image(Int)                 // [[img_NNN]] → photo attachment (1-based)
        case task(checked: Bool)        // "- [ ]" / "- [x]" → checkbox attachment
    }

    struct Piece: Equatable {
        let segment: Segment
        /// The consumed range in the RAW text.
        let rawRange: NSRange
    }

    /// `[[img_NNN]]` anywhere; `- [ ]` / `- [x]` only at a line start (optionally
    /// indented — the indent stays TEXT so it round-trips) and only when followed
    /// by a space or line end — matching what Obsidian treats as a task.
    private static let regex = try! NSRegularExpression(
        pattern: #"\[\[img_(\d+)\]\]|(?m)^([ \t]*)(- \[( |x|X)\])(?=\s|$)"#)

    static func pieces(of raw: String) -> [Piece] {
        let ns = raw as NSString
        var out: [Piece] = []
        var last = 0
        func text(upTo end: Int) {
            guard end > last else { return }
            let r = NSRange(location: last, length: end - last)
            out.append(Piece(segment: .text(ns.substring(with: r)), rawRange: r))
        }
        for m in regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            if m.range(at: 1).location != NSNotFound {
                text(upTo: m.range.location)
                let n = Int(ns.substring(with: m.range(at: 1))) ?? 0
                out.append(Piece(segment: .image(n), rawRange: m.range))
                last = m.range.location + m.range.length
            } else {
                let token = m.range(at: 3)                     // "- [ ]" without the indent
                text(upTo: token.location)
                let mark = ns.substring(with: m.range(at: 4)).lowercased()
                out.append(Piece(segment: .task(checked: mark == "x"), rawRange: token))
                last = token.location + token.length
            }
        }
        text(upTo: ns.length)
        return out
    }

    /// The raw syntax an attachment reconstructs to.
    static func rawTask(checked: Bool) -> String { checked ? "- [x]" : "- [ ]" }

    /// Map a RAW range to the DISPLAYED range: every non-text piece before it
    /// collapses to one glyph. nil when the range straddles a piece (name spans
    /// never do).
    static func displayRange(forRaw raw: NSRange, in text: String) -> NSRange? {
        var delta = 0
        for piece in pieces(of: text) {
            if case .text = piece.segment { continue }
            let r = piece.rawRange
            // A task prefix keeps its leading indent in rawRange? No — rawRange
            // includes the indent for tasks; the glyph replaces the WHOLE match.
            if r.location + r.length <= raw.location {
                delta += r.length - 1
            } else if r.location < raw.location + raw.length {
                return nil
            } else {
                break
            }
        }
        let loc = raw.location - delta
        return loc >= 0 ? NSRange(location: loc, length: raw.length) : nil
    }

    /// True when the raw text contains task syntax not yet materialized as
    /// attachments (i.e. typed since the last render).
    static func containsTaskSyntax(_ raw: String) -> Bool {
        pieces(of: raw).contains { if case .task = $0.segment { return true }; return false }
    }
}
