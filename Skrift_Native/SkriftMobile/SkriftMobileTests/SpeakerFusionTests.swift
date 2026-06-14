import XCTest
@testable import SkriftMobile

final class SpeakerFusionTests: XCTestCase {
    private func w(_ word: String, _ s: Double, _ e: Double) -> WordTiming { WordTiming(word: word, start: s, end: e) }

    func testTwoSpeakerSplit() {
        let words = [w("Hi", 0, 1), w("there", 1, 2), w("Hello", 3, 4), w("back", 4, 5)]
        let segs = [DiarizedSegment(speaker: 0, start: 0, end: 2.5),
                    DiarizedSegment(speaker: 1, start: 2.5, end: 5)]
        XCTAssertEqual(SpeakerFusion.turns(words: words, segments: segs),
                       [.init(speaker: 0, text: "Hi there"), .init(speaker: 1, text: "Hello back")])
    }

    /// The "But" blip: a 1-word island for spk1 between two spk0 turns folds into spk0.
    func testSmoothsOneWordIsland() {
        let words = [w("a", 0, 1), w("b", 1, 2), w("But", 2, 3), w("c", 3, 4), w("d", 4, 5)]
        let segs = [DiarizedSegment(speaker: 0, start: 0, end: 2),
                    DiarizedSegment(speaker: 1, start: 2, end: 3),
                    DiarizedSegment(speaker: 0, start: 3, end: 5)]
        XCTAssertEqual(SpeakerFusion.turns(words: words, segments: segs),
                       [.init(speaker: 0, text: "a b But c d")])
    }

    /// A phantom 1-word island flanked by DIFFERENT speakers folds into the nearer-in-time
    /// neighbor (the "Speaker 3: Oh" blip). Here "Oh" abuts spk0 → joins spk0.
    func testFoldsOneWordIslandToEarlierNeighbor() {
        let words = [w("a", 0, 1), w("b", 1, 2), w("Oh", 2.0, 2.2), w("c", 5, 6), w("d", 6, 7)]
        let segs = [DiarizedSegment(speaker: 0, start: 0, end: 2),
                    DiarizedSegment(speaker: 2, start: 2, end: 2.3),
                    DiarizedSegment(speaker: 1, start: 5, end: 7)]
        XCTAssertEqual(SpeakerFusion.turns(words: words, segments: segs),
                       [.init(speaker: 0, text: "a b Oh"), .init(speaker: 1, text: "c d")])
    }

    /// Same blip, but timed right before the later speaker → joins them instead.
    func testFoldsOneWordIslandToLaterNeighbor() {
        let words = [w("a", 0, 1), w("b", 1, 2), w("Oh", 4.8, 5.0), w("c", 5, 6), w("d", 6, 7)]
        let segs = [DiarizedSegment(speaker: 0, start: 0, end: 2),
                    DiarizedSegment(speaker: 2, start: 4.7, end: 5.0),
                    DiarizedSegment(speaker: 1, start: 5, end: 7)]
        XCTAssertEqual(SpeakerFusion.turns(words: words, segments: segs),
                       [.init(speaker: 0, text: "a b"), .init(speaker: 1, text: "Oh c d")])
    }

    /// A word in a gap between segments goes to the nearest segment's speaker.
    func testGapWordGoesToNearest() {
        let words = [w("x", 10, 11)]
        let segs = [DiarizedSegment(speaker: 0, start: 0, end: 2),
                    DiarizedSegment(speaker: 1, start: 9, end: 12)]
        XCTAssertEqual(SpeakerFusion.turns(words: words, segments: segs), [.init(speaker: 1, text: "x")])
    }

    /// minTurnWords=3: a 2-word wrong burst flanked by the SAME speaker on both sides is
    /// absorbed (reduces fragmentation / mid-run mis-attribution, #3/#4).
    func testSmoothsTwoWordBurstFlankedBySameSpeaker() {
        let words = [w("a", 0, 1), w("b", 1, 2), w("c", 2, 3),
                     w("X", 3, 4), w("Y", 4, 5),
                     w("d", 5, 6), w("e", 6, 7), w("f", 7, 8)]
        let segs = [DiarizedSegment(speaker: 0, start: 0, end: 3),
                    DiarizedSegment(speaker: 1, start: 3, end: 5),
                    DiarizedSegment(speaker: 0, start: 5, end: 8)]
        XCTAssertEqual(SpeakerFusion.turns(words: words, segments: segs),
                       [.init(speaker: 0, text: "a b c X Y d e f")])
    }

    /// Gap word goes to the segment with the NEAREST BOUNDARY, not the nearest midpoint:
    /// a word at a long segment's trailing edge must NOT be snapped to a short neighbour
    /// whose midpoint happens to be closer (#4).
    func testGapWordUsesNearestBoundaryNotMidpoint() {
        let words = [w("x", 10.1, 10.3)]   // midpoint 10.2, in the gap [10, 10.5]
        let segs = [DiarizedSegment(speaker: 0, start: 0, end: 10),     // boundary 0.2s away, midpoint 5.2s away
                    DiarizedSegment(speaker: 1, start: 10.5, end: 11.5)] // boundary 0.3s away, midpoint 0.8s away
        XCTAssertEqual(SpeakerFusion.turns(words: words, segments: segs), [.init(speaker: 0, text: "x")])
    }

    func testAttributedMarkdown() {
        let words = [w("Hi", 0, 1), w("Hello", 3, 4)]
        let segs = [DiarizedSegment(speaker: 0, start: 0, end: 2),
                    DiarizedSegment(speaker: 1, start: 2, end: 5)]
        let md = SpeakerFusion.attributedTranscript(words: words, segments: segs) { $0 == 0 ? "Tiuri" : "Speaker 2" }
        XCTAssertEqual(md, "**Tiuri:** Hi\n\n**Speaker 2:** Hello")
    }

    func testEmptyInputs() {
        XCTAssertEqual(SpeakerFusion.turns(words: [], segments: []), [])
        XCTAssertEqual(SpeakerFusion.turns(words: [w("a", 0, 1)], segments: []), [])
    }
}
