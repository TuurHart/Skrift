import Foundation

/// The ONE raw⇄display transform for the note body — SHARED: the phone's editor
/// and the Mac's body render the same tokens (photo markers, task prefixes,
/// memo-link chips) from the same raw text, so the two displays can't drift.
/// Scans the raw text for
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
        case memoLink(id: UUID, title: String)  // [[memo:UUID|Title]] → link chip
    }

    struct Piece: Equatable {
        let segment: Segment
        /// The consumed range in the RAW text.
        let rawRange: NSRange
    }

    /// `[[img_NNN]]` and `[[memo:UUID|Title]]` anywhere; `- [ ]` / `- [x]` only
    /// at a line start (optionally indented — the indent stays TEXT so it
    /// round-trips) and only when followed by a space or line end — matching
    /// what Obsidian treats as a task.
    private static let regex = try! NSRegularExpression(pattern:
        #"\[\[img_(?<img>\d+)\]\]"# +
        #"|\[\[memo:(?<mid>[0-9A-Fa-f\-]{36})\|(?<mtitle>[^\]\n|]*)\]\]"# +
        #"|(?m)^(?<ind>[ \t]*)(?<task>- \[(?<mark> |x|X)\])(?=\s|$)"#)

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
            let img = m.range(withName: "img")
            let mid = m.range(withName: "mid")
            if img.location != NSNotFound {
                text(upTo: m.range.location)
                out.append(Piece(segment: .image(Int(ns.substring(with: img)) ?? 0), rawRange: m.range))
                last = m.range.location + m.range.length
            } else if mid.location != NSNotFound {
                guard let id = UUID(uuidString: ns.substring(with: mid)) else { continue }
                text(upTo: m.range.location)
                out.append(Piece(segment: .memoLink(id: id, title: ns.substring(with: m.range(withName: "mtitle"))),
                                 rawRange: m.range))
                last = m.range.location + m.range.length
            } else {
                let token = m.range(withName: "task")          // "- [ ]" without the indent
                text(upTo: token.location)
                let mark = ns.substring(with: m.range(withName: "mark")).lowercased()
                out.append(Piece(segment: .task(checked: mark == "x"), rawRange: token))
                last = token.location + token.length
            }
        }
        text(upTo: ns.length)
        return out
    }

    /// The raw syntax an attachment reconstructs to.
    static func rawTask(checked: Bool) -> String { checked ? "- [x]" : "- [ ]" }

    /// Display-only paragraph breaks around an IMAGE piece — photos render as
    /// their own BLOCK (signed off 2026-07-07, `mocks/accessory-bar-v2.html`
    /// §#11): a break before when the marker doesn't already start a line, a
    /// break after when raw text continues on the same line. The breaks exist
    /// ONLY in the display text (tagged; `reconstruct` skips them) and this is
    /// the single rule both the attributed builder and `displayRange` use, so
    /// they can't drift.
    static func imageBreaks(for piece: Piece, in raw: String) -> (leading: Bool, trailing: Bool) {
        guard case .image = piece.segment else { return (false, false) }
        let ns = raw as NSString
        let r = piece.rawRange
        let leading = r.location > 0 && ns.character(at: r.location - 1) != 10
        let end = r.location + r.length
        let trailing = end < ns.length && ns.character(at: end) != 10
        return (leading, trailing)
    }

    /// Display length of a piece's glyph(s): 1 for every attachment, plus an
    /// image's display-only breaks.
    private static func displayLength(of piece: Piece, in raw: String) -> Int {
        if case .text = piece.segment { return piece.rawRange.length }
        let breaks = imageBreaks(for: piece, in: raw)
        return 1 + (breaks.leading ? 1 : 0) + (breaks.trailing ? 1 : 0)
    }

    /// Map a RAW range to the DISPLAYED range: every non-text piece before it
    /// collapses to one glyph (images additionally gain their display-only
    /// block breaks). nil when the range straddles a piece (name spans never
    /// do).
    static func displayRange(forRaw raw: NSRange, in text: String) -> NSRange? {
        var delta = 0
        for piece in pieces(of: text) {
            if case .text = piece.segment { continue }
            let r = piece.rawRange
            // A task prefix keeps its leading indent in rawRange? No — rawRange
            // includes the indent for tasks; the glyph replaces the WHOLE match.
            if r.location + r.length <= raw.location {
                delta += r.length - displayLength(of: piece, in: text)
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
