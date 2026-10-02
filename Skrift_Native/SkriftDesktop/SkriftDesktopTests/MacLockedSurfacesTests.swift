import XCTest
import Foundation

/// Q101 — a locked note stays locked on every non-list surface (C91/C161/C213, R88): the
/// Way-out shelf rows + peek, the Journal ("Review") rows, and search. The surfaces route
/// through the Shared pure rules in `NoteVisibility`; these pin the rules (host-less — no
/// LocalAuthentication) plus the Mac matchers that call them. Synthetic notes only.
final class MacLockedSurfacesTests: XCTestCase {

    private let words = "a private thought about the thing"

    private func memo(locked: Bool, title: String? = nil) -> Memo {
        let id = UUID()
        let m = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: Date(),
                     title: title, transcript: words, transcriptStatus: .done, significance: 0)
        m.locked = locked
        return m
    }

    // MARK: - the title a hidden surface shows

    func testHiddenTitleIsTheSetTitleOrThePlaceholderNeverTheFirstLine() {
        let fallback = { "FIRST LINE OF THE WORDS" }
        XCTAssertEqual(NoteVisibility.displayTitle(locked: true, unlockedThisSession: false, title: nil, fallback: fallback),
                       "Locked note")
        XCTAssertEqual(NoteVisibility.displayTitle(locked: true, unlockedThisSession: false, title: "  ", fallback: fallback),
                       "Locked note")
        XCTAssertEqual(NoteVisibility.displayTitle(locked: true, unlockedThisSession: false, title: "Groceries", fallback: fallback),
                       "Groceries")
    }

    func testVisibleTitleUsesTheFallbackWhenUnlockedOrNeverLocked() {
        let fallback = { "FIRST LINE" }
        XCTAssertEqual(NoteVisibility.displayTitle(locked: false, unlockedThisSession: false, title: nil, fallback: fallback), "FIRST LINE")
        XCTAssertEqual(NoteVisibility.displayTitle(locked: true, unlockedThisSession: true, title: nil, fallback: fallback), "FIRST LINE")
    }

    // MARK: - the snippet a Journal row shows

    func testSnippetIsNilWhileHiddenAndPresentOnceUnlocked() {
        XCTAssertNil(NoteVisibility.snippet(locked: true, unlockedThisSession: false, words))
        XCTAssertEqual(NoteVisibility.snippet(locked: true, unlockedThisSession: true, words), words)
        XCTAssertEqual(NoteVisibility.snippet(locked: false, unlockedThisSession: false, words), words)
    }

    func testHiddenSnippetNeverEvaluatesTheWords() {
        var read = false
        let text: () -> String? = { read = true; return self.words }
        _ = NoteVisibility.snippet(locked: true, unlockedThisSession: false, text())
        XCTAssertFalse(read, "the words of a hidden note aren't even read")
    }

    // MARK: - search (recsj-053)

    func testSearchMatchRuleHidesBodyFieldsUntilUnlocked() {
        let body = words
        func hit(_ q: String, locked: Bool, unlocked: Bool) -> Bool {
            NoteVisibility.matches(query: q, locked: locked, unlockedThisSession: unlocked,
                                   title: "Groceries", bodyFields: { [body, "summary mentions apples"] })
        }
        XCTAssertTrue(hit("grocer", locked: true, unlocked: false), "the title still matches")
        XCTAssertFalse(hit("private", locked: true, unlocked: false))
        XCTAssertFalse(hit("apples", locked: true, unlocked: false))
        XCTAssertTrue(hit("private", locked: true, unlocked: true), "unlocked this session: the body counts")
        XCTAssertTrue(hit("private", locked: false, unlocked: false))
        XCTAssertTrue(hit("", locked: true, unlocked: false), "empty query matches all")
    }

    func testMacQuietRowSearchHonoursTheSessionUnlock() {
        let m = memo(locked: true)
        XCTAssertFalse(WayOutRules.matchesSearch(m, query: "private"))
        XCTAssertFalse(WayOutRules.matchesSearch(m, query: "private", unlockedThisSession: false))
        XCTAssertTrue(WayOutRules.matchesSearch(m, query: "private", unlockedThisSession: true))
        let open = memo(locked: false)
        XCTAssertTrue(WayOutRules.matchesSearch(open, query: "private"))
    }

    // MARK: - the shelf rows (list-sidebar-116, recsj-110)

    func testShelfRowTitleOfALockedNoteIsThePlaceholderOrSetTitle() {
        XCTAssertEqual(LockedRow.title(for: memo(locked: true)), "Locked note")
        XCTAssertEqual(LockedRow.title(for: memo(locked: true, title: "Groceries")), "Groceries")
        let pf = PipelineFile(id: UUID().uuidString, filename: "x.m4a", sourceType: .audio, uploadedAt: Date())
        pf.locked = true
        pf.transcript = words
        XCTAssertEqual(LockedRow.title(for: pf), "Locked note", "the Mac-only trash tail uses it too")
    }

    func testPlaceholderTitleIsOneConstant() {
        XCTAssertEqual(NoteVisibility.placeholderTitle, LockedRow.placeholderTitle)
    }
}
