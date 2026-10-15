import Combine
import Foundation

// MARK: - The stored article

/// Q355 (D90 / D138, mock `mocks/Q351-article-reader.html`): an article's reader-mode text, fetched
/// once and stored locally as `article.json` in the source's folder, so the reader works offline.
/// Never synced: a second device with the same source fetches its own copy (`LibraryArticle.complete`).
struct ArticleDoc: Codable, Equatable, Sendable {
    struct Block: Codable, Equatable, Sendable {
        /// Q404: `row` (a two-column table line, cells joined by a tab) and `page` (a PDF's
        /// "Page N" break) come only from a PDF's reading view, never from an article.
        /// Q460: `figure` is a picture with its caption as `text` and the picture as `image`.
        enum Kind: String, Codable, Sendable { case heading, paragraph, row, page, figure }
        var kind: Kind
        var text: String
        /// Q404: the 1-based PDF page a reading-view block comes from (nil for an article).
        var page: Int? = nil
        /// Q460: a figure's picture (PNG), cropped from its PDF page. nil for every other kind.
        var image: Data? = nil
    }

    var url: String
    var title: String
    /// The host without "www." ("inkandswitch.com"): the attribution's site (D138).
    var site: String
    /// og:site_name ("Ink & Switch"), when the page names itself.
    var publisher: String?
    var byline: String?
    var published: Date?
    var blocks: [Block]

    /// The reader's text: blocks joined by blank lines. Word offsets count over this.
    var plainText: String { blocks.map(\.text).joined(separator: "\n\n") }
    var wordCount: Int { plainText.split(whereSeparator: \.isWhitespace).count }
    var readMinutes: Int { Self.minutes(forWords: wordCount) }

    /// 230 words a minute, never 0.
    static func minutes(forWords words: Int) -> Int { max(1, Int((Double(words) / 230).rounded())) }

    /// How many words of `plainText` come before `quote` (the capture's place). nil when absent.
    func wordOffset(of quote: String) -> Int? {
        let needle = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, let range = plainText.range(of: needle) else { return nil }
        return plainText[..<range.lowerBound].split(whereSeparator: \.isWhitespace).count
    }
}

// MARK: - Reader-mode extraction

/// Regex-grade reader mode over saved HTML (C4: "no AI, just parsing", the same grade as
/// `HTMLMeta`): the article scope (`<article>`, else `<main>`, else `<body>`) minus its chrome, then
/// its headings and paragraphs in page order. nil = no article text (a video, a post, a shop page),
/// which keeps the link a note (D138).
enum ArticleExtractor {
    /// Fewer paragraphs or characters than this is not an article (the `HTMLMeta` rule).
    static let minParagraphs = 3
    static let minCharacters = 400

    static func extract(html: String, url: URL) -> ArticleDoc? {
        let cleaned = HTMLMeta.strippingBlocks(html, tags: ["script", "style", "noscript", "svg", "template"])
        if let type = HTMLMeta.metaContent(cleaned, key: "og:type")?.lowercased(),
           type.hasPrefix("video") || type.hasPrefix("music") || type == "product" { return nil }

        let scope = HTMLMeta.tagText(cleaned, tag: "article", keepInnerHTML: true)
            ?? HTMLMeta.tagText(cleaned, tag: "main", keepInnerHTML: true)
            ?? HTMLMeta.tagText(cleaned, tag: "body", keepInnerHTML: true)
            ?? cleaned
        let body = strippingChrome(scope)
        let blocks = self.blocks(in: body)
        let paragraphs = blocks.filter { $0.kind == .paragraph }
        guard paragraphs.count >= minParagraphs,
              paragraphs.map(\.text.count).reduce(0, +) >= minCharacters else { return nil }

        let site = Self.site(of: url)
        let title = firstNonEmpty(HTMLMeta.metaContent(cleaned, key: "og:title"),
                                  HTMLMeta.metaContent(cleaned, key: "twitter:title"),
                                  HTMLMeta.tagText(scope, tag: "h1"),
                                  HTMLMeta.tagText(cleaned, tag: "title")).map(HTMLMeta.decodeEntities) ?? site
        let publisher = HTMLMeta.metaContent(cleaned, key: "og:site_name").map(HTMLMeta.decodeEntities)
        return ArticleDoc(url: url.absoluteString, title: clean(title), site: site,
                          publisher: publisher.map(clean), byline: byline(in: cleaned).map(clean),
                          published: published(in: cleaned), blocks: trimmed(blocks))
    }

    /// "https://www.inkandswitch.com/x" -> "inkandswitch.com".
    static func site(of url: URL) -> String {
        var host = url.host?.lowercased() ?? url.absoluteString
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    // MARK: Pieces

    /// Drop the in-article chrome: figures, asides, forms, nav, and the byline/date/share lines.
    private static func strippingChrome(_ html: String) -> String {
        var out = HTMLMeta.strippingBlocks(html, tags: ["nav", "header", "footer", "aside", "form", "figure",
                                                        "button", "h1"])
        let classes = "byline|author|dateline|date|meta|share|social|cookie|newsletter|related|comments|caption|subscribe"
        for tag in ["p", "span", "li", "div"] {
            // A div only when it has no nested div (a non-greedy match would cut a nested one in half).
            let inner = tag == "div" ? "(?:(?!<div\\b).)*?" : ".*?"
            let pattern = "<\(tag)\\b[^>]*class\\s*=\\s*[\"'][^\"']*\\b(?:\(classes))\\b[^\"']*[\"'][^>]*>\(inner)</\(tag)>"
            if let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                out = rx.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length),
                                                  withTemplate: " ")
            }
        }
        return out
    }

    /// Headings (h2-h4) and paragraphs in page order. A paragraph counts from 40 characters, or a
    /// shorter full sentence of 3+ words ("None of this is free." is text; "Share this" is chrome).
    private static func blocks(in html: String) -> [ArticleDoc.Block] {
        guard let rx = try? NSRegularExpression(pattern: "<(h[2-4]|p)\\b[^>]*>(.*?)</\\1>",
                                                options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        var out: [ArticleDoc.Block] = []
        for m in rx.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: m.range(at: 1)).lowercased()
            let text = clean(HTMLMeta.decodeEntities(HTMLMeta.strippingTags(ns.substring(with: m.range(at: 2)))))
            guard !text.isEmpty else { continue }
            if tag == "p" {
                let words = text.split(whereSeparator: \.isWhitespace).count
                let sentence = words >= 3 && ".!?”\"’)".contains(text.last!)
                if text.count >= 40 || sentence { out.append(.init(kind: .paragraph, text: text)) }
            } else if text.count <= 140 {
                out.append(.init(kind: .heading, text: text))
            }
        }
        return out
    }

    /// No heading at the very end, and no two headings in a row (an empty section).
    private static func trimmed(_ blocks: [ArticleDoc.Block]) -> [ArticleDoc.Block] {
        var out: [ArticleDoc.Block] = []
        for b in blocks {
            if b.kind == .heading, out.last?.kind == .heading { out.removeLast() }
            out.append(b)
        }
        while out.last?.kind == .heading { out.removeLast() }
        return out
    }

    private static func byline(in html: String) -> String? {
        if let meta = firstNonEmpty(HTMLMeta.metaContent(html, key: "author"),
                                    HTMLMeta.metaContent(html, key: "article:author"),
                                    HTMLMeta.metaContent(html, key: "parsely-author")),
           !meta.lowercased().hasPrefix("http") {
            return HTMLMeta.decodeEntities(meta)
        }
        let patterns = ["<a\\b[^>]*rel\\s*=\\s*[\"']author[\"'][^>]*>(.*?)</a>",
                        "<[a-z]+\\b[^>]*class\\s*=\\s*[\"'][^\"']*\\bbyline\\b[^\"']*[\"'][^>]*>(.*?)</[a-z]+>"]
        for p in patterns {
            guard let rx = try? NSRegularExpression(pattern: p, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { continue }
            let ns = html as NSString
            if let m = rx.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) {
                var text = clean(HTMLMeta.decodeEntities(HTMLMeta.strippingTags(ns.substring(with: m.range(at: 1)))))
                if text.lowercased().hasPrefix("by ") { text.removeFirst(3) }
                if !text.isEmpty, text.count <= 120 { return text }
            }
        }
        return nil
    }

    private static func published(in html: String) -> Date? {
        let raw = firstNonEmpty(HTMLMeta.metaContent(html, key: "article:published_time"),
                                HTMLMeta.metaContent(html, key: "date"),
                                timeDatetime(html))
        guard let raw else { return nil }
        let iso = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds],
                                                       [.withInternetDateTime], [.withFullDate]] {
            iso.formatOptions = options
            if let d = iso.date(from: raw) { return d }
        }
        return nil
    }

    private static func timeDatetime(_ html: String) -> String? {
        guard let rx = try? NSRegularExpression(pattern: "<time\\b[^>]*datetime\\s*=\\s*[\"']([^\"']+)[\"']",
                                                options: .caseInsensitive) else { return nil }
        let ns = html as NSString
        return rx.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstNonEmpty(_ vals: String?...) -> String? {
        for v in vals { if let v, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return v } }
        return nil
    }
}

// MARK: - The Library source

/// Q355: an article as a Library source. Like a PDF it is an `Audiobook` record (`kind == .article`)
/// so the shelf, the sync carrier and the ❝ N note join keep working with no schema change. For an
/// article the audio fields count WORDS: `duration` = word count, `position` = the word at the top
/// of the reader (0 = never opened). `sourceURL` and `site` ride the same blob.
enum LibraryArticle {

    static let fileName = "article.json"
    static let noArticleToast = "No article text on that page. Saved it as a note instead."
    static let noArticleAction = "Open note"

    /// The network. Tests swap in saved pages.
    static var fetcher: any LinkFetching = URLSessionLinkFetcher()

    // MARK: Fetch

    enum Fetch: Equatable {
        case article(ArticleDoc)
        /// The page loaded but has no article text; `title` is its page title for the note.
        case noArticle(title: String?)
        /// No answer (offline, a server error): the source waits and tries again later.
        case unreachable
    }

    static func fetch(url: URL, fetcher: any LinkFetching) async -> Fetch {
        guard url.scheme?.lowercased().hasPrefix("http") == true else { return .noArticle(title: nil) }
        guard let page = await fetcher.fetch(url, method: "GET", timeout: 15) else { return .unreachable }
        guard page.contentType.lowercased().contains("html") || page.contentType.isEmpty,
              let html = String(data: page.data, encoding: .utf8) ?? String(data: page.data, encoding: .isoLatin1)
        else { return .noArticle(title: nil) }
        if let doc = ArticleExtractor.extract(html: html, url: url) { return .article(doc) }
        return .noArticle(title: HTMLMeta.parse(html, baseURL: url).title)
    }

    // MARK: Store

    /// A new source holding `doc`, its text written to the source's folder.
    @MainActor
    @discardableResult
    static func add(_ doc: ArticleDoc, store: AudiobookLibraryStore, id: UUID = UUID(), now: Date = Date()) -> Audiobook {
        var book = Audiobook(id: id, files: [fileName], fileDurations: [0], title: doc.title, author: "",
                             importedAt: now, position: 0, modifiedAt: now)
        book.kind = .article
        book.sourceURL = doc.url
        apply(doc, to: &book)
        save(doc, bookID: id, store: store)
        store.add(book)
        return book
    }

    /// A source whose text has not arrived yet (offline at share time, or synced from another
    /// device). The tile says "Getting the text…" until `complete` stores it.
    @MainActor
    @discardableResult
    static func addPending(url: String, title: String?, store: AudiobookLibraryStore,
                           id: UUID = UUID(), now: Date = Date()) -> Audiobook {
        let site = URL(string: url).map(ArticleExtractor.site(of:)) ?? url
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var book = Audiobook(id: id, files: [fileName], fileDurations: [0], title: name.isEmpty ? site : name,
                             author: "", importedAt: now, position: 0, modifiedAt: now)
        book.kind = .article
        book.sourceURL = url
        book.site = site
        store.add(book)
        return book
    }

    enum Completion: Equatable { case stored, becameNote(UUID), unreachable }

    /// Fetch a waiting source's text. Article text: stored. No article text: the source leaves
    /// Library and the link becomes a note (D138), announced by the toast. No answer: it waits.
    @MainActor
    static func complete(_ book: Audiobook, store: AudiobookLibraryStore, repository: NotesRepository = .shared,
                         fetcher: any LinkFetching = LibraryArticle.fetcher) async -> Completion {
        guard let raw = book.sourceURL, let url = URL(string: raw) else { return .unreachable }
        switch await fetch(url: url, fetcher: fetcher) {
        case .article(let doc):
            save(doc, bookID: book.id, store: store)
            var updated = store.book(id: book.id) ?? book
            apply(doc, to: &updated)
            store.update(updated)
            return .stored
        case .noArticle(let title):
            let id = linkNote(id: book.id, url: raw, title: title ?? book.title, repository: repository)
            store.remove(book)
            LibraryArticleArrival.shared.post(memoID: id)
            return .becameNote(id)
        case .unreachable:
            return .unreachable
        }
    }

    /// Title, byline, site and word count from the doc onto the record (the user's own title edit
    /// is not kept apart: an article's title is the page's).
    private static func apply(_ doc: ArticleDoc, to book: inout Audiobook) {
        book.title = doc.title
        book.author = doc.byline ?? doc.publisher ?? ""
        book.site = doc.site
        book.duration = Double(doc.wordCount)
        book.fileDurations = [Double(doc.wordCount)]
        book.publishedAt = doc.published
    }

    @MainActor
    static func docURL(bookID: UUID, store: AudiobookLibraryStore) -> URL {
        store.folder(for: bookID).appendingPathComponent(fileName)
    }

    @MainActor
    static func save(_ doc: ArticleDoc, bookID: UUID, store: AudiobookLibraryStore) {
        let url = docURL(bookID: bookID, store: store)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(doc) { try? data.write(to: url, options: .atomic) }
    }

    @MainActor
    static func doc(of book: Audiobook, store: AudiobookLibraryStore) -> ArticleDoc? {
        guard let data = try? Data(contentsOf: docURL(bookID: book.id, store: store)) else { return nil }
        return try? JSONDecoder().decode(ArticleDoc.self, from: data)
    }

    /// True while the text is not on this device yet.
    @MainActor
    static func isFetching(_ book: Audiobook, store: AudiobookLibraryStore) -> Bool {
        book.sourceKind == .article && !FileManager.default.fileExists(atPath: docURL(bookID: book.id, store: store).path)
    }

    // MARK: Reading place

    static func percent(word: Int, of book: Audiobook) -> Int {
        guard book.duration > 0 else { return 0 }
        return min(100, max(0, Int((Double(word) / book.duration * 100).rounded())))
    }

    static func percent(of book: Audiobook) -> Int { percent(word: Int(book.position), of: book) }

    /// The tile line: "new · 41 min read", "31%", "finished".
    static func progressLine(_ book: Audiobook) -> String {
        if book.isFinished { return "finished" }
        if book.position <= 0 { return "new · \(ArticleDoc.minutes(forWords: Int(book.duration))) min read" }
        return "\(percent(of: book))%"
    }

    /// "28 min left".
    static func leftLine(_ book: Audiobook) -> String {
        let left = max(0, Int(book.duration - book.position))
        return "\(ArticleDoc.minutes(forWords: left)) min left"
    }

    /// The reader dock: "31% · 28 min left".
    static func dockLine(_ book: Audiobook) -> String { "\(percent(of: book))% · \(leftLine(book))" }

    @MainActor
    static func savePosition(word: Int, bookID: UUID, store: AudiobookLibraryStore) {
        guard let book = store.book(id: bookID) else { return }
        let clamped = min(max(0, Double(word)), book.duration)
        guard abs(clamped - book.position) >= 1 else { return }
        store.updateProgress(id: bookID, position: clamped)
    }

    // MARK: Capture (the selection + his voice)

    /// The note "Add note" starts as: the selection as the quote block (word for word), the
    /// source in the metadata (title, site as the place, the URL, kind "article", the word it
    /// starts at). His voice is then appended by the normal recorder, as for a PDF quote.
    @MainActor
    @discardableResult
    static func saveCapture(quote: String, book: Audiobook, wordOffset: Int, significance: Double,
                            repository: NotesRepository = .shared, now: Date = Date()) -> UUID? {
        let transcript = QuoteFormatting.blockquote(quote)
        guard !transcript.isEmpty else { return nil }
        let id = UUID()
        var meta = MemoMetadata(bookTitle: book.title,
                                bookChapter: book.site ?? book.sourceURL.flatMap(URL.init(string:)).map(ArticleExtractor.site(of:)),
                                bookID: book.id,
                                bookPosition: Double(max(0, wordOffset)))
        meta.bookKind = LibrarySourceKind.article.rawValue
        meta.bookURL = book.sourceURL
        repository.insert(Memo.make(
            id: id, audioFilename: "", recordedAt: now, syncStatus: .waiting,
            transcript: transcript, transcriptStatus: .done,
            transcriptUserEdited: true,   // deliberate quote: the Mac must not re-transcribe
            significance: significance, metadata: meta))
        return id
    }

    /// The plain link note a page without article text becomes: today's link card, unchanged.
    @MainActor
    @discardableResult
    static func linkNote(id: UUID, url: String, title: String?, repository: NotesRepository,
                         now: Date = Date()) -> UUID {
        if repository.memo(id: id) != nil { return id }
        let shared = SharedContent(type: .url, url: url, urlTitle: title)
        repository.insert(Memo.make(id: id, audioFilename: "", duration: 0, recordedAt: now, tags: [],
                                    syncStatus: .waiting, transcript: nil, transcriptStatus: .done,
                                    significance: 0, sharedContent: shared))
        return id
    }

    /// The drain's step for an entry he marked "Article" (`routeToLibrary` on a url entry). Article
    /// text: a source with the text stored. No article text: a link note + the toast. No answer:
    /// a waiting source. Never a lost share. The source reuses the entry id, so a re-drain finds it.
    @MainActor
    static func drain(entryID: UUID, url: String, title: String?, store: AudiobookLibraryStore,
                      repository: NotesRepository) async {
        if store.book(id: entryID) != nil || repository.memo(id: entryID) != nil { return }
        guard let remote = URL(string: url) else {
            linkNote(id: entryID, url: url, title: title, repository: repository)
            return
        }
        switch await fetch(url: remote, fetcher: fetcher) {
        case .article(let doc):
            add(doc, store: store, id: entryID)
            DevLog.log("drain: article \(entryID) → Library ('\(doc.title)', \(doc.wordCount) words)")
        case .noArticle(let pageTitle):
            linkNote(id: entryID, url: url, title: pageTitle ?? title, repository: repository)
            LibraryArticleArrival.shared.post(memoID: entryID)
            DevLog.log("drain: article \(entryID) has no article text → note")
        case .unreachable:
            addPending(url: url, title: title, store: store, id: entryID)
            DevLog.log("drain: article \(entryID) unreachable → waiting source")
        }
    }
}

/// Q355: "a link had no article text" from the drain (or a later fetch) to the Library tab, which
/// shows the toast "No article text on that page. Saved it as a note instead." with "Open note".
@MainActor
final class LibraryArticleArrival: ObservableObject {
    static let shared = LibraryArticleArrival()
    struct Arrival: Equatable, Identifiable {
        let memoID: UUID
        var id: UUID { memoID }
    }
    @Published private(set) var pending: Arrival?
    func post(memoID: UUID) { pending = Arrival(memoID: memoID) }
    func clear() { pending = nil }
}
