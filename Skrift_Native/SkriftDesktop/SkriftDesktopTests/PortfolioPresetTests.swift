import XCTest

/// Q402 / D205: choosing Portfolio adds NO tags. idea / inspiration / project are suggestions
/// shown only while the note is Portfolio and carries none of them; a tap adds just that one;
/// flipping back to Personal removes nothing. One shared rule (`PortfolioTagPresets`), read by
/// the phone, iPad, Mac and quick note alike. The views are SwiftUI and this bundle is host-less,
/// so the tests drive the pure rule plus the pill's tap step, and read the call sites' source to
/// prove every surface asks the one rule.
final class PortfolioPresetTests: XCTestCase {

    // MARK: - Flip adds none

    func testFlippingToPortfolioAddsNoTags() {
        var destination = NoteDestination.personal
        let tags = ["studio", "lisbon"]
        _ = NoteDestination.tapped(&destination) { _ in }
        XCTAssertEqual(destination, .portfolio)
        XCTAssertEqual(tags, ["studio", "lisbon"], "the tap step never touches tags")
        // The rule offers all three, it does not apply them.
        XCTAssertEqual(PortfolioTagPresets.suggestions(destination: destination, tags: tags, enabled: true),
                       ["idea", "inspiration", "project"])
    }

    func testPersonalAndDestinationsOffOfferNothing() {
        XCTAssertEqual(PortfolioTagPresets.suggestions(destination: .personal, tags: [], enabled: true), [])
        XCTAssertEqual(PortfolioTagPresets.suggestions(destination: .portfolio, tags: [], enabled: false), [])
    }

    // MARK: - Tap adds one

    func testTappingOneSuggestionAddsOnlyThatTag() {
        let after = PortfolioTagPresets.picked("idea", into: ["studio"])
        XCTAssertEqual(after, ["studio", "idea"])
    }

    func testOnceOnePresetIsOnTheNoteTheSuggestionsLeave() {
        for p in PortfolioTagPresets.all {
            XCTAssertEqual(PortfolioTagPresets.suggestions(destination: .portfolio, tags: ["x", p], enabled: true), [],
                           "a note that has \(p) needs no suggestions")
        }
        // Case-insensitive, like every other tag comparison.
        XCTAssertEqual(PortfolioTagPresets.suggestions(destination: .portfolio, tags: ["Idea"], enabled: true), [])
    }

    func testPickingTwiceNeverDuplicates() {
        let once = PortfolioTagPresets.picked("project", into: [])
        XCTAssertEqual(PortfolioTagPresets.picked("PROJECT", into: once), ["project"])
    }

    func testPickedIgnoresAnythingThatIsNotAPreset() {
        XCTAssertEqual(PortfolioTagPresets.picked("lisbon", into: ["a"]), ["a"])
    }

    // MARK: - Flip back keeps tags

    func testFlippingBackToPersonalRemovesNothing() {
        var destination = NoteDestination.portfolio
        let tags = PortfolioTagPresets.picked("inspiration", into: ["studio"])
        _ = NoteDestination.tapped(&destination) { _ in }
        XCTAssertEqual(destination, .personal)
        XCTAssertEqual(tags, ["studio", "inspiration"], "the user's tag stays")
        XCTAssertEqual(PortfolioTagPresets.suggestions(destination: destination, tags: tags, enabled: true), [],
                       "the suggestions leave with Personal")
    }

    // MARK: - Every surface asks the one rule

    private static func source(_ rel: String) -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SkriftDesktopTests
            .deletingLastPathComponent()   // SkriftDesktop
            .deletingLastPathComponent()   // Skrift_Native
        return (try? String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)) ?? ""
    }

    func testPhoneIPadMacAndQuickNoteAllUseTheSharedRule() {
        for rel in ["SkriftDesktop/Features/Review/NoteProperties.swift",
                    "SkriftMobile/Features/MemoDetail/MemoPageView.swift"] {   // Q451: the quick note IS this page
            let code = Self.source(rel)
            XCTAssertFalse(code.isEmpty, "could not read \(rel)")
            XCTAssertTrue(code.contains("PortfolioTagPresets.suggestions("), "\(rel) must use the shared rule")
            XCTAssertFalse(code.contains("PortfolioTagPresets.all"), "\(rel) still hand-rolls the preset list")
        }
    }
}
