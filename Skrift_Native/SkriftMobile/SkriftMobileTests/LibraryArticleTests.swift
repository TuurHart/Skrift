import XCTest
@testable import SkriftMobile

/// Q355 (D90, D138, mock `mocks/Q351-article-reader.html`, signed D195): a shared article link is
/// fetched once, its reader-mode text extracted and stored locally as a Library source (kind
/// `article`: title, site, byline, URL); a link that is not an article stays a note. "Add note"
/// on a selection makes a note that links back and exports `— *Title*, [site](URL)`.
/// Saved HTML pages under `test-fixtures/articles/`, no network.
final class LibraryArticleTests: XCTestCase {

    // MARK: - Fixtures

    private func html(_ name: String) throws -> String {
        // .../Skrift_Native/SkriftMobile/SkriftMobileTests/LibraryArticleTests.swift -> repo root is 4 up.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("test-fixtures/articles/\(name)"))
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private let localFirstURL = URL(string: "https://www.inkandswitch.com/local-first/")!
    private let webWeLostURL = URL(string: "https://anildash.com/2012/12/13/the_web_we_lost/")!
    private let videoURL = URL(string: "https://www.youtube.com/watch?v=example")!

    private func localFirst() throws -> ArticleDoc {
        try XCTUnwrap(ArticleExtractor.extract(html: html("local-first.html"), url: localFirstURL))
    }

    @MainActor
    private func makeStore() -> AudiobookLibraryStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("articles_\(UUID().uuidString)", isDirectory: true)
        return AudiobookLibraryStore(directory: dir)
    }

    /// Serves saved pages by URL; anything else is a transport failure. Counts GETs.
    private final class FixtureFetcher: LinkFetching, @unchecked Sendable {
        var pages: [URL: String] = [:]
        private(set) var gets = 0
        init(_ pages: [URL: String]) { self.pages = pages }
        func fetch(_ url: URL, method: String, timeout: TimeInterval) async -> LinkFetchResponse? {
            if method == "GET" { gets += 1 }
            guard let page = pages[url] else { return nil }
            return LinkFetchResponse(data: Data(page.utf8), statusCode: 200, contentType: "text/html; charset=utf-8")
        }
    }

    @MainActor
    private func cleanInbox() throws {
        guard let inbox = CaptureInbox.inboxURL else { throw XCTSkip("no App Group container in this test host") }
        try? FileManager.default.removeItem(at: inbox)
    }

    // MARK: - Extraction

    func testExtractsTitleSiteBylineAndDateFromTheEssayPage() throws {
        let doc = try localFirst()
        XCTAssertEqual(doc.title, "Local-first software", "og:title wins over the <title> with its site suffix")
        XCTAssertEqual(doc.site, "inkandswitch.com", "the site is the host without www (the mock's attribution)")
        XCTAssertEqual(doc.publisher, "Ink & Switch")
        XCTAssertEqual(doc.byline, "Martin Kleppmann, Adam Wiggins, Peter van Hardenberg, Mark McGranaghan")
        XCTAssertEqual(doc.url, "https://www.inkandswitch.com/local-first/")
        let year = Calendar(identifier: .gregorian).component(.year, from: try XCTUnwrap(doc.published))
        XCTAssertEqual(year, 2019)
    }

    func testKeepsHeadingsAndParagraphsInOrderAndDropsThePageChrome() throws {
        let doc = try localFirst()
        XCTAssertEqual(doc.blocks.filter { $0.kind == .heading }.map(\.text),
                       ["Why the cloud feels fragile", "What it asks of the software"])
        XCTAssertEqual(doc.blocks.first?.text, "Why the cloud feels fragile",
                       "the title, byline and date lines are header, not body")
        XCTAssertEqual(doc.blocks.filter { $0.kind == .paragraph }.count, 4)
        let body = doc.plainText
        XCTAssertTrue(body.contains("Your data should live on your own device first, and the network should only carry copies."))
        XCTAssertTrue(body.contains("someone else’s server"), "entities decode")
        for chrome in ["cookies", "Sign up", "newsletter", "independent research lab", "Figure 1", "earlier version", "About the lab"] {
            XCTAssertFalse(body.contains(chrome), "page chrome leaked into the reader: \(chrome)")
        }
    }

    func testCountsWordsAndReadingTime() throws {
        let doc = try localFirst()
        XCTAssertEqual(doc.wordCount, doc.plainText.split(whereSeparator: \.isWhitespace).count)
        XCTAssertGreaterThan(doc.wordCount, 150)
        XCTAssertEqual(doc.readMinutes, 1, "a short page still reads as 1 min, never 0")
        XCTAssertEqual(ArticleDoc.minutes(forWords: 9430), 41, "230 words a minute (the mock's 41 min read)")
    }

    func testABlogPostWithoutAnArticleTagStillExtracts() throws {
        let doc = try XCTUnwrap(ArticleExtractor.extract(html: html("web-we-lost.html"), url: webWeLostURL))
        XCTAssertEqual(doc.title, "The Web We Lost")
        XCTAssertEqual(doc.site, "anildash.com")
        XCTAssertNil(doc.publisher, "no og:site_name on this page")
        XCTAssertEqual(doc.byline, "Anil Dash", "byline from the rel=author link")
        XCTAssertEqual(doc.blocks.filter { $0.kind == .paragraph }.count, 5)
        XCTAssertEqual(doc.blocks.filter { $0.kind == .heading }.map(\.text), ["What changed"])
        XCTAssertFalse(doc.plainText.contains("Share this"))
        XCTAssertFalse(doc.plainText.contains("Archive"))
    }

    func testAVideoPageHasNoArticleText() throws {
        let page = try html("video-page.html")
        XCTAssertNil(ArticleExtractor.extract(html: page, url: videoURL),
                     "a video page is not an article (D138: it stays a note)")
    }

    func testTheDocRoundTripsThroughItsFile() throws {
        let doc = try localFirst()
        let data = try JSONEncoder().encode(doc)
        XCTAssertEqual(try JSONDecoder().decode(ArticleDoc.self, from: data), doc)
    }

    // MARK: - Routing: the share sheet's guess (it cannot load the page)

    func testTheShareSheetGuessesArticleForAnOrdinaryWebLink() {
        XCTAssertEqual(ArticleLinkGuess.guess("https://www.inkandswitch.com/local-first/"), .article)
        XCTAssertEqual(ArticleLinkGuess.guess("https://anildash.com/2012/12/13/the_web_we_lost/"), .article)
    }

    func testVideosPostsAndShopPagesAreGuessedAsNotes() {
        XCTAssertEqual(ArticleLinkGuess.guess("https://www.youtube.com/watch?v=abc"), .note(kind: "Video"))
        XCTAssertEqual(ArticleLinkGuess.guess("https://youtu.be/abc"), .note(kind: "Video"))
        XCTAssertEqual(ArticleLinkGuess.guess("https://vimeo.com/12345"), .note(kind: "Video"))
        XCTAssertEqual(ArticleLinkGuess.guess("https://x.com/hendri/status/123"), .note(kind: "Post"))
        XCTAssertEqual(ArticleLinkGuess.guess("https://twitter.com/hendri/status/123"), .note(kind: "Post"))
        XCTAssertEqual(ArticleLinkGuess.guess("https://www.instagram.com/p/abc/"), .note(kind: "Post"))
        XCTAssertEqual(ArticleLinkGuess.guess("https://www.amazon.de/dp/B000123"), .note(kind: "Product page"))
        XCTAssertEqual(ArticleLinkGuess.guess("https://shop.example.com/products/bench-psu"), .note(kind: "Product page"))
    }

    func testLinksOtherDoorsOwnKeepTodaysSheet() {
        XCTAssertEqual(ArticleLinkGuess.guess("https://podcasts.apple.com/nl/podcast/het-uur/id123"), .unchanged,
                       "a podcast link is the podcast door's (Q353)")
        XCTAssertEqual(ArticleLinkGuess.guess("https://open.spotify.com/episode/abc"), .unchanged)
        XCTAssertEqual(ArticleLinkGuess.guess("https://maps.apple.com/?q=Lisbon"), .unchanged)
        XCTAssertEqual(ArticleLinkGuess.guess("https://arxiv.org/pdf/2406.19741.pdf"), .unchanged)
        XCTAssertEqual(ArticleLinkGuess.guess("mailto:a@b.c"), .unchanged)
        XCTAssertEqual(ArticleLinkGuess.guess(nil), .unchanged)
    }

    func testPickingArticleMarksTheEntryForTheLibraryAndPickingNoteDoesNot() {
        let link = "https://www.inkandswitch.com/local-first/"
        XCTAssertTrue(ArticleLinkGuess.routesToLibrary(url: link, pickedArticle: true))
        XCTAssertFalse(ArticleLinkGuess.routesToLibrary(url: link, pickedArticle: false), "Note keeps it a note (D195)")
        XCTAssertFalse(ArticleLinkGuess.routesToLibrary(url: "https://youtu.be/abc", pickedArticle: true),
                       "a video never reaches Library, whatever the card state")
    }

    // MARK: - Routing: the app fetches and decides

    func testFetchFindsTheArticle() async throws {
        let fetcher = FixtureFetcher([localFirstURL: try html("local-first.html")])
        guard case .article(let doc) = await LibraryArticle.fetch(url: localFirstURL, fetcher: fetcher) else {
            return XCTFail("expected an article")
        }
        XCTAssertEqual(doc.title, "Local-first software")
        XCTAssertEqual(fetcher.gets, 1, "fetched once")
    }

    func testFetchOfAPageWithoutArticleTextSaysSo() async throws {
        let fetcher = FixtureFetcher([videoURL: try html("video-page.html")])
        let result = await LibraryArticle.fetch(url: videoURL, fetcher: fetcher)
        guard case .noArticle(let title) = result else { return XCTFail("expected noArticle, got \(result)") }
        XCTAssertEqual(title, "How a hydraulic press is built", "the note keeps the page title")
    }

    func testAFailedFetchIsUnreachableNotNoArticle() async {
        let result = await LibraryArticle.fetch(url: localFirstURL, fetcher: FixtureFetcher([:]))
        XCTAssertEqual(result, .unreachable, "offline is not 'no article text': the source waits and retries")
    }

    @MainActor
    func testTheDrainAddsAPickedArticleToTheLibraryWithItsTextStored() async throws {
        try cleanInbox()
        let repo = NotesRepository(inMemory: true)
        let store = makeStore()
        let savedStore = CaptureInboxDrainer.libraryStore, savedFetcher = LibraryArticle.fetcher
        CaptureInboxDrainer.libraryStore = store
        LibraryArticle.fetcher = FixtureFetcher([localFirstURL: try html("local-first.html")])
        defer { CaptureInboxDrainer.libraryStore = savedStore; LibraryArticle.fetcher = savedFetcher }

        let id = UUID()
        XCTAssertTrue(CaptureInbox.write(CaptureInboxEntry(
            id: id, type: "url", url: localFirstURL.absoluteString, urlTitle: "Local-first software",
            text: nil, imageFileName: nil, mimeType: nil, annotationText: nil, significance: 0,
            sharedAt: ISO8601.string(from: Date()), routeToLibrary: true)))

        await CaptureInboxDrainer.drain(into: repo)

        XCTAssertTrue(CaptureInbox.pendingEntries().isEmpty, "entry consumed")
        XCTAssertNil(repo.memo(id: id), "an article is a source, not a note")
        let book = try XCTUnwrap(store.books.first)
        XCTAssertEqual(store.books.count, 1)
        XCTAssertEqual(book.sourceKind, .article)
        XCTAssertEqual(book.title, "Local-first software")
        XCTAssertEqual(book.author, "Martin Kleppmann, Adam Wiggins, Peter van Hardenberg, Mark McGranaghan")
        XCTAssertEqual(book.site, "inkandswitch.com")
        XCTAssertEqual(book.sourceURL, localFirstURL.absoluteString)
        let stored = try XCTUnwrap(LibraryArticle.doc(of: book, store: store), "the text is stored for offline reading")
        XCTAssertEqual(stored.blocks.count, 6)
        XCTAssertEqual(book.duration, Double(stored.wordCount), "progress counts words")
    }

    @MainActor
    func testTheDrainSavesALinkWithoutArticleTextAsANoteAndSaysSo() async throws {
        try cleanInbox()
        let repo = NotesRepository(inMemory: true)
        let store = makeStore()
        let savedStore = CaptureInboxDrainer.libraryStore, savedFetcher = LibraryArticle.fetcher
        CaptureInboxDrainer.libraryStore = store
        LibraryArticle.fetcher = FixtureFetcher([videoURL: try html("video-page.html")])
        defer { CaptureInboxDrainer.libraryStore = savedStore; LibraryArticle.fetcher = savedFetcher }
        LibraryArticleArrival.shared.clear()

        let id = UUID()
        XCTAssertTrue(CaptureInbox.write(CaptureInboxEntry(
            id: id, type: "url", url: videoURL.absoluteString, urlTitle: nil,
            text: nil, imageFileName: nil, mimeType: nil, annotationText: nil, significance: 0,
            sharedAt: ISO8601.string(from: Date()), routeToLibrary: true)))

        await CaptureInboxDrainer.drain(into: repo)

        XCTAssertTrue(store.books.isEmpty, "no article text: nothing reaches Library")
        let memo = try XCTUnwrap(repo.memo(id: id), "the link is saved as a note")
        XCTAssertEqual(memo.sharedContent?.type, .url)
        XCTAssertEqual(memo.sharedContent?.url, videoURL.absoluteString)
        XCTAssertEqual(memo.sharedContent?.urlTitle, "How a hydraulic press is built")
        XCTAssertEqual(LibraryArticleArrival.shared.pending?.memoID, id, "the toast offers to open it")
        XCTAssertEqual(LibraryArticle.noArticleToast, "No article text on that page. Saved it as a note instead.")
        XCTAssertEqual(LibraryArticle.noArticleAction, "Open note")
    }

    @MainActor
    func testOfflineTheSourceWaitsAndALaterFetchStoresTheText() async throws {
        let store = makeStore()
        let repo = NotesRepository(inMemory: true)
        let book = LibraryArticle.addPending(url: localFirstURL.absoluteString, title: "Local-first software", store: store)
        XCTAssertEqual(book.sourceKind, .article)
        XCTAssertNil(LibraryArticle.doc(of: book, store: store))
        XCTAssertTrue(LibraryArticle.isFetching(book, store: store), "the tile says Getting the text…")

        let outcome = await LibraryArticle.complete(book, store: store, repository: repo,
                                                    fetcher: FixtureFetcher([localFirstURL: try html("local-first.html")]))
        XCTAssertEqual(outcome, .stored)
        let updated = try XCTUnwrap(store.book(id: book.id))
        XCTAssertNotNil(LibraryArticle.doc(of: updated, store: store))
        XCTAssertFalse(LibraryArticle.isFetching(updated, store: store))
        XCTAssertEqual(updated.site, "inkandswitch.com")
    }

    func testAnArticleRecordKeepsItsUrlAndSiteThroughCodable() throws {
        var book = Audiobook(audioFilename: "", title: "Local-first software", author: "Ink & Switch")
        book.kind = .article
        book.sourceURL = "https://www.inkandswitch.com/local-first/"
        book.site = "inkandswitch.com"
        let back = try JSONDecoder().decode(Audiobook.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(back.sourceURL, book.sourceURL)
        XCTAssertEqual(back.site, "inkandswitch.com")
        XCTAssertEqual(back.sourceKind, .article)
    }

    // MARK: - Reading place

    func testProgressCountsWordsAndShowsPercentAndMinutesLeft() {
        var book = Audiobook(audioFilename: "", title: "Local-first software", author: "", duration: 9430, position: 0)
        book.kind = .article
        XCTAssertEqual(LibraryArticle.progressLine(book), "new · 41 min read")
        book.position = 2923
        XCTAssertEqual(LibraryArticle.percent(of: book), 31)
        XCTAssertEqual(LibraryArticle.progressLine(book), "31%")
        XCTAssertEqual(LibraryArticle.leftLine(book), "28 min left")
        XCTAssertEqual(LibraryArticle.dockLine(book), "31% · 28 min left")
        book.position = 9430
        XCTAssertTrue(book.isFinished)
        XCTAssertEqual(LibraryArticle.progressLine(book), "finished")
    }

    // MARK: - Capture and link-back

    @MainActor
    func testAddNoteMakesAQuoteNoteThatLinksBackToTheArticle() throws {
        let store = makeStore()
        let repo = NotesRepository(inMemory: true)
        let doc = try localFirst()
        let book = LibraryArticle.add(doc, store: store)
        let quote = "Your data should live on your own device first, and the network should only carry copies."
        let at = try XCTUnwrap(doc.wordOffset(of: quote))
        let id = try XCTUnwrap(LibraryArticle.saveCapture(quote: quote, book: book, wordOffset: at,
                                                          significance: 0, repository: repo))
        let memo = try XCTUnwrap(repo.memo(id: id))
        XCTAssertEqual(memo.captureQuote?.displayText, quote, "the selection is the quote, word for word")
        let meta = try XCTUnwrap(memo.metadata)
        XCTAssertEqual(meta.bookID, book.id)
        XCTAssertEqual(meta.bookTitle, "Local-first software")
        XCTAssertNil(meta.bookAuthor, "no author in the attribution (D138: — *Title*, site)")
        XCTAssertEqual(meta.bookChapter, "inkandswitch.com")
        XCTAssertEqual(meta.bookKind, "article")
        XCTAssertEqual(meta.bookURL, "https://www.inkandswitch.com/local-first/")
        XCTAssertEqual(meta.bookPosition, Double(at))
        XCTAssertEqual(SourceKind.of(memo), .articleQuote)
        XCTAssertEqual(memo.quoteAttributionLabel, "— Local-first software, inkandswitch.com")

        let target = try XCTUnwrap(BookNotesJoin.jumpTarget(for: memo))
        let route = BookNotesJoin.route(for: target, source: book)
        let pct = Int((Double(at) / Double(doc.wordCount) * 100).rounded())
        XCTAssertEqual(route, .reading(word: at, percent: pct))
        XCTAssertEqual(BookNotesJoin.jumpLabel(for: route), "Back to it at \(pct)% in Library")
        XCTAssertEqual(BookNotesJoin.notes(forBook: book.id, in: [memo]).map(\.id), [id], "the ❝ count and the notes row find it")
    }

    func testTheNoteExportsTitleAndSiteAsTheLinkAndTheUrlAsSource() throws {
        let md = Compiler.audiobookBody("> Your data should live on your own device first.\n\nThe CloudKit bet in one line.",
                                        book: "Local-first software", author: nil, chapter: "inkandswitch.com",
                                        url: "https://www.inkandswitch.com/local-first/")
        XCTAssertEqual(md, """
        > *Your data should live on your own device first.*
        >
        > — *Local-first software*, [inkandswitch.com](https://www.inkandswitch.com/local-first/)

        The CloudKit bet in one line.
        """)
    }

    @MainActor
    func testTheExportedFrontmatterCarriesTheUrlAsSource() throws {
        let store = makeStore()
        let repo = NotesRepository(inMemory: true)
        let doc = try localFirst()
        let book = LibraryArticle.add(doc, store: store)
        let id = try XCTUnwrap(LibraryArticle.saveCapture(quote: "Neither is true any more.", book: book,
                                                          wordOffset: 40, significance: 0, repository: repo))
        let memo = try XCTUnwrap(repo.memo(id: id))
        let out = ExportV2Test.markdown(MemoExporter.compilerInput(for: memo, people: []), author: "Tuur")
        XCTAssertTrue(out.contains("\nsource: https://www.inkandswitch.com/local-first/\n"), out)
        XCTAssertTrue(out.contains("> — *Local-first software*, [inkandswitch.com](https://www.inkandswitch.com/local-first/)"), out)
    }
}
