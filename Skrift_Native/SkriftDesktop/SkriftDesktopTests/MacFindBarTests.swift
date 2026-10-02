import XCTest
import AppKit

/// Q125 (D125): the Mac note editor enables the system find bar.
final class MacFindBarTests: XCTestCase {
    func testEnableTurnsOnFindBarAndIncrementalSearch() {
        let tv = NSTextView()
        tv.usesFindBar = false
        tv.isIncrementalSearchingEnabled = false
        NoteFindBar.enable(on: tv)
        XCTAssertTrue(tv.usesFindBar)
        XCTAssertTrue(tv.isIncrementalSearchingEnabled)
    }

    func testMenuVerbTagsMatchTextFinderActions() {
        XCTAssertEqual(NoteFindBar.Verb.show.rawValue, NSTextFinder.Action.showFindInterface.rawValue)
        XCTAssertEqual(NoteFindBar.Verb.next.rawValue, NSTextFinder.Action.nextMatch.rawValue)
        XCTAssertEqual(NoteFindBar.Verb.previous.rawValue, NSTextFinder.Action.previousMatch.rawValue)
    }

    func testEveryVerbHasATitle() {
        for v in NoteFindBar.Verb.allCases { XCTAssertFalse(v.title.isEmpty) }
    }
}
