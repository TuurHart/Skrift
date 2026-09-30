import XCTest
@testable import SkriftMobile

/// Q82 group 13: search by meaning is ONE shared rule (`SemanticSearch`) — the floor, the
/// exact-match exclusion and what a note contributes to the index. Identical file in the
/// phone and Mac test targets: same input, same output.
final class SemanticSearchTests: XCTestCase {

    func testResultsFloorExcludeSortAndCap() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let scores: [(memoID: UUID, score: Float)] = [(a, 0.30), (b, 0.80), (c, 0.10), (d, 0.55)]
        XCTAssertEqual(SemanticSearch.results(scores: scores, excluding: []), [b, d, a],
                       "below the 0.25 floor is dropped, best first")
        XCTAssertEqual(SemanticSearch.results(scores: scores, excluding: [b]), [d, a],
                       "an exact match never repeats under Related")
        XCTAssertEqual(SemanticSearch.results(scores: scores, excluding: [], limit: 1), [b])
        XCTAssertEqual(SemanticSearch.results(scores: scores, excluding: [], floor: 0.6), [b])
    }

    func testSnapshotBodyAndTitlePrecedence() {
        let id = UUID()
        let polished = SemanticSearch.snapshot(id: id, userTitle: "  ", enhancedTitle: "Polish title",
                                               summary: "S", polished: "polished body", transcript: "raw body",
                                               annotation: "typed", place: "Lisbon", tags: ["x"])
        XCTAssertEqual(polished?.body, "polished body\ntyped", "polished beats raw; annotation appended")
        XCTAssertEqual(polished?.title, "Polish title", "a blank user title falls through to the polish's")
        let raw = SemanticSearch.snapshot(id: id, userTitle: "Mine", enhancedTitle: "Polish title", summary: nil,
                                          polished: nil, transcript: "raw body", annotation: nil,
                                          place: nil, tags: [])
        XCTAssertEqual(raw?.body, "raw body")
        XCTAssertEqual(raw?.title, "Mine")
        XCTAssertNil(SemanticSearch.snapshot(id: id, userTitle: nil, enhancedTitle: nil, summary: nil,
                                             polished: nil, transcript: "  \n", annotation: nil,
                                             place: nil, tags: []), "nothing to embed")
    }
}
