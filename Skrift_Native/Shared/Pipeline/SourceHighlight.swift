import Foundation

/// Q404 (D207, the Q6 + Q351 mocks' "Highlight"): a highlight is a stored range on a Library
/// source with no note: the words, and where they are (`word` = words of the source text before
/// it; `page` for a PDF). It rides inside the Library item's synced blob. SHARED so the Mac reads
/// the same shape when it shows sources.
struct SourceHighlight: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var text: String
    /// 1-based PDF page; nil for an article.
    var page: Int?
    /// Words of the source text before the highlight (the occurrence to paint when the words repeat).
    var word: Int
    var createdAt: Date
    /// Q463 (D212, D214): his comment on this highlight, typed or the transcript of a spoken one.
    /// It becomes the PDF annotation's contents when he shares the PDF with his highlights.
    /// Additive and optional, so an older build decodes the record unchanged.
    var comment: String? = nil
    /// Q463 (D214): the spoken comment's audio, a file name inside the Library item's folder
    /// (`comments/`). Kept on this device; the transcript in `comment` is what syncs and what the PDF carries.
    var commentAudio: String? = nil
    /// When the comment was last written (the comment sheet's "edited …" line).
    var commentedAt: Date? = nil

    init(id: UUID = UUID(), text: String, page: Int?, word: Int, createdAt: Date = Date(),
         comment: String? = nil, commentAudio: String? = nil, commentedAt: Date? = nil) {
        self.id = id
        self.text = text
        self.page = page
        self.word = word
        self.createdAt = createdAt
        self.comment = comment
        self.commentAudio = commentAudio
        self.commentedAt = commentedAt
    }

    /// The comment, trimmed; nil when there is none or it is blank.
    var commentText: String? {
        guard let c = comment?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty else { return nil }
        return c
    }

    var hasComment: Bool { commentText != nil || commentAudio != nil }
}

/// The list rules: add (trimmed, one space, no blanks, no duplicate range), remove, and find the
/// range to paint in a text.
enum SourceHighlights {
    static func normalized(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func adding(_ text: String, page: Int?, word: Int, to list: [SourceHighlight],
                       id: UUID = UUID(), now: Date = Date()) -> [SourceHighlight] {
        let t = normalized(text)
        guard !t.isEmpty else { return list }
        if list.contains(where: { $0.text == t && $0.page == page && $0.word == word }) { return list }
        return list + [SourceHighlight(id: id, text: t, page: page, word: max(0, word), createdAt: now)]
    }

    static func removing(_ id: UUID, from list: [SourceHighlight]) -> [SourceHighlight] {
        list.filter { $0.id != id }
    }

    /// Q463: set (or, with a blank text and no audio, clear) the comment on one highlight.
    static func commenting(_ id: UUID, comment: String?, audio: String?, in list: [SourceHighlight],
                           now: Date = Date()) -> [SourceHighlight] {
        list.map { h in
            guard h.id == id else { return h }
            var out = h
            let text = comment?.trimmingCharacters(in: .whitespacesAndNewlines)
            let blank = (text ?? "").isEmpty
            out.comment = blank ? nil : text
            out.commentAudio = audio
            out.commentedAt = (blank && audio == nil) ? nil : now
            return out
        }
    }

    /// The occurrence of `needle` in `haystack` (inside `within`, if given) whose word index is
    /// nearest `word`. `wordStarts` = UTF-16 offset of each word of the source text in `haystack`.
    static func range(of needle: String, near word: Int, in haystack: String, wordStarts: [Int],
                      within: NSRange? = nil) -> NSRange? {
        let ns = haystack as NSString
        guard !needle.isEmpty else { return nil }
        var search = within ?? NSRange(location: 0, length: ns.length)
        var best: (range: NSRange, distance: Int)?
        while search.length > 0 {
            let r = ns.range(of: needle, options: [], range: search)
            guard r.location != NSNotFound else { break }
            let d = abs(wordIndex(atCharacter: r.location, wordStarts: wordStarts) - word)
            if best == nil || d < best!.distance { best = (r, d) }
            let next = r.location + max(1, r.length)
            search = NSRange(location: next, length: search.location + search.length - next)
        }
        return best?.range
    }

    /// Index of the word holding UTF-16 offset `c` (the last word starting at or before it).
    static func wordIndex(atCharacter c: Int, wordStarts: [Int]) -> Int {
        var lo = 0, hi = wordStarts.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if wordStarts[mid] <= c { lo = mid + 1 } else { hi = mid }
        }
        return max(0, lo - 1)
    }
}
