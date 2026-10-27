import Foundation

/// Q530: carry ONLY what the user typed in a name-linked body back into the RAW transcript.
///
/// The linked body is `CompilerInput.linkBody(raw)`: the raw words with some runs replaced (the
/// first mention of a person becomes `[[Canonical]]`, later mentions become the short name). A
/// whole-body `Sanitiser.unlinkToSpoken` turns every link into the person's SHORT name, so a name
/// he said as an alias ("Nik" for Nick Jansen) was rewritten to "Nick" on the first unrelated edit.
/// Instead: `LinkTrail` records which raw range each replaced run stood for WHILE the linker builds
/// the body, the user's change is found by diffing the linked body the linker made against the one
/// he edited, and only that region is spliced into the raw text. Every untouched word keeps its
/// bytes. A change that lands inside a replaced run takes the whole run with it, and only that run
/// is un-linked.
///
/// Shared so the phone (Q529) reads the same mapping.

/// What the linker did to the raw text, kept as a tiling of the linked body: each segment is either
/// unchanged raw text (`same`) or a replaced run that stands for a raw range. Offsets are UTF-16
/// (NSString), like the linker's.
final class LinkTrail {
    struct Seg {
        var out: Int        // UTF-16 length in the linked body
        var raw: NSRange    // the raw range this segment stands for
        var same: Bool      // true: `out == raw.length` and the text is identical
    }

    private(set) var segs: [Seg]
    let rawLength: Int
    /// False once a linker path ran that does not report its replacements (the conversation
    /// linker): the mapping would be a guess, so callers fall back to un-linking the whole body.
    private(set) var exact = true

    init(rawLength: Int) {
        self.rawLength = rawLength
        segs = rawLength > 0 ? [Seg(out: rawLength, raw: NSRange(location: 0, length: rawLength), same: true)] : []
    }

    func invalidate() { exact = false }

    /// The linker replaced `range` (in the CURRENT linked text) with text of `newLength`.
    func replace(_ range: NSRange, newLength: Int) {
        var lo = range.location
        var hi = range.location + range.length
        // A replaced run cannot be split: a replacement touching one takes all of it.
        var s = 0
        for seg in segs {
            let e = s + seg.out
            if !seg.same, s < hi, e > lo { lo = min(lo, s); hi = max(hi, e) }
            s = e
        }
        var out: [Seg] = []
        var rawLo = Int.max, rawHi = Int.min
        var placed = false
        var pos = 0
        func place() {
            guard !placed else { return }
            placed = true
            let rl = rawLo == Int.max ? rawPosition(atOut: lo) : rawLo
            let rh = rawHi == Int.min ? rl : rawHi
            out.append(Seg(out: (hi - lo) - range.length + newLength,
                           raw: NSRange(location: rl, length: rh - rl), same: false))
        }
        for seg in segs {
            let e = pos + seg.out
            if e <= lo {
                out.append(seg)
            } else if pos >= hi {
                place()
                out.append(seg)
            } else {
                // intersects [lo, hi) (or contains the insertion point strictly inside)
                if pos < lo {          // left remainder (a same segment, by construction)
                    out.append(Seg(out: lo - pos, raw: NSRange(location: seg.raw.location, length: lo - pos), same: true))
                }
                let cutLo = max(pos, lo), cutHi = min(e, hi)
                if seg.same {
                    rawLo = min(rawLo, seg.raw.location + (cutLo - pos))
                    rawHi = max(rawHi, seg.raw.location + (cutHi - pos))
                } else {
                    rawLo = min(rawLo, seg.raw.location)
                    rawHi = max(rawHi, seg.raw.location + seg.raw.length)
                }
                place()
                if e > hi {            // right remainder
                    out.append(Seg(out: e - hi,
                                   raw: NSRange(location: seg.raw.location + (hi - pos), length: e - hi), same: true))
                }
            }
            pos = e
        }
        place()
        segs = out
    }

    /// The raw offset of the linked-body boundary `x`.
    func rawPosition(atOut x: Int) -> Int {
        var s = 0
        for seg in segs {
            let e = s + seg.out
            if x < e || (x == s && seg.out == 0) {
                return seg.same ? seg.raw.location + (x - s) : seg.raw.location
            }
            s = e
        }
        return rawLength
    }

    /// The linked-body range `[lo, hi)` widened to whole replaced runs it cuts into.
    func expand(lo: Int, hi: Int) -> (lo: Int, hi: Int) {
        var lo = lo, hi = hi
        var s = 0
        for seg in segs {
            let e = s + seg.out
            if !seg.same, s < hi, e > lo { lo = min(lo, s); hi = max(hi, e) }
            s = e
        }
        return (lo, hi)
    }

    /// The start of the replaced run that ends exactly at `x`, if there is one.
    func replacedRun(endingAt x: Int) -> Int? {
        var s = 0
        for seg in segs {
            let e = s + seg.out
            if !seg.same, e == x, seg.out > 0 { return s }
            s = e
        }
        return nil
    }

    /// The end of the replaced run that starts exactly at `x`, if there is one.
    func replacedRun(startingAt x: Int) -> Int? {
        var s = 0
        for seg in segs {
            let e = s + seg.out
            if !seg.same, s == x, seg.out > 0 { return e }
            s = e
        }
        return nil
    }

    /// The raw range for a linked-body range that is already run-aligned (`expand`ed).
    func rawRange(lo: Int, hi: Int) -> NSRange {
        let a = rawPosition(atOut: lo)
        var b = a
        var s = 0
        var found = false
        for seg in segs {
            let e = s + seg.out
            if hi > s && hi <= e {
                b = seg.same ? seg.raw.location + (hi - s) : seg.raw.location + seg.raw.length
                found = true
                break
            }
            s = e
        }
        if !found { b = hi <= lo ? a : rawLength }
        return NSRange(location: a, length: max(0, b - a))
    }
}

enum LinkedBodyEdit {
    /// The raw transcript after the user edited the linked body, or nil when `shown` is exactly what
    /// the linker makes of `raw` (nothing was edited, so nothing is written).
    /// A conversation body (the one linker path that does not report its runs) falls back to
    /// un-linking the whole body.
    static func rawTranscript(raw: String, shown: String, source: NoteSourceType, people: [Person],
                              resolutions: NameResolutions) -> String? {
        let trail = LinkTrail(rawLength: Sanitiser.nsLen(raw))
        let derived = CompilerInput.linkBody(raw, source: source, people: people,
                                             resolutions: resolutions, trail: trail)
        guard shown != derived else { return nil }
        guard trail.exact else { return Sanitiser.unlinkToSpoken(shown, people: people) }
        return splice(raw: raw, derived: derived, shown: shown, trail: trail, people: people)
    }

    /// Diff `derived` against `shown`, widen each changed region to the replaced runs it touches,
    /// and replace the matching raw range with the region's new text, un-linked.
    static func splice(raw: String, derived: String, shown: String, trail: LinkTrail,
                       people: [Person]) -> String {
        let a = Array(derived.utf16), b = Array(shown.utf16)
        var p = 0
        while p < a.count, p < b.count, a[p] == b[p] { p += 1 }
        var q = 0
        while q < a.count - p, q < b.count - p, a[a.count - 1 - q] == b[b.count - 1 - q] { q += 1 }
        // Never cut a surrogate pair.
        if p > 0, p < a.count, UTF16.isLeadSurrogate(a[p - 1]) { p -= 1 }
        if q > 0, a.count - q > 0, UTF16.isTrailSurrogate(a[a.count - q]) { q -= 1 }

        // Hunks (old range, new range) in absolute coordinates.
        struct Hunk { var oldLo: Int, oldHi: Int, newLo: Int, newHi: Int }
        var hunks: [Hunk] = []
        let oldMid = Array(a[p..<(a.count - q)]), newMid = Array(b[p..<(b.count - q)])
        if oldMid.count * newMid.count <= 16_000_000, !oldMid.isEmpty, !newMid.isEmpty {
            let diff = newMid.difference(from: oldMid)
            var removed = Set<Int>(), inserted = Set<Int>()
            for change in diff {
                switch change {
                case .remove(let offset, _, _): removed.insert(offset)
                case .insert(let offset, _, _): inserted.insert(offset)
                }
            }
            var i = 0, j = 0
            while i < oldMid.count || j < newMid.count {
                if (i < oldMid.count && removed.contains(i)) || (j < newMid.count && inserted.contains(j)) {
                    let i0 = i, j0 = j
                    while i < oldMid.count, removed.contains(i) { i += 1 }
                    while j < newMid.count, inserted.contains(j) { j += 1 }
                    hunks.append(Hunk(oldLo: p + i0, oldHi: p + i, newLo: p + j0, newHi: p + j))
                } else { i += 1; j += 1 }
            }
        } else {
            hunks = [Hunk(oldLo: p, oldHi: a.count - q, newLo: p, newHi: b.count - q)]
        }
        // Regions: the hunks widened to whole replaced runs, merged while they overlap or touch,
        // so every region holds complete hunks and its edges sit on unchanged text.
        // Letters typed straight onto a replaced word extend that word ("Nick" shown for a spoken
        // "Nik", he types "y" → "Nicky"), so the run joins the change instead of being left behind.
        func isWord(_ u: UInt16) -> Bool {
            guard let sc = Unicode.Scalar(u) else { return false }
            return CharacterSet.alphanumerics.contains(sc)
        }
        var regions = hunks.map { h -> (lo: Int, hi: Int) in
            var lo = h.oldLo, hi = h.oldHi
            if h.newHi > h.newLo {
                if lo > 0, isWord(a[lo - 1]), isWord(b[h.newLo]), let s = trail.replacedRun(endingAt: lo) { lo = s }
                if hi < a.count, isWord(a[hi]), isWord(b[h.newHi - 1]), let e = trail.replacedRun(startingAt: hi) { hi = e }
            }
            return (lo, hi)
        }
        var changed = true
        while changed {
            changed = false
            regions = regions.map { trail.expand(lo: $0.lo, hi: $0.hi) }
            for h in hunks {
                for k in regions.indices {
                    let r = regions[k]
                    let touches = (h.oldLo == h.oldHi) ? (h.oldLo >= r.lo && h.oldLo <= r.hi)
                                                      : (h.oldLo < r.hi && h.oldHi > r.lo)
                    if touches, h.oldLo < r.lo || h.oldHi > r.hi {
                        regions[k] = (min(r.lo, h.oldLo), max(r.hi, h.oldHi)); changed = true
                    }
                }
            }
            regions.sort { $0.lo < $1.lo }
            var merged: [(lo: Int, hi: Int)] = []
            for r in regions {
                if let last = merged.last, last.hi >= r.lo {
                    merged[merged.count - 1].hi = max(last.hi, r.hi)
                    changed = true
                } else { merged.append(r) }
            }
            if merged.count != regions.count { changed = true }
            regions = merged
        }

        // A region's new edges: shift by the hunks before it (a hunk inside it is part of it).
        func shift(_ h: Hunk) -> Int { (h.newHi - h.newLo) - (h.oldHi - h.oldLo) }
        var edits: [(NSRange, String)] = []
        for r in regions {
            let nLo = r.lo + hunks.filter { $0.oldLo < r.lo }.reduce(0) { $0 + shift($1) }
            let nHi = r.hi + hunks.filter { $0.oldHi <= r.hi }.reduce(0) { $0 + shift($1) }
            guard nLo >= 0, nHi >= nLo, nHi <= b.count else { return Sanitiser.unlinkToSpoken(shown, people: people) }
            let text = String(decoding: b[nLo..<nHi], as: UTF16.self)
            edits.append((trail.rawRange(lo: r.lo, hi: r.hi), Sanitiser.unlinkToSpoken(text, people: people)))
        }
        return Sanitiser.nsReplace(raw, edits: edits)
    }
}
