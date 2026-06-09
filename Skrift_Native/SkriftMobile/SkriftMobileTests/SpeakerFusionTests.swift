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

    /// A word in a gap between segments goes to the nearest segment's speaker.
    func testGapWordGoesToNearest() {
        let words = [w("x", 10, 11)]
        let segs = [DiarizedSegment(speaker: 0, start: 0, end: 2),
                    DiarizedSegment(speaker: 1, start: 9, end: 12)]
        XCTAssertEqual(SpeakerFusion.turns(words: words, segments: segs), [.init(speaker: 1, text: "x")])
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
