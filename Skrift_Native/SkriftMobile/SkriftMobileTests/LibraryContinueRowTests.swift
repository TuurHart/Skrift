import XCTest
@testable import SkriftMobile

/// Q403 (D207, Q6 mock): the Library shelf's "Continue" row is the last few sources you played or
/// opened, any kind, most recent first; a finished source drops out; every cover carries a type
/// badge whose words come from the shared `SourceKind`.
final class LibraryContinueRowTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func source(_ title: String, kind: LibrarySourceKind, hoursAgo: Double?, position: Double,
                        duration: Double = 1_000, author: String = "") -> Audiobook {
        var b = Audiobook(audioFilename: "a.m4b", title: title, author: author, duration: duration,
                          lastPlayedAt: hoursAgo.map { now.addingTimeInterval(-$0 * 3_600) }, position: position)
        b.kind = kind
        return b
    }

    func testOrderIsMostRecentlyPlayedFirstAcrossKinds() {
        let books = [
            source("old pdf", kind: .pdf, hoursAgo: 30, position: 4, duration: 18),
            source("book", kind: .book, hoursAgo: 5, position: 300),
            source("article", kind: .article, hoursAgo: 1, position: 200),
            source("episode", kind: .episode, hoursAgo: 2, position: 100),
        ]
        XCTAssertEqual(LibraryContinue.items(from: books).map(\.title), ["article", "episode", "book", "old pdf"])
        XCTAssertEqual(Set(LibraryContinue.items(from: books).map(\.sourceKind)),
                       [.book, .episode, .pdf, .article])
    }

    func testFinishedSourcesDropOut() {
        let books = [
            source("done book", kind: .book, hoursAgo: 1, position: 990),          // within the 30 s tail
            source("done pdf", kind: .pdf, hoursAgo: 2, position: 18, duration: 18),
            source("done article", kind: .article, hoursAgo: 3, position: 1_000),
            source("reading", kind: .book, hoursAgo: 4, position: 100),
        ]
        XCTAssertEqual(LibraryContinue.items(from: books).map(\.title), ["reading"])
    }

    func testNeverOpenedSourcesAreNotInTheRow() {
        let books = [
            source("new", kind: .book, hoursAgo: nil, position: 0),
            source("opened", kind: .pdf, hoursAgo: 1, position: 1, duration: 18),
        ]
        XCTAssertEqual(LibraryContinue.items(from: books).map(\.title), ["opened"])
    }

    func testRowIsCappedAtFive() {
        let books = (0..<8).map { source("b\($0)", kind: .book, hoursAgo: Double($0), position: 10) }
        let row = LibraryContinue.items(from: books)
        XCTAssertEqual(row.count, 5)
        XCTAssertEqual(row.first?.title, "b0")
    }

    func testEmptyShelfHasNoRow() {
        XCTAssertTrue(LibraryContinue.items(from: []).isEmpty)
    }

    func testKindLabelsAndBadgesComeFromTheSharedTaxonomy() {
        XCTAssertEqual(LibrarySourceKind.book.label, SourceKind.audiobookLink.sourceName)
        XCTAssertEqual(LibrarySourceKind.episode.label, SourceKind.episodeLink.sourceName)
        XCTAssertEqual(LibrarySourceKind.pdf.label, SourceKind.pdfLink.sourceName)
        XCTAssertEqual(LibrarySourceKind.article.label, SourceKind.articleLink.sourceName)
        XCTAssertEqual(LibrarySourceKind.allCases.map(\.badge), ["AUDIOBOOK", "EPISODE", "PDF", "ARTICLE"])
    }

    func testBylineAddsTheReleaseDateForAnEpisode() {
        var ep = source("ep", kind: .episode, hoursAgo: 1, position: 10, author: "NRC Het Uur")
        ep.publishedAt = Date(timeIntervalSince1970: 1_782_468_000)   // 2026-06-26
        XCTAssertEqual(LibraryContinue.byline(ep, calendar: utc, locale: Locale(identifier: "en_GB")),
                       "NRC Het Uur \u{00B7} 26 Jun 2026")
        XCTAssertEqual(LibraryContinue.byline(source("b", kind: .book, hoursAgo: 1, position: 1, author: "Frank Herbert")),
                       "Frank Herbert")
        XCTAssertEqual(LibraryContinue.byline(source("b", kind: .book, hoursAgo: 1, position: 1)), "")
    }

    func testProgressAndLeftLinesPerKind() {
        let book = source("b", kind: .book, hoursAgo: 1, position: 500, duration: 1_000)
        XCTAssertEqual(LibraryContinue.leftLine(book), AudiobookTime.clock(500) + " left")
        let pdf = source("p", kind: .pdf, hoursAgo: 1, position: 4, duration: 18)
        XCTAssertEqual(LibraryContinue.progressLine(pdf), "p. 4 of 18")
        XCTAssertEqual(LibraryContinue.leftLine(pdf), "14 pages left")
        let art = source("a", kind: .article, hoursAgo: 1, position: 250, duration: 1_000)
        XCTAssertEqual(LibraryContinue.progressLine(art), "25%")
    }

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
}
