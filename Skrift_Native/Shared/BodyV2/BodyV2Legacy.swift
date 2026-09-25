import Foundation

/// Q13 READ-ONLY FALLBACK. Q14 KEPT it: `BodyNormaliseMigration` rewrites an old body at the
/// note's first open (onAppear, after the first render), but the vault exporter, the phone
/// publisher and the snapshot tool read bodies of notes never opened on this device, a v1 body
/// can arrive over CloudKit while its note is on screen, and a refused rewrite stays v1 — all
/// of those still need the reflow. Every write site stores body v2 now, but a body stored
/// before the swap (v1 wrote `sat\n\n[[img_001]]\n\n down.` at the photo's moment; a v1 edit
/// or a copy-edit can leave a marker inline) would render with the photo mid-sentence
/// without this fallback. Such a body is still shown and exported through it, exactly
/// as before v1 was deleted (Q15, `v1-body` tag); a v2-shaped body passes through untouched, so
/// its only offset remap is marker → one glyph (C17). Nothing here writes.
enum BodyV2Legacy {

    /// True when some picture marker is not its own paragraph in v2's shape: at the top or
    /// after a blank line, markers `\n\n`-separated, then a blank line straight into the next
    /// paragraph (v1's wrap leaves a space there) or the end.
    static func isUnnormalised(_ body: String) -> Bool {
        BodyNormaliseMigration.needsNormalise(body)
    }

    /// The text to show / export for a stored body, and the map from a stored (raw) range
    /// to a range in that text. Identity for a v2-shaped body.
    static func shown(_ body: String) -> (text: String, map: (NSRange) -> NSRange) {
        guard isUnnormalised(body) else { return (body, { $0 }) }
        let reflow = Self.reflowMidSentencePictures(body)
        return (reflow.text, { reflow.mapped(rawRange: $0) })
    }

    // MARK: - the v1 photo-reflow, kept ONLY for this read-only fallback (Q15)

    /// Result of `reflowMidSentencePictures`: the reflowed DISPLAY/EXPORT string plus a
    /// forward map from a location in the ORIGINAL raw to the matching location in `text`.
    /// Reflowing only RELOCATES image markers (and normalizes the whitespace that wrapped
    /// them) — every other character keeps its order — so any location that isn't inside a
    /// marker maps cleanly (a name span never overlaps one).
    private struct Reflow {
        let text: String
        let segments: [Segment]

        enum Segment {
            case copy(rawLocation: Int, length: Int)   // text += raw[rawLocation ..< +length]
            case insert(length: Int)                    // literal chars not present in raw
        }

        /// Map a raw UTF-16 location → the location in `text`. A raw location that
        /// was dropped (marker / trimmed wrapping whitespace) lands on the seam.
        func mapped(rawLocation loc: Int) -> Int {
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

        /// Map a raw RANGE → reflowed range (start & end mapped independently; safe
        /// because name/suggested spans never straddle a relocated marker).
        func mapped(rawRange r: NSRange) -> NSRange {
            let s = mapped(rawLocation: r.location)
            let e = mapped(rawLocation: r.location + r.length)
            return NSRange(location: s, length: max(0, e - s))
        }
    }

    private static func isReflowWhitespace(_ c: unichar) -> Bool { c == 32 || c == 9 || c == 10 }

    private static func isReflowWordChar(_ c: unichar) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c >= 128
    }

    /// `nil` (nothing before) OR a sentence terminator counts as a boundary.
    private static func isReflowBoundaryChar(_ c: unichar?) -> Bool {
        guard let c else { return true }
        return c == 46 || c == 33 || c == 63 || c == 0x2026   // . ! ? …  (\n handled by output state)
    }

    /// Sentence terminators the reflow breaks on (`. ! ? …` and a newline).
    private static func isReflowSentenceTerminator(_ c: unichar) -> Bool {
        c == 46 || c == 33 || c == 63 || c == 0x2026 || c == 10   // . ! ? … \n
    }

    /// A raw image marker literal, zero-padded to match the injector (`%03d`).
    private static func reflowMarkerLiteral(_ n: Int) -> String { "[[img_\(String(format: "%03d", n))]]" }

    /// Move every MID-SENTENCE `[[img_NNN]]` photo marker to the end of the sentence it
    /// interrupts, rendered as its own `\n\n[[img_NNN]]\n\n` block, so the sentence reads
    /// whole and the photo drops beneath it. Markers already at a sentence/paragraph
    /// boundary are normalized to the same block in place. Idempotent. v1's own snap,
    /// preserved verbatim here so a pre-v2 body still displays/exports the same way it
    /// always did (Q15 deleted the general-purpose copy in `BodyTransform`).
    private static func reflowMidSentencePictures(_ raw: String) -> Reflow {
        guard raw.contains("[[img_") else {
            let ns = raw as NSString
            return Reflow(text: raw,
                          segments: ns.length == 0 ? [] : [.copy(rawLocation: 0, length: ns.length)])
        }
        let ns = raw as NSString
        let out = NSMutableString()
        var segs: [Reflow.Segment] = []
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
            while out.length > 0, isReflowWhitespace(out.character(at: out.length - 1)) {
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
                if isReflowWhitespace(c) { i -= 1; continue }
                return c
            }
            return nil
        }
        /// Guard an edge input (marker between two words with no separating space,
        /// e.g. Gemma-reflowed) from healing into one word: keep a single space at
        /// the seam. The injector always leaves the following space, so this is belt-only.
        func guardSeamSpace(nextChar: unichar) {
            guard !tailStarted, out.length > 0,
                  isReflowWordChar(out.character(at: out.length - 1)), isReflowWordChar(nextChar)
            else { return }
            appendInsert(" ")
        }
        func flushDeferred() {
            guard !deferred.isEmpty else { return }
            trimTrailingWhitespace()
            appendInsert("\n\n" + deferred.map(reflowMarkerLiteral).joined(separator: "\n\n") + "\n\n")
            deferred.removeAll()
            suppressLeadingNewlines = true
            tailStarted = false
            justPlacedBlock = true
        }

        for piece in BodyTransform.pieces(of: raw) {
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
                while i < end { if isReflowSentenceTerminator(ns.character(at: i)) { term = i; break }; i += 1 }
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
                if deferred.isEmpty, justPlacedBlock || isReflowBoundaryChar(trimmedLastChar()) {
                    // Already at a boundary (or right after another photo) → block in place.
                    trimTrailingWhitespace()
                    appendInsert((out.length == 0 ? "" : "\n\n") + reflowMarkerLiteral(n) + "\n\n")
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
        return Reflow(text: out as String, segments: segs)
    }
}
