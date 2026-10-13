import XCTest
import SwiftUI
@testable import SkriftMobile

/// Q379 (D193, D197, D198, signed mock Q378-ipad-apple, tabs option A): the iPad layout of the
/// universal phone target. Regular width = list column + open note side by side, the four tabs as
/// a slim control at the top of the list column (no system tab bar), the note text running the
/// full pane width with Apple's margins, Apple's in-note attach menu minus Record Audio, and the
/// Mac's full Aa list. Compact width (phone, iPad Split View) keeps the phone layout.
final class IPadLayoutTests: XCTestCase {

    // MARK: the size-class switch

    func testRegularWidthIsTheSplitAndCompactIsThePhoneStack() {
        XCTAssertEqual(IPadLayout.mode(.regular), .split)
        XCTAssertEqual(IPadLayout.mode(.compact), .stack)
        XCTAssertEqual(IPadLayout.mode(nil), .stack, "an unknown size class must fall back to the phone")
    }

    func testTheSystemTabBarShowsOnlyOnThePhoneLayout() {
        XCTAssertFalse(IPadLayout.showsSystemTabBar(.regular), "option A: the tabs live in the list column")
        XCTAssertTrue(IPadLayout.showsSystemTabBar(.compact))
        XCTAssertTrue(IPadLayout.showsSystemTabBar(nil))
    }

    // MARK: tabs option A

    func testTheTabControlCarriesTheFourTabsInOrder() {
        XCTAssertEqual(IPadLayout.tabs, [.notes, .books, .journal, .settings])
        XCTAssertEqual(IPadLayout.tabs.map(IPadLayout.tabTitle), ["Notes", "Library", "Review", "Settings"])
    }

    func testTheColumnGeometryMatchesTheMock() {
        XCTAssertEqual(IPadLayout.listColumnWidth, 375)
        XCTAssertEqual(IPadLayout.rowHeight, 60, "tab row, list header and note toolbar are 60 pt lines")
        XCTAssertEqual(IPadLayout.glassHeight, 44)
        XCTAssertEqual(IPadLayout.toggleLeading, 9, "◧ sits 9 pt from the leading edge")
        XCTAssertEqual(IPadLayout.tabRowLeading, 63, "the tab control clears the ◧")
        XCTAssertEqual(IPadLayout.tabRowTrailing, 9)
    }

    // MARK: full-width note text (D198: not capped at 640 pt)

    func testNoteMarginsAreAppleSBesideTheListAndFullScreen() {
        XCTAssertEqual(IPadLayout.noteMargin(listVisible: true), 48)
        XCTAssertEqual(IPadLayout.noteMargin(listVisible: false), 89)
    }

    func testTheNoteTextRunsTheWholePaneWidth() {
        // 13" landscape, list open: 1376 - 375 = 1001 pt pane, 48 pt each side.
        XCTAssertEqual(IPadLayout.textWidth(paneWidth: 1001, listVisible: true), 905)
        // List hidden: the whole screen, 89 pt each side.
        XCTAssertEqual(IPadLayout.textWidth(paneWidth: 1376, listVisible: false), 1198)
        XCTAssertGreaterThan(IPadLayout.textWidth(paneWidth: 1001, listVisible: true), 640,
                             "the old 640 pt reading cap is gone on iPad")
    }

    // MARK: Apple's attach menu (D198)

    func testTheAttachMenuIsApplesMinusRecordAudio() {
        XCTAssertEqual(IPadLayout.attachHeader, "Add to this note")
        XCTAssertEqual(IPadLayout.AttachItem.allCases.map(\.title),
                       ["Scan Document", "Take Photo or Video", "Choose Photo or Video", "Attach File"])
        XCTAssertFalse(IPadLayout.AttachItem.allCases.map(\.title).contains("Record Audio"))
        for item in IPadLayout.AttachItem.allCases {
            XCTAssertNotNil(UIImage(systemName: item.symbol), "\(item.title): SF Symbol \(item.symbol) does not exist")
        }
    }

    // MARK: the full Aa list (D197)

    func testTheAaMarksAreBIUSAndHighlight() {
        XCTAssertEqual(IPadFormatMenu.marks, [.bold, .italic, .underline, .strike, .highlight])
    }

    func testTheAaStyleListIsApplesFull() {
        XCTAssertEqual(IPadFormatMenu.styles.map(\.label), ["Title", "Heading", "Subheading", "Body", "Monostyled"])
        XCTAssertEqual(IPadFormatMenu.lists.map(\.label), ["Bulleted", "Dashed", "Numbered"])
        XCTAssertEqual(IPadFormatMenu.quote.label, "Block Quote")
    }

    /// Each caption is the Markdown the row really writes (the shared rule, never a guess).
    func testEveryCaptionIsWhatTheRowWrites() {
        for row in IPadFormatMenu.styles + IPadFormatMenu.lists + [IPadFormatMenu.quote] {
            guard case .line(let style) = row.action else { continue }
            let written = BodyFormat.setStyle(style, in: "word", selection: NSRange(location: 0, length: 0)).text
            let expected = row.hint == "plain" ? "word" : row.hint + "word"
            XCTAssertEqual(written, expected, "\(row.label) says \(row.hint) but writes \(written)")
        }
        XCTAssertEqual(IPadFormatMenu.styles.last?.action, .monostyled)
        let mono = BodyFormat.monostyled(in: "a word here", selection: NSRange(location: 2, length: 4)).text
        XCTAssertEqual(mono, "a `word` here", "Monostyled on a selection writes inline code")
    }
}
