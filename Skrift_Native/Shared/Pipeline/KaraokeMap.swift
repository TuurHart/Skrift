import Foundation

/// Pure word geometry for the editor's karaoke painting: maps the timings-sidecar
/// word index ↔ the character range of that word in the DISPLAYED text (the text
/// view's storage, where each inline photo is one attachment glyph U+FFFC).
///
/// Indexing matches the on-device word timings: a "word" is a whitespace-delimited
/// run; attachment glyphs are not spoken words, so a token that is only attachment
/// characters is skipped, and attachment characters glued to a word (e.g.
/// "word\u{FFFC}") don't split or add words.
enum KaraokeMap {
    static let attachmentChar: unichar = 0xFFFC

    /// Character ranges of the spoken words in display order. `ranges[i]` is the
    /// i-th word of THIS text (callers add the region's sidecar offset — e.g. a
    /// capture ramble starts at `CaptureQuote.spokenWordCount`).
    ///
    /// `countAttachmentOnlyTokens`: the Mac editor splices a speaker-gutter attachment in front of
    /// a turn and it must count as a word (the literal `**Name:**` it stands for was one), so the
    /// Mac passes true; the phone has no such attachment and keeps false.
    static func wordRanges(in text: NSString, countAttachmentOnlyTokens: Bool = false) -> [NSRange] {
        var ranges: [NSRange] = []
        var tokenStart: Int? = nil
        var tokenHasWord = false

        func closeToken(at end: Int) {
            if let start = tokenStart, tokenHasWord || countAttachmentOnlyTokens {
                ranges.append(NSRange(location: start, length: end - start))
            }
            tokenStart = nil
            tokenHasWord = false
        }

        let length = text.length
        var i = 0
        while i < length {
            let c = text.character(at: i)
            // Whitespace/newline ends a token. (unichar-level check is fine here:
            // the transcript is prose; supplementary-plane chars are non-space.)
            if let scalar = Unicode.Scalar(c), CharacterSet.whitespacesAndNewlines.contains(scalar) {
                closeToken(at: i)
            } else {
                if tokenStart == nil { tokenStart = i }
                if c != Self.attachmentChar { tokenHasWord = true }
            }
            i += 1
        }
        closeToken(at: length)
        return ranges
    }

    /// The word whose range contains `charIndex`, or the nearest word before it
    /// (a tap on whitespace seeks to the word just read). nil when before word 0.
    static func wordIndex(at charIndex: Int, in ranges: [NSRange]) -> Int? {
        guard !ranges.isEmpty else { return nil }
        var candidate: Int? = nil
        for (i, r) in ranges.enumerated() {
            if charIndex >= r.location + r.length { candidate = i; continue }
            if charIndex >= r.location { return i }
            break
        }
        return candidate
    }
}
