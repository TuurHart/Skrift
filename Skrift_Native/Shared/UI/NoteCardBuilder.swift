import Foundation

/// THE card-content builder (Q106, C115/C240/C172/C78). Both lists feed the shared
/// `NoteCardView`; until now each app derived the card's TEXT by hand — the phone's
/// `MemoCard.cardModel` did the quote / book chip / capture title / domain chip logic and
/// the Mac's `QueueRowView.cardModel` and quiet-row builder did a thinner copy of it, so a
/// book capture or a video import (both `.audio` rows) read as a flat body on the Mac
/// (parity audit list-sidebar-62..65, 68; capture-source-04/05/13/14; books-103).
///
/// Each app reduces its own storage to `NoteCardFacts` (phone `Memo` and the Mac's unrated
/// `Memo` rows via `Memo.cardFacts`, the Mac's rated `PipelineFile` rows via
/// `PipelineFile.cardFacts`) and calls `NoteCardBuilder.content`. The per-app CHROME (stamp,
/// status pill, balls, fading line, selection, lock placeholder, thumbnail) stays in each
/// adapter; only title / quote / snippet / chips live here.
///
/// Foundation-only on purpose so the host-less Mac test bundle compiles it.

/// What the card needs to know about a note, independent of where it is stored.
struct NoteCardFacts: Equatable {
    /// The one classifier's verdict (`SourceKind.classify`).
    var kind: SourceKind
    /// The note's own title, when one was chosen (`Memo.title` / the Mac row's `enhancedTitle`).
    var title: String?
    /// The Mac's generated title on the phone side (`MemoEnhancement.title`); display-only.
    var generatedTitle: String?
    /// The raw body: the transcript (phone) or `sanitised ?? copyedit ?? transcript` (Mac row).
    var body: String?
    /// A share capture's annotation (`Memo.annotationText`; on the Mac row it is the body).
    var annotation: String?
    /// The shared thing, ONLY when the note is a capture (a no-audio memo with `sharedContent`).
    var shared: SharedContent?
    /// Audiobook capture source: book title + raw chapter (a number or an m4b chapter name).
    var book: Book?
    /// nil = no audio / no duration (never a permanent "0:00" for a note with no recording).
    var durationSeconds: Double?
    var place: String?
    var temperature: Int?
    var tags: [String]

    struct Book: Equatable {
        var title: String
        var chapter: String?
        init(title: String, chapter: String? = nil) {
            self.title = title
            self.chapter = chapter
        }
    }

    init(kind: SourceKind, title: String? = nil, generatedTitle: String? = nil, body: String? = nil,
         annotation: String? = nil, shared: SharedContent? = nil, book: Book? = nil,
         durationSeconds: Double? = nil, place: String? = nil, temperature: Int? = nil,
         tags: [String] = []) {
        self.kind = kind
        self.title = title
        self.generatedTitle = generatedTitle
        self.body = body
        self.annotation = annotation
        self.shared = shared
        self.book = book
        self.durationSeconds = durationSeconds
        self.place = place
        self.temperature = temperature
        self.tags = tags
    }
}

/// The text and chips of one card. Equatable so a test can compare two adapters' output.
struct NoteCardContent: Equatable {
    var title: String?
    var quote: String?
    var snippet: String?
    var chips: [NoteCardModel.Chip] = []
}

enum NoteCardBuilder {

    // MARK: - The one entry point

    static func content(for f: NoteCardFacts) -> NoteCardContent {
        var c = NoteCardContent()
        // A capture: no audio, a shared thing. Its row leads with the capture title and a
        // type chip (+ the domain for a link) — never a duration.
        if let shared = f.shared {
            c.title = clean(f.title) ?? clean(f.generatedTitle).map { NoteTitle.clip($0) }
                ?? captureTitle(shared: shared, annotation: f.annotation)
            c.snippet = captureSnippet(shared: shared, annotation: f.annotation)
            c.chips.append(.init(text: f.kind.label, systemImage: f.kind.glyph))
            if let domain = domain(of: shared) { c.chips.append(.init(text: domain, systemImage: nil)) }
            c.chips.append(contentsOf: NoteCardModel.tagChips(for: f.tags))
            return c
        }

        let titled = clean(f.title) != nil || clean(f.generatedTitle) != nil
        let quote = f.book != nil ? quoteLine(in: f.body) : nil
        if titled {
            c.title = clean(f.title) ?? clean(f.generatedTitle).map { NoteTitle.clip($0) }
            if let quote {
                c.quote = quote                       // a titled book capture: title + quote, no ramble
            } else {
                c.snippet = firstLine(of: f.body)     // titled row: ONE clipped line (phone rule)
            }
        } else if let quote {
            c.quote = quote
            c.snippet = rambleLine(in: f.body)        // untitled book capture: quote + first ramble line
        } else {
            // Untitled: the body carries the row; an empty one falls to the taxonomy word.
            c.snippet = bodyText(f.body) ?? f.kind.emptyTitleFallback
        }

        // Chips: source (everything but a plain voice memo; a book capture's own chip below
        // plays that part), book, duration, place, weather, tags.
        if f.book == nil, f.kind != .voiceMemo {
            c.chips.append(.init(text: f.kind.label, systemImage: f.kind.glyph))
        }
        if let book = f.book,
           let caption = CaptureQuote.caption(book: book.title, chapter: book.chapter) {
            c.chips.append(.init(text: caption, systemImage: SourceKind.audiobookQuote.glyph))
        }
        if let secs = f.durationSeconds, secs > 0 {
            c.chips.append(.init(text: duration(seconds: secs)))
        }
        if let place = clean(f.place) {
            c.chips.append(.init(text: place, systemImage: "mappin.circle.fill"))
        }
        if let t = f.temperature {
            c.chips.append(.init(text: "\(t)°", systemImage: "cloud.sun.fill"))
        }
        c.chips.append(contentsOf: NoteCardModel.tagChips(for: f.tags))
        return c
    }

    // MARK: - Pieces (also what the phone's detail-side helpers delegate to)

    /// The leading `> ` block as ONE row-sized line (≤120). nil when the body doesn't open
    /// with a quote. Rides `CaptureQuote.split` — the one splitter (C172).
    static func quoteLine(in body: String?) -> String? {
        guard let body, let split = CaptureQuote.split(NoteSnippet.plain(body)) else { return nil }
        let joined = split.displayText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return joined.isEmpty ? nil : String(joined.prefix(120))
    }

    /// First line below the quote block, markers stripped. nil while there is no ramble.
    static func rambleLine(in body: String?) -> String? {
        guard let body else { return nil }
        for raw in NoteSnippet.plain(body).components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(">") { continue }
            return NoteTitle.clip(line)
        }
        return nil
    }

    /// First non-empty line of the body, markers stripped, clipped to one title-length line.
    static func firstLine(of body: String?) -> String? {
        guard let body else { return nil }
        let line = NoteSnippet.plain(body)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
        guard let line, !line.isEmpty else { return nil }
        return NoteTitle.clip(line)
    }

    /// The whole plain body with blank lines collapsed — the untitled row's snippet (the view
    /// clamps it to two lines). nil when nothing readable is left (a lone `[[img_001]]`).
    static func bodyText(_ body: String?) -> String? {
        guard let body else { return nil }
        let cleaned = NoteSnippet.plain(body)
            .replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// A capture row's title: the page title (link), the first words (text), the annotation
    /// or "Image" (image), the file name (file).
    static func captureTitle(shared sc: SharedContent, annotation: String?) -> String {
        switch sc.type {
        case .url:
            if let t = clean(sc.urlTitle) { return t }
            if let u = sc.url, let host = URL(string: u)?.host { return host }
            return "Link"
        case .text:
            if let text = clean(sc.text) { return NoteTitle.clip(text) }
            return "Text snippet"
        case .image:
            if let ann = clean(annotation) { return NoteTitle.clip(ann) }
            return "Image"
        case .file:
            return sc.fileName ?? "File"
        }
    }

    /// The annotation (≤120), else — for a link — its domain.
    static func captureSnippet(shared sc: SharedContent, annotation: String?) -> String? {
        if let ann = clean(annotation) { return String(ann.prefix(120)) }
        if sc.type == .url { return domain(of: sc) }
        return nil
    }

    /// "swiftwithmajid.com" for a link capture, no `www.`.
    static func domain(of sc: SharedContent) -> String? {
        guard sc.type == .url, let urlStr = sc.url, let host = URL(string: urlStr)?.host else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    /// "m:ss", or "h:mm:ss" past the hour (an audiobook capture runs to double digits).
    static func duration(seconds: Double) -> String { DurationFormat.label(seconds: seconds) }

    private static func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}

// MARK: - Memo adapter (phone rows + the Mac's unrated rows)

extension Memo {
    /// The card facts of a stored memo. The phone's `MemoCard` and the Mac's quiet-row builder
    /// both call this, so an unrated Mac row and the same note on the phone cannot drift.
    func cardFacts(generatedTitle: String? = nil) -> NoteCardFacts {
        let hasAudio = !audioFilename.isEmpty
        let bookTitle = metadata?.bookTitle?.trimmingCharacters(in: .whitespaces)
        return NoteCardFacts(
            kind: SourceKind.of(self),
            title: title,
            generatedTitle: generatedTitle,
            body: transcript,
            annotation: annotationText,
            shared: hasAudio ? nil : sharedContent,
            book: (bookTitle?.isEmpty == false) ? .init(title: bookTitle!, chapter: metadata?.bookChapter) : nil,
            durationSeconds: hasAudio ? duration : nil,
            place: metadata?.location?.placeName,
            temperature: metadata?.weather?.temperature,
            tags: tags)
    }
}

extension NoteCardModel {
    /// Lay the shared content onto a card whose chrome the adapter has already set.
    mutating func apply(_ content: NoteCardContent) {
        title = content.title
        quote = content.quote
        snippet = content.snippet
        chips = content.chips
    }
}
