import Foundation

/// PRESENTATION-ONLY split of a note body into its leading `> ` blockquote and whatever
/// follows. SHARED — the Mac, the phone and the iPad must draw a quote the same way, and
/// until 2026-07-27 they each owned a copy of this rule (the phone's `CaptureQuote`, the
/// Mac's `BookCapture.quoteLineRanges` over `QuoteProtection.splitLeadingQuote`).
///
/// The stored body keeps its raw `> ` lines — this type carries the exact leading substring
/// (`rawBlock`) so an editor can re-prepend it verbatim and an edit can never corrupt the
/// quote. Round trip: for the shape the capture flow writes (quote block, blank line, ramble)
/// `split(t)!.body(withRamble: split(t)!.ramble) == t` byte for byte. A degenerate input
/// missing the blank separator keeps the quote and ramble bytes intact but normalises the
/// separator to one blank line.
///
/// NOT gated on book metadata. It used to be, on both apps — "a bare blockquote in an
/// ordinary memo stays plain text" — and that was wrong for a reason no design argument would
/// have found: the metadata is a SYNCED blob that can be missing. A June-2026 audiobook
/// capture reached the Mac with an empty metadata blob, so the Mac showed the reader a raw
/// `> ` wall while the phone, which still held the metadata locally, drew it properly. A
/// quote should look like a quote from the text alone; only the ATTRIBUTION caption needs the
/// metadata, and it simply doesn't appear without it.
struct CaptureQuote: Equatable, Sendable {
    /// The quote with the `> ` markers stripped, for styled display. Bare `>` spacer lines
    /// inside the block become empty lines (paragraph breaks).
    let displayText: String
    /// The exact leading substring of the body covering the quote block, including any
    /// leading blanks and the blank separator line(s) after it.
    let rawBlock: String
    /// The exact remainder below the quote block (empty = no ramble yet).
    let ramble: String

    /// Spoken words in the quote (`>` markers are not words). The word-timings sidecar holds
    /// the quote's spoken words first, then the appended ramble's — so this is the ramble's
    /// base index into the global karaoke timings.
    var spokenWordCount: Int {
        displayText.split(whereSeparator: \.isWhitespace).count
    }

    /// Char ranges (NSString/UTF-16 coords) of the quote's lines within the ORIGINAL body —
    /// what an attributed-text renderer needs to style them in place. Each range covers the
    /// whole line INCLUDING its `> ` marker; `markerLength(ofLine:)` says how much of it is
    /// syntax.
    static func lineRanges(in body: String) -> [NSRange] {
        guard let split = split(body) else { return [] }
        let ns = body as NSString
        var ranges: [NSRange] = []
        var loc = 0
        for line in split.rawBlock.components(separatedBy: "\n") {
            let len = (line as NSString).length
            // Trailing blank separator lines belong to rawBlock but aren't quote lines.
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                ranges.append(NSRange(location: loc, length: len))
            }
            loc += len + 1   // + the "\n" the split dropped
        }
        return ranges.filter { NSMaxRange($0) <= ns.length }
    }

    /// How many leading characters of a quote line are the `>` marker plus the space after
    /// it — the run a renderer hides so the reader sees prose, not syntax. Counts any
    /// leading whitespace before the `>` too. 0 when the line isn't a quote line.
    static func markerLength(ofLine line: String) -> Int {
        let ns = line as NSString
        var i = 0
        while i < ns.length, ns.character(at: i) == 32 || ns.character(at: i) == 9 { i += 1 }
        guard i < ns.length, ns.character(at: i) == 62 else { return 0 }   // ">"
        i += 1
        while i < ns.length, ns.character(at: i) == 32 || ns.character(at: i) == 9 { i += 1 }
        return i
    }

    /// Parse the body's leading blockquote. Tolerates blank lines above the quote and
    /// bare/padded `>` markers; nil when the body doesn't open with a non-empty `> ` block.
    static func split(_ body: String?) -> CaptureQuote? {
        guard let body, !body.isEmpty else { return nil }
        let lines = body.components(separatedBy: "\n")
        var i = 0
        while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1 }
        var quoteLines: [String] = []
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(">") else { break }
            quoteLines.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
            i += 1
        }
        guard quoteLines.contains(where: { !$0.isEmpty }) else { return nil }
        // The blank separator after the quote belongs to the raw block, so the ramble starts
        // at its first real line.
        while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1 }
        while quoteLines.first?.isEmpty == true { quoteLines.removeFirst() }
        while quoteLines.last?.isEmpty == true { quoteLines.removeLast() }
        return CaptureQuote(
            displayText: quoteLines.joined(separator: "\n"),
            rawBlock: lines[0..<i].joined(separator: "\n"),
            ramble: lines[i...].joined(separator: "\n")
        )
    }

    /// Reassemble the stored body from an edited ramble: the raw quote block verbatim + a
    /// blank-line separator (kept byte-exact when the block already carries one) + the
    /// ramble. An emptied ramble leaves a quote-only capture — never an empty body.
    func body(withRamble newRamble: String) -> String {
        guard !newRamble.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return rawBlock
        }
        let separator = rawBlock.hasSuffix("\n") ? "\n" : "\n\n"
        return rawBlock + separator + newRamble
    }

    /// The plain-text attribution caption — "— Author, Book · ch. N", with the author and
    /// chapter omitted when absent. A purely numeric chapter gets the "ch. " prefix; anything
    /// else (an m4b chapter *name*) shows as-is. nil without a book title, which is what
    /// makes the caption optional while the quote styling is not.
    ///
    /// PLAIN text by design: the real `[[Author]]` wikilink is written at export only
    /// (`Compiler.audiobookBody`), never duplicated into the body.
    static func attribution(book: String?, author: String? = nil, chapter: String? = nil,
                            style: AttributionParts.Style = .plain) -> String? {
        attributionParts(book: book, author: author, chapter: chapter, style: style)?.text
    }

    /// The attribution as its three runs, so a view can set the title in italics without
    /// building a second string (C172: one builder). `style` picks the punctuation: `.plain`
    /// is the in-app caption ("— Author, Book · ch. N"), `.vault` the export line
    /// ("— [[Author]], *Book*, ch. N"). The author guard and the chapter rule are the same
    /// in both: an empty author is dropped (never "— , Book"), a numeric chapter gets
    /// "ch. ", a chapter NAME shows as-is.
    struct AttributionParts: Equatable, Sendable {
        enum Style: Sendable { case plain, vault }
        let lead: String
        let title: String
        let tail: String
        let style: Style

        /// The title as it is written inline (`*Book*` in the vault, bare in-app).
        var renderedTitle: String { style == .vault ? "*\(title)*" : title }
        var text: String { lead + renderedTitle + tail }
    }

    static func attributionParts(book: String?, author: String? = nil, chapter: String? = nil,
                                 style: AttributionParts.Style = .plain) -> AttributionParts? {
        func clean(_ v: String?) -> String? {
            guard let t = v?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
            return t
        }
        guard let title = clean(book) else { return nil }
        var lead = "— "
        if let author = clean(author) {
            lead += (style == .vault ? "[[\(author)]]" : author) + ", "
        }
        var tail = ""
        if let label = chapterLabel(chapter) { tail = (style == .vault ? ", " : " · ") + label }
        return AttributionParts(lead: lead, title: title, tail: tail, style: style)
    }

    /// The quote block alone, exactly as it sits at the top of the body: `rawBlock` minus
    /// the blank separator lines after it. This is what the copy-edit escrow, the
    /// name-linker's protected range and the export italicising operate on (C172 — they all
    /// see the block this splitter found, indent- and blank-line-tolerant).
    var quoteBlock: String {
        var lines = rawBlock.components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// The short list-row caption — "Book · ch. N" (no author, no dash). One chapter rule
    /// with `attribution`. nil without a book title.
    static func caption(book: String?, chapter: String? = nil) -> String? {
        guard let title = book?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { return nil }
        guard let label = chapterLabel(chapter) else { return title }
        return "\(title) · \(label)"
    }

    /// "ch. 4" for a purely numeric chapter, an m4b chapter NAME as-is, nil when blank.
    static func chapterLabel(_ chapter: String?) -> String? {
        guard let c = chapter?.trimmingCharacters(in: .whitespaces), !c.isEmpty else { return nil }
        return c.allSatisfy(\.isNumber) ? "ch. \(c)" : c
    }
}
