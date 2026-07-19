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

    /// Batch form of `displayRange(forRaw:in:)`: ONE `pieces` pass shared by all
    /// ranges — the per-span form re-ran the full regex scan per call (S+1 whole-
    /// document passes for S name spans). Result order mirrors the input; nil
    /// entries mean exactly what the single-range form's nil means.
    static func displayRanges(forRaw raws: [NSRange], in text: String) -> [NSRange?] {
        guard !raws.isEmpty else { return [] }
        var cumulative: [(end: Int, delta: Int, start: Int)] = []
        var delta = 0
        for piece in pieces(of: text) {
            if case .text = piece.segment { continue }
            let r = piece.rawRange
            delta += r.length - displayLength(of: piece, in: text)
            cumulative.append((end: r.location + r.length, delta: delta, start: r.location))
        }
        return raws.map { raw in
            var applied = 0
            for entry in cumulative {
                if entry.end <= raw.location { applied = entry.delta }
                else if entry.start < raw.location + raw.length { return nil }
                else { break }
            }
            let loc = raw.location - applied
            return loc >= 0 ? NSRange(location: loc, length: raw.length) : nil
        }
    }

    /// True when the raw text contains task syntax not yet materialized as
    /// attachments (i.e. typed since the last render).
    static func containsTaskSyntax(_ raw: String) -> Bool {
        pieces(of: raw).contains { if case .task = $0.segment { return true }; return false }
    }

    // MARK: - Image-at-sentence-end snap (photo reflow)

    /// Result of `snapImages`: the snapped DISPLAY/EXPORT string plus a forward
    /// map from a location in the ORIGINAL raw to the matching location in `text`.
    /// Snapping only RELOCATES image markers (and normalizes the whitespace that
    /// wrapped them) — every other character keeps its order — so any location
    /// that isn't inside a marker maps cleanly (a name span never overlaps one).
    struct SnapResult: Equatable {
        let text: String
        fileprivate let segments: [Segment]

        fileprivate enum Segment: Equatable {
            case copy(rawLocation: Int, length: Int)   // text += raw[rawLocation ..< +length]
            case insert(length: Int)                    // literal chars not present in raw
        }

        /// Map a raw UTF-16 location → the location in `text`. A raw location that
        /// was dropped (marker / trimmed wrapping whitespace) lands on the seam.
        func snapped(rawLocation loc: Int) -> Int {
            var base = 0
            for seg in segments {
                switch seg {
                case .copy(let cLoc, let len):
                    if loc < cLoc { return base }               // dropped gap before this copy
                    if loc < cLoc + len { return base + (loc - cLoc) }
                    base += len
                case .insert(let len):
                    base += len
                }
            }
            return base
        }

        /// Map a raw RANGE → snapped range (start & end mapped independently; safe
        /// because name/suggested spans never straddle a relocated marker).
        func snapped(rawRange r: NSRange) -> NSRange {
            let s = snapped(rawLocation: r.location)
            let e = snapped(rawLocation: r.location + r.length)
            return NSRange(location: s, length: max(0, e - s))
        }

        static let empty = SnapResult(text: "", segments: [])
    }

    /// Sentence terminators the photo snap breaks on (`. ! ? …` and a newline).
    private static func isSentenceTerminator(_ c: unichar) -> Bool {
        c == 46 || c == 33 || c == 63 || c == 0x2026 || c == 10   // . ! ? … \n
    }

    /// A raw image marker literal, zero-padded to match the injector (`%03d`).
    private static func imgMarker(_ n: Int) -> String { "[[img_\(String(format: "%03d", n))]]" }

    /// Move every MID-SENTENCE `[[img_NNN]]` photo marker to the end of the
    /// sentence it interrupts, rendered as its own `\n\n[[img_NNN]]\n\n` block, so
    /// the sentence reads whole and the photo drops beneath it. Markers already at
    /// a sentence/paragraph boundary are normalized to the same block in place.
    /// Idempotent. SHARED by BOTH renderers AND the Obsidian export, so the display
    /// and the exported markdown agree; the stored RAW transcript is untouched by
    /// display (only a user EDIT rewrites it, and edited notes are trusted, never
    /// re-injected — the photo's recorded moment lives in `imageManifest.offsetSeconds`).
    static func snapImages(_ raw: String) -> SnapResult {
        guard raw.contains("[[img_") else {
            let ns = raw as NSString
            return SnapResult(text: raw,
                              segments: ns.length == 0 ? [] : [.copy(rawLocation: 0, length: ns.length)])
        }
        let ns = raw as NSString
        let out = NSMutableString()
        var segs: [SnapResult.Segment] = []
        var deferred: [Int] = []            // markers awaiting flush at the sentence end
        var suppressLeadingNewlines = false // just closed a block → eat the next text's leading \n
        var tailStarted = false             // have we begun copying the current deferred sentence tail?
        var justPlacedBlock = false         // the last thing emitted was a photo block → next photo is also at a boundary

        func appendCopy(_ location: Int, _ length: Int) {
            guard length > 0 else { return }
            out.append(ns.substring(with: NSRange(location: location, length: length)))
            if case .copy(let l, let n)? = segs.last, l + n == location {
                segs[segs.count - 1] = .copy(rawLocation: l, length: n + length)
            } else {
                segs.append(.copy(rawLocation: location, length: length))
            }
        }
        func appendInsert(_ s: String) {
            let count = (s as NSString).length
            guard count > 0 else { return }
            out.append(s)
            if case .insert(let n)? = segs.last {
                segs[segs.count - 1] = .insert(length: n + count)
            } else {
                segs.append(.insert(length: count))
            }
        }
        func trimTrailingWhitespace() {
            while out.length > 0, isWhitespace(out.character(at: out.length - 1)) {
                out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1))
                switch segs.last {
                case .copy(let l, let n)?:
                    if n <= 1 { segs.removeLast() } else { segs[segs.count - 1] = .copy(rawLocation: l, length: n - 1) }
                case .insert(let n)?:
                    if n <= 1 { segs.removeLast() } else { segs[segs.count - 1] = .insert(length: n - 1) }
                case nil:
                    return
                }
            }
        }
        /// Last non-whitespace char currently in `out`, or nil when the output is
        /// still empty/blank (→ a boundary).
        func trimmedLastChar() -> unichar? {
            var i = out.length - 1
            while i >= 0 {
                let c = out.character(at: i)
                if isWhitespace(c) { i -= 1; continue }
                return c
            }
            return nil
        }
        /// Guard an edge input (marker between two words with no separating space,
        /// e.g. Gemma-reflowed) from healing into one word: keep a single space at
        /// the seam. The injector always leaves the following space, so this is belt-only.
        func guardSeamSpace(nextChar: unichar) {
            guard !tailStarted, out.length > 0,
                  isWordChar(out.character(at: out.length - 1)), isWordChar(nextChar)
            else { return }
            appendInsert(" ")
        }
        func flushDeferred() {
            guard !deferred.isEmpty else { return }
            trimTrailingWhitespace()
            appendInsert("\n\n" + deferred.map(imgMarker).joined(separator: "\n\n") + "\n\n")
            deferred.removeAll()
            suppressLeadingNewlines = true
            tailStarted = false
            justPlacedBlock = true
        }

        for piece in pieces(of: raw) {
            switch piece.segment {
            case .text:
                let r = piece.rawRange
                var start = r.location
                let end = r.location + r.length
                if deferred.isEmpty && suppressLeadingNewlines {
                    while start < end, ns.character(at: start) == 10 { start += 1 }
                }
                suppressLeadingNewlines = false
                if deferred.isEmpty {
                    let copied = end - start
                    appendCopy(start, copied)
                    if copied > 0 { justPlacedBlock = false }
                    break
                }
                // Collecting a sentence tail: strip the marker's leading wrapping
                // newlines, then copy up to & including the first terminator, flush
                // the deferred photo block(s), and continue with the remainder.
                while start < end, ns.character(at: start) == 10 { start += 1 }
                guard start < end else { break }        // wrapping-only piece; keep collecting
                guardSeamSpace(nextChar: ns.character(at: start))
                tailStarted = true
                var term = -1
                var i = start
                while i < end { if isSentenceTerminator(ns.character(at: i)) { term = i; break }; i += 1 }
                if term == -1 {
                    appendCopy(start, end - start)          // tail not closed yet
                } else {
                    appendCopy(start, term + 1 - start)
                    flushDeferred()
                    suppressLeadingNewlines = false          // remainder is a fresh paragraph, copy verbatim
                    let rest = end - (term + 1)
                    appendCopy(term + 1, rest)
                    if rest > 0 { justPlacedBlock = false }
                }
            case .image(let n):
                suppressLeadingNewlines = false
                if deferred.isEmpty, justPlacedBlock || isBoundaryChar(trimmedLastChar()) {
                    // Already at a boundary (or right after another photo) → block in place.
                    trimTrailingWhitespace()
                    appendInsert((out.length == 0 ? "" : "\n\n") + imgMarker(n) + "\n\n")
                    suppressLeadingNewlines = true
                    justPlacedBlock = true
                } else {
                    // Mid-sentence → heal the marker's leading wrapping and defer.
                    trimTrailingWhitespace()
                    deferred.append(n)
                }
            case .task, .memoLink:
                suppressLeadingNewlines = false
                appendCopy(piece.rawRange.location, piece.rawRange.length)   // opaque token
            }
        }
        flushDeferred()   // marker(s) in the final sentence with no terminator
        // A trailing block leaves "…\n\n"; keep it — it matches an in-place block.
        return SnapResult(text: out as String, segments: segs)
    }

    private static func isWhitespace(_ c: unichar) -> Bool { c == 32 || c == 9 || c == 10 }

    private static func isWordChar(_ c: unichar) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c >= 128
    }

    /// `nil` (nothing before) OR a sentence terminator counts as a boundary.
    private static func isBoundaryChar(_ c: unichar?) -> Bool {
        guard let c else { return true }
        return c == 46 || c == 33 || c == 63 || c == 0x2026   // . ! ? …  (\n handled by output state)
    }

    /// The snapped string alone (the Obsidian export path — no offset map needed).
    static func snappedImageBody(_ raw: String) -> String { snapImages(raw).text }
}
