import XCTest
@testable import SkriftMobile

/// Sentence-end detection (the live caption's paragraph joins lean on it).
final class ParagrapherTests: XCTestCase {

    func testEndsSentence() {
        XCTAssertTrue(Paragrapher.endsSentence("done."))
        XCTAssertTrue(Paragrapher.endsSentence("really?"))
        XCTAssertTrue(Paragrapher.endsSentence("stop!"))
        XCTAssertTrue(Paragrapher.endsSentence("\"quote.\""))
        XCTAssertFalse(Paragrapher.endsSentence("comma,"))
        XCTAssertFalse(Paragrapher.endsSentence("plain"))
        // Caveat: an abbreviation like "e.g." ends in "." so it reads as a sentence
        // end — acceptable, since it rarely coincides with a long (paragraph) pause.
        XCTAssertTrue(Paragrapher.endsSentence("e.g."))
    }
}
