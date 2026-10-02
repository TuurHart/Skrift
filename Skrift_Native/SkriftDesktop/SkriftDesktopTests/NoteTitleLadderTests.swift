import XCTest
import Foundation

/// Q114 (C25, C239, C115): the ONE display-title ladder — `NoteTitle.display` — read by the
/// lists, headers, link rows and the exporters. The SAME fixture table lives in the phone's
/// `NoteTitleLadderTests`; each row runs through the static ladder, the export bridge
/// (`ExportNaming.title`, which must agree) and the `Memo` adapter both apps' lists call.
final class NoteTitleLadderTests: XCTestCase {

    private struct Row {
        let name: String
        var user: String? = nil
        var suggested: String? = nil
        var body: String? = nil
        var shared: SharedContent? = nil
        var typed = false          // a note with no audio and no shared thing → "Note"
        let expected: String
    }

    private static let longLine = String(repeating: "alpha beta gamma ", count: 10)   // 170 chars

    private static let rows: [Row] = [
        Row(name: "user title wins", user: "Mine", suggested: "Polished", body: "first", expected: "Mine"),
        Row(name: "suggested beats body", suggested: "Polished", body: "first", expected: "Polished"),
        Row(name: "blank user falls through", user: "  ", body: "first line\nsecond", expected: "first line"),
        Row(name: "markers stripped", body: "[[img_001]]\n[[Jack Smith]] rang again\nsecond",
            expected: "Jack Smith rang again"),
        Row(name: "book quote marker stripped", body: "> Focus is a skill.\n> Train it.",
            expected: "Focus is a skill."),
        Row(name: "clip at 120 on a word boundary", body: longLine,
            expected: String(longLine.prefix(120)).trimmingCharacters(in: .whitespaces)
                .split(separator: " ").dropLast().joined(separator: " ")),
        Row(name: "empty voice note", expected: "Voice note"),
        Row(name: "empty typed note", typed: true, expected: "Note"),
        Row(name: "link: urlTitle", shared: SharedContent(type: .url, url: "https://a.example/x", urlTitle: "A Post"),
            expected: "A Post"),
        Row(name: "text: first 8 words", shared: SharedContent(type: .text, text: "one two three four five six seven eight nine ten"),
            expected: "one two three four five six seven eight…"),
        Row(name: "image: file name", shared: SharedContent(type: .image, fileName: "board.jpg"),
            expected: "board.jpg"),
        Row(name: "capture: nothing at all", shared: SharedContent(type: .url), expected: "Capture"),
        Row(name: "annotation beats the share title", body: "My thoughts on it",
            shared: SharedContent(type: .url, urlTitle: "A Post"), expected: "My thoughts on it"),
        Row(name: "user title beats a capture", user: "Mine", shared: SharedContent(type: .url, urlTitle: "A Post"),
            expected: "Mine"),
        Row(name: "suggested beats a capture", suggested: "Polished", shared: SharedContent(type: .url, urlTitle: "A Post"),
            expected: "Polished"),
    ]

    private func memo(_ r: Row) -> Memo {
        if let sc = r.shared {
            return Memo(title: r.user, sharedContentData: try! JSONEncoder().encode(sc), annotationText: r.body)
        }
        if r.typed {
            return Memo(title: r.user, transcript: r.body,
                        metadataData: try! JSONSerialization.data(withJSONObject: ["mediaSource": "typed"]))
        }
        return Memo(audioFilename: "a.m4a", title: r.user, transcript: r.body)
    }

    func testEveryFixtureRowThroughTheStaticLadder() {
        for r in Self.rows {
            let hasAudio = r.shared == nil && !r.typed
            XCTAssertEqual(NoteTitle.display(userTitle: r.user, suggestedTitle: r.suggested, body: r.body,
                                             shared: r.shared, emptyFallback: hasAudio ? "Voice note" : "Note"),
                           r.expected, r.name)
        }
    }

    func testExportBridgeAgreesWithTheDisplayLadder() {
        for r in Self.rows {
            XCTAssertEqual(ExportNaming.title(userTitle: r.user, suggestedTitle: r.suggested, body: r.body,
                                              shared: r.shared, isVoice: r.shared == nil && !r.typed),
                           r.expected, r.name)
        }
    }

    func testMemoAdapterGivesTheSameTitle() {
        for r in Self.rows {
            XCTAssertEqual(memo(r).ladderTitle(suggestedTitle: r.suggested), r.expected, r.name)
        }
    }

    /// The header ghost is the ladder minus the user's title; nil (→ "Add a title") when the
    /// note has nothing to derive from.
    func testGhostIsTheDerivedTitleOrNil() {
        XCTAssertNil(memo(Self.rows[6]).ladderGhost(), "empty voice note ghosts the placeholder")
        XCTAssertEqual(memo(Self.rows[3]).ladderGhost(), "Jack Smith rang again")
        XCTAssertEqual(memo(Self.rows[0]).ladderGhost(), "first", "the user's own title is not its own ghost")
        XCTAssertEqual(memo(Self.rows[0]).ladderGhost(withUserTitle: true), "Mine")
        XCTAssertEqual(SharedCopy.titlePrompt(ghosts: [memo(Self.rows[6]).ladderGhost()]), SharedCopy.titlePlaceholder)
    }

    /// A user-typed or Mac-polished title on a capture beats the share title (the phone list
    /// row used to ignore both).
    func testCaptureHonoursUserAndPolishedTitleFirst() {
        let sc = SharedContent(type: .url, urlTitle: "A Post")
        let m = Memo(title: "Mine", sharedContentData: try! JSONEncoder().encode(sc))
        XCTAssertEqual(m.ladderTitle(), "Mine")
        let untitled = Memo(sharedContentData: try! JSONEncoder().encode(sc))
        XCTAssertEqual(untitled.ladderTitle(suggestedTitle: "Polished"), "Polished")
        XCTAssertEqual(untitled.ladderTitle(), "A Post")
    }
}
