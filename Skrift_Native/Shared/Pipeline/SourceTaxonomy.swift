import Foundation

/// The unified source taxonomy — ONE copy of every source kind's glyph + label
/// (CLAUDE.md "Unified source taxonomy"; single-sourced 2026-07-21 after a
/// third hardcoded copy appeared). The Mac's queue rows, its quiet rows, and
/// the phone's row/chip glyphs all read THESE — a symbol renamed here renames
/// everywhere, and nowhere else.
enum SourceKind: Equatable {
    case audiobookQuote, pdfQuote,
         /// Q355 (D138): a quote highlighted in a Library article (`bookKind` "article").
         articleQuote,
         video, captureURL, captureImage, captureText,
         captureFile, captureOther, appleNote, voiceMemo, typedNote,
         /// Q372 (D138): a note that LINKS to a Library source with no captured quote — what
         /// "Send to a note" and "Move to Library" leave. One case per source kind.
         audiobookLink, episodeLink, pdfLink, articleLink

    /// True for the four source-link kinds.
    var isSourceLink: Bool {
        switch self {
        case .audiobookLink, .episodeLink, .pdfLink, .articleLink: return true
        default: return false
        }
    }

    /// The `source:` frontmatter value of a source-link note, naming the source kind (D138).
    var linkExportSource: String? {
        switch self {
        case .audiobookLink: return "Audiobook-link"
        case .episodeLink:   return "Episode-link"
        case .pdfLink:       return "PDF-link"
        case .articleLink:   return "Article-link"
        default:             return nil
        }
    }

    /// SF Symbol.
    var glyph: String {
        switch self {
        case .audiobookQuote: return "book.closed.fill"
        case .pdfQuote:       return "doc.text"
        case .articleQuote:   return "newspaper.fill"
        case .audiobookLink:  return "book.closed"
        case .episodeLink:    return "antenna.radiowaves.left.and.right"
        case .pdfLink:        return "doc"
        case .articleLink:    return "newspaper"
        case .video:          return "video.fill"
        case .captureURL:     return "link"
        case .captureImage:   return "photo"
        case .captureText:    return "text.quote"
        case .captureFile:    return "doc"
        case .captureOther:   return "square.and.arrow.down"
        case .appleNote:      return "note.text"
        case .voiceMemo:      return "mic.fill"
        case .typedNote:      return "square.and.pencil"
        }
    }

    /// Human label (detail "source" lines, chips).
    var label: String {
        switch self {
        case .audiobookQuote: return "Audiobook quote"
        case .pdfQuote:       return "PDF quote"
        case .articleQuote:   return "Article quote"
        case .audiobookLink:  return "Audiobook link"
        case .episodeLink:    return "Episode link"
        case .pdfLink:        return "PDF link"
        case .articleLink:    return "Article link"
        case .video:          return "Video"
        case .captureURL:     return "Link"
        case .captureImage:   return "Image"
        case .captureText:    return "Text"
        case .captureFile:    return "File"
        case .captureOther:   return "Capture"
        case .appleNote:      return "Apple Note"
        case .voiceMemo:      return "Voice memo"
        case .typedNote:      return "Note"
        }
    }

    /// Q386: what a book-backed note shows itself as (header chip, line-3 marker): a source
    /// link or a PDF / article quote as itself, anything else carrying book metadata as an
    /// audiobook quote. The one rule the phone chip, the Mac source line and the card marker share.
    var bookKind: SourceKind {
        switch self {
        case .pdfQuote, .articleQuote, .audiobookLink, .episodeLink, .pdfLink, .articleLink: return self
        default: return .audiobookQuote
        }
    }

    /// Q386: the source itself as one word ("Audiobook", "Episode", "PDF", "Article"), for the
    /// Library link card and the hatch copy. nil for kinds that are not a Library source.
    var sourceName: String? {
        switch self {
        case .audiobookQuote, .audiobookLink: return "Audiobook"
        case .episodeLink:                    return "Episode"
        case .pdfQuote, .pdfLink:             return "PDF"
        case .articleQuote, .articleLink:     return "Article"
        default:                              return nil
        }
    }

    /// Q386: the noun in "N notes from this book" / "The episode's own place is not moved".
    var sourceNoun: String? {
        switch self {
        case .audiobookQuote, .audiobookLink: return "book"
        case .episodeLink:                    return "episode"
        case .pdfQuote, .pdfLink:             return "PDF"
        case .articleQuote, .articleLink:     return "article"
        default:                              return nil
        }
    }

    /// The header chip / source line of a book-backed note: "Audiobook quote · <title>",
    /// "PDF quote · <title>", "PDF link · <title>" (Q187, Q355, Q356, Q372).
    func bookChip(title: String) -> String { "\(bookKind.label) · \(title)" }

    /// The Mac capture strip's line: the kind label, plus the domain when a link has one
    /// ("Link · swiftwithmajid.com"). The strip used to hardcode its own "Shared link", and the
    /// phone chip another: three spellings of one fact. Both now read `label`.
    func stripLabel(domain: String?) -> String {
        guard let domain, !domain.isEmpty else { return label }
        return "\(label) · \(domain)"
    }

    /// Row-title fallback for a note with no title and no words yet. A typed
    /// note says "Note" — "Voice note" on something you wrote reads as a bug
    /// (mocks/mac-new-note.html m3); everything else keeps the historic copy.
    var emptyTitleFallback: String {
        self == .typedNote ? "Note" : "Voice note"
    }

    /// The media marker inside a metadata JSON object. Two spellings exist for one fact:
    /// the phone's `MemoMetadata` encodes `sourceType` (no CodingKeys; `Source.video`),
    /// the Mac author and `Memo.newTyped` write `mediaSource` ("video" / "typed"). Both are
    /// read, `mediaSource` first (C71 glyph key drift).
    static func mediaMarker(in json: [String: Any]?) -> String? {
        guard let json else { return nil }
        for key in ["mediaSource", "sourceType"] {
            if let v = (json[key] as? String)?.trimmingCharacters(in: .whitespaces), !v.isEmpty { return v }
        }
        return nil
    }

    /// THE classifier: every surface (phone row/pane/chips, iPad Journal, the Mac projection
    /// and the Mac's `PipelineFile` rows) reduces its own storage to these facts and calls
    /// this. Priority: audiobook quote, video, typed, capture subtype, audio/no-audio.
    /// - `sharedType`: the capture's `type` string (nil / unknown means not a typed capture)
    /// - `isCaptureRow`: the row is already known to be a capture (Mac `.capture` rows), so
    ///   an unknown subtype reads as `.captureOther` rather than falling through.
    /// - `pdfPage`: the quote's place is a PDF page ("p. 4", `isPDFPageLabel`), Q356 / D138.
    /// - `article`: the quote came from a Library article (`bookKind` "article"), Q355.
    /// - `sourceLink`: the note is a link to a Library source (`sourceLink(...)`, Q372), which
    ///   wins over the quote kinds: it carries the same book metadata but no quote.
    static func classify(hasBook: Bool, pdfPage: Bool = false, article: Bool = false, sourceLink: SourceKind? = nil,
                         media: String?, sharedType: String?,
                         isCaptureRow: Bool = false, hasAudio: Bool) -> SourceKind {
        if let sourceLink, sourceLink.isSourceLink { return sourceLink }
        if hasBook { return article ? .articleQuote : (pdfPage ? .pdfQuote : .audiobookQuote) }
        if media == "video" { return .video }
        // A note born typed (the Mac's pencil/Cmd-N verb, `MacMemoAuthor.typedNote`).
        // Without the marker a no-audio memo reads as an Apple Note import below.
        if media == "typed" { return .typedNote }
        // A Mac picture-only import carries no `sharedContent`; its marker says what it is.
        if media == "image" { return .captureImage }
        switch sharedType {
        case "url":   return .captureURL
        case "image": return .captureImage
        case "text":  return .captureText
        case "file":  return .captureFile
        default:      break
        }
        if isCaptureRow { return .captureOther }
        return hasAudio ? .voiceMemo : .appleNote
    }

    /// Kind of a synced `Memo`. A capture is the phone's bare `Memo.sharedContentData`
    /// (`CaptureInboxDrainer`); a video is `sourceType` OR `mediaSource` in `metadataData`.
    static func of(_ memo: Memo) -> SourceKind {
        of(metadataData: memo.metadataData, sharedContentData: memo.sharedContentData,
           hasAudio: !memo.audioFilename.isEmpty, body: memo.transcript)
    }

    /// The classifier over a memo's raw facts (Q320). Content-keyed cache: the inputs are the
    /// whole answer, so any edit (local or CloudKit merge) is a new key and nothing goes stale.
    /// Building a list of titles used to JSON-parse two blobs per note per call. Callable off the
    /// main actor (NSCache is thread-safe). `body` (the raw transcript) only matters for a note
    /// linked to a Library source: a leading quote makes it a quote, none makes it a link (Q372).
    /// It enters the key as one Bool, computed only when the metadata carries a `bookID`.
    static func of(metadataData: Data?, sharedContentData: Data?, hasAudio: Bool,
                   body: String? = nil) -> SourceKind {
        let quoted = hasBookIDKey(metadataData) && CaptureQuote.split(body) != nil
        let key = KindKey(metadataData, sharedContentData, hasAudio, quoted)
        if let hit = kindCache.object(forKey: key) { return hit.kind }
        kindMisses.add()
        let meta = metadataData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let shared: SharedContent? = Memo.decodeJSON(sharedContentData)
        let memoMeta = Memo.metadata(from: metadataData)
        let kind = classify(hasBook: memoMeta?.bookTitle.map { !$0.isEmpty } ?? false,
                            pdfPage: isPDFPageLabel(memoMeta?.bookChapter),
                            article: memoMeta?.bookKind?.lowercased() == "article",
                            sourceLink: sourceLink(metadata: meta, quoted: quoted),
                            media: mediaMarker(in: meta),
                            sharedType: shared?.type.rawValue,
                            hasAudio: hasAudio)
        kindCache.setObject(KindBox(kind), forKey: key)
        return kind
    }

    // MARK: - Source links (Q372, D138)

    /// THE source-link rule, used by the phone (`LibraryHatch.isSourceLink`, `of(_:)`), the Mac
    /// row (`PipelineFile.sourceKind`) and both exporters (`CompilerInput.kind`). A note links to
    /// a Library source when its metadata carries the link (`bookID` + a finite, non-negative
    /// `bookPosition`, what `LibraryHatch.linkMetadata` writes) and its body opens with NO
    /// captured quote. The kind comes from `bookKind` ("book" / "episode" / "pdf" / "article");
    /// a link written before that key existed falls back on its place: "p. N" is a PDF, anything
    /// else an audiobook. nil = not a source link.
    static func sourceLink(metadataData: Data?, body: String?) -> SourceKind? {
        guard hasBookIDKey(metadataData) else { return nil }
        let meta = metadataData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        return sourceLink(metadata: meta, quoted: CaptureQuote.split(body) != nil)
    }

    /// The rule over an already-parsed metadata object; `quoted` = the body opens with a quote.
    static func sourceLink(metadata meta: [String: Any]?, quoted: Bool) -> SourceKind? {
        guard !quoted, let meta,
              let id = meta["bookID"] as? String, UUID(uuidString: id) != nil,
              let position = (meta["bookPosition"] as? NSNumber)?.doubleValue,
              position.isFinite, position >= 0 else { return nil }
        switch (meta["bookKind"] as? String)?.lowercased() {
        case "episode": return .episodeLink
        case "pdf":     return .pdfLink
        case "article": return .articleLink
        case "book":    return .audiobookLink
        default:        return isPDFPageLabel(meta["bookChapter"] as? String) ? .pdfLink : .audiobookLink
        }
    }

    /// Cheap pre-check (a byte search, no JSON parse) so an ordinary note never splits its body.
    private static func hasBookIDKey(_ data: Data?) -> Bool {
        guard let data else { return false }
        return data.range(of: bookIDKeyBytes) != nil
    }
    private static let bookIDKeyBytes = Data("\"bookID\"".utf8)

    /// True for a capture place written as a PDF page ("p. 4", the phone's `LibraryPDF.pageLabel`):
    /// the quote came from a PDF, not a book (Q356 / D138). Both apps read it from `bookChapter`.
    static func isPDFPageLabel(_ chapter: String?) -> Bool {
        guard let c = chapter, c.hasPrefix("p. ") else { return false }
        let n = c.dropFirst(3)
        return !n.isEmpty && n.allSatisfy(\.isNumber)
    }

    /// How many times the classifier actually ran (tests read this; harmless in production).
    static var classifyRuns: Int { kindMisses.value }

    private final class KindBox { let kind: SourceKind; init(_ k: SourceKind) { kind = k } }
    private final class KindKey: NSObject {
        let metadata: Data?, shared: Data?, hasAudio: Bool, quoted: Bool
        init(_ m: Data?, _ s: Data?, _ a: Bool, _ q: Bool) { metadata = m; shared = s; hasAudio = a; quoted = q }
        override var hash: Int {
            var h = Hasher()
            h.combine(metadata); h.combine(shared); h.combine(hasAudio); h.combine(quoted)
            return h.finalize()
        }
        override func isEqual(_ object: Any?) -> Bool {
            guard let o = object as? KindKey else { return false }
            return metadata == o.metadata && shared == o.shared && hasAudio == o.hasAudio && quoted == o.quoted
        }
    }
    private static let kindCache: NSCache<KindKey, KindBox> = {
        let c = NSCache<KindKey, KindBox>()
        c.countLimit = 4096
        return c
    }()
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func add() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }
    private static let kindMisses = Counter()
}
