import XCTest
import Foundation

/// Q345: a book-quote note's derived title carries no markdown. Device feedback 2b8bc952
/// showed "> The first complete Odyssey in English w…" — the quote itself began with `>`, so
/// stripping ONE marker left the second. Every surface reads the one ladder, so one table
/// covers the static ladder, the Memo adapter (list row / header ghost) and the export title.
final class NoteTitleQuoteTests: XCTestCase {

    private struct Row { let name: String; let body: String; let expected: String }

    private static let rows: [Row] = [
        Row(name: "single marker", body: "> The first complete Odyssey in English.\n\nramble",
            expected: "The first complete Odyssey in English."),
        Row(name: "doubled marker (the feedback note)",
            body: "> > The first complete Odyssey in English was that of George Chapman, in 1615.\n\nMore blah",
            expected: "The first complete Odyssey in English was that of George Chapman, in 1615."),
        Row(name: "tight nested marker", body: ">> Deep quote\n\nramble", expected: "Deep quote"),
        Row(name: "italic-wrapped quote", body: "> *Focus is a skill.*\n\nramble", expected: "Focus is a skill."),
        Row(name: "underscore-wrapped quote", body: "> _Focus is a skill._\n\nramble", expected: "Focus is a skill."),
        Row(name: "quoted heading", body: "> # Chapter Two\n> body", expected: "Chapter Two"),
        Row(name: "quoted bullet", body: "> - first point\n> - second", expected: "first point"),
        Row(name: "bold run inside", body: "> **Train** it daily\n\nramble", expected: "Train it daily"),
        Row(name: "leading blank lines", body: "\n\n> Quote after blanks\n\nramble", expected: "Quote after blanks"),
    ]

    private func assertNoMarkers(_ t: String, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(t.hasPrefix(">"), "\(name): leading > in \"\(t)\"", file: file, line: line)
        for m in ["*", "_", "`", "#", "=="] {
            XCTAssertFalse(t.contains(m), "\(name): \"\(m)\" in \"\(t)\"", file: file, line: line)
        }
    }

    func testStaticLadder() {
        for r in Self.rows {
            let t = NoteTitle.display(userTitle: nil, suggestedTitle: nil, body: r.body, shared: nil, emptyFallback: "Voice note")
            XCTAssertEqual(t, r.expected, r.name)
            assertNoMarkers(t, r.name)
        }
    }

    func testMemoAdapterAndGhostMatch() {
        for r in Self.rows {
            let memo = Memo(audioFilename: "a.m4a", transcript: r.body)
            XCTAssertEqual(memo.ladderTitle(), r.expected, r.name)
            XCTAssertEqual(memo.ladderGhost(), r.expected, r.name)
        }
    }

    func testExportTitleUsesTheSameLadder() {
        for r in Self.rows {
            XCTAssertEqual(ExportNaming.title(userTitle: nil, suggestedTitle: nil, body: r.body, shared: nil, isVoice: true),
                           r.expected, r.name)
            XCTAssertEqual(ExportNaming.firstLine(r.body), r.expected, r.name)
        }
    }

    func testLongQuoteStillCutsAtTheLimitWithoutMarker() {
        let long = "> > " + String(repeating: "alpha beta gamma ", count: 10)
        let t = NoteTitle.firstLine(long)!
        XCTAssertFalse(t.hasPrefix(">"))
        XCTAssertLessThanOrEqual(t.count, NoteTitle.derivedLimit)
    }

    func testQuoteTextCaptureTitleHasNoMarker() {
        let sc = SharedContent(type: .text, text: "> > one two three four five six seven eight nine")
        XCTAssertEqual(NoteTitle.captureTitle(sc), "one two three four five six seven eight…")
    }

    func testPlainTitlesAreUntouched() {
        XCTAssertEqual(NoteTitle.firstLine("Dinner at 5 - maybe 6\nx"), "Dinner at 5 - maybe 6")
        XCTAssertEqual(NoteTitle.firstLine("snake_case_name is fine"), "snake_case_name is fine")
        XCTAssertEqual(NoteTitle.firstLine("2 * 3 = 6"), "2 * 3 = 6")
    }
}
