import UIKit
import XCTest
@testable import SkriftMobile

/// Q404 (D207, the Q6 + Q351 mocks' callout "Copy · Highlight · ❝ Add note"): a highlight is a
/// stored range on a Library source, no note made, drawn yellow, removable from its own menu, and
/// synced inside the Library item's blob (the `Audiobook` record), so it rides the existing carrier.
final class SourceHighlightTests: XCTestCase {

    @MainActor
    private func makeStore() -> AudiobookLibraryStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audiobooks_\(UUID().uuidString)", isDirectory: true)
        return AudiobookLibraryStore(directory: dir)
    }

    private func article(id: UUID = UUID(), modifiedAt: Date = Date(timeIntervalSince1970: 1000)) -> Audiobook {
        var b = Audiobook(id: id, files: ["article.json"], fileDurations: [100], title: "Local-first software",
                          author: "", duration: 100, modifiedAt: modifiedAt)
        b.kind = .article
        return b
    }

    // MARK: - The pure list rules (Shared)

    func testAddingKeepsTheTrimmedTextAndItsPlace() {
        let list = SourceHighlights.adding("  Your data should live\non your own device first. ", page: nil, word: 42, to: [])
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].text, "Your data should live on your own device first.", "whitespace collapses to one space")
        XCTAssertEqual(list[0].word, 42)
        XCTAssertNil(list[0].page)
    }

    func testABlankSelectionOrTheSameRangeTwiceAddsNothing() {
        var list = SourceHighlights.adding(" \n ", page: 4, word: 0, to: [])
        XCTAssertTrue(list.isEmpty)
        list = SourceHighlights.adding("Travel €3,200", page: 4, word: 10, to: list)
        list = SourceHighlights.adding("Travel €3,200", page: 4, word: 10, to: list)
        XCTAssertEqual(list.count, 1, "the same range twice is one highlight")
        list = SourceHighlights.adding("Travel €3,200", page: 5, word: 30, to: list)
        XCTAssertEqual(list.count, 2, "the same words on another page are another highlight")
    }

    func testRemovingTakesOnlyThatHighlight() {
        var list = SourceHighlights.adding("one two three", page: nil, word: 0, to: [])
        list = SourceHighlights.adding("four five six", page: nil, word: 3, to: list)
        let gone = list[0].id
        list = SourceHighlights.removing(gone, from: list)
        XCTAssertEqual(list.map(\.text), ["four five six"])
    }

    func testTheRangeIsTheOccurrenceNearestItsWord() {
        // "the field tests" appears twice; the highlight made at word 9 is the second one.
        let text = "We ask the field tests first. Then the panel reads the field tests again."
        let ns = text as NSString
        var starts: [Int] = []
        var inWord = false
        for i in 0..<ns.length {
            let space = ns.character(at: i) == 32
            if !space, !inWord { starts.append(i) }
            inWord = !space
        }
        let h = SourceHighlight(text: "the field tests", page: nil, word: 10)
        let r = SourceHighlights.range(of: h.text, near: h.word, in: text, wordStarts: starts)
        XCTAssertEqual(r?.location, ns.range(of: "the field tests", options: .backwards).location)
        let first = SourceHighlights.range(of: h.text, near: 1, in: text, wordStarts: starts)
        XCTAssertEqual(first?.location, ns.range(of: "the field tests").location)
        XCTAssertNil(SourceHighlights.range(of: "not here", near: 0, in: text, wordStarts: starts))
    }

    // MARK: - Stored in the synced blob

    func testHighlightsRideTheLibraryRecordThroughCodableAndSync() throws {
        var book = article()
        book.highlights = SourceHighlights.adding("on your own device first", page: nil, word: 20, to: [])
        let data = try JSONEncoder().encode(book.sanitizedForSync())
        let back = try JSONDecoder().decode(Audiobook.self, from: data)
        XCTAssertEqual(back.highlights, book.highlights, "highlights are synced, not local-only")
    }

    func testARecordWrittenBeforeHighlightsDecodesWithNone() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(article())) as! [String: Any]
        json.removeValue(forKey: "highlights")
        let back = try JSONDecoder().decode(Audiobook.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(back.highlights)
    }

    @MainActor
    func testTheStoreAddsAndRemovesAndBumpsTheSyncClock() throws {
        let store = makeStore()
        let book = article()
        store.add(book)
        let id = try XCTUnwrap(LibraryHighlights.add("on your own device first", page: nil, word: 20,
                                                     bookID: book.id, store: store))
        let stored = try XCTUnwrap(store.book(id: book.id))
        XCTAssertEqual(stored.highlights?.map(\.id), [id])
        XCTAssertGreaterThan(stored.modifiedAt, book.modifiedAt, "a highlight is a synced change (LWW key moves)")
        LibraryHighlights.remove(id, bookID: book.id, store: store)
        XCTAssertEqual(store.book(id: book.id)?.highlights ?? [], [])
    }

    // MARK: - Drawn yellow, removable from its own menu

    @MainActor
    func testTheReaderPaintsAStoredHighlightAndTagsItForItsMenu() {
        let doc = ArticleDoc(url: "https://example.com/a", title: "A", site: "example.com", publisher: nil,
                             byline: nil, published: nil,
                             blocks: [.init(kind: .paragraph, text: "Neither is true any more. Your data should live on your own device first.")])
        let h = SourceHighlight(text: "Your data should live on your own device first.", page: nil, word: 5)
        let built = ArticleLayout.build(doc, fontSize: 17, lineHeight: 1.7, noteQuotes: [], highlights: [h])
        let ns = built.text.string as NSString
        let r = ns.range(of: h.text)
        XCTAssertNotEqual(r.location, NSNotFound)
        let tag = built.text.attribute(ArticleTextView.highlightKey, at: r.location + 3, effectiveRange: nil) as? UUID
        XCTAssertEqual(tag, h.id, "a tap there finds the highlight, so its menu can remove it")
        XCTAssertNotNil(built.text.attribute(.backgroundColor, at: r.location + 3, effectiveRange: nil), "drawn yellow")
        let before = ns.range(of: "Neither")
        XCTAssertNil(built.text.attribute(ArticleTextView.highlightKey, at: before.location, effectiveRange: nil))
    }

    func testBothSelectionMenusOfferHighlight() {
        XCTAssertEqual(SourceMenu.selectionItems(insideHighlight: false), ["Copy", "Highlight", "\u{275D} Add note"],
                       "the mocks' callout, PDF and article alike")
        XCTAssertEqual(SourceMenu.selectionItems(insideHighlight: true), ["Copy", "Remove highlight", "\u{275D} Add note"])
        XCTAssertEqual(SourceMenu.highlightItems, ["Copy", "Remove highlight"], "a tap on a highlight opens its own menu")
    }
}
