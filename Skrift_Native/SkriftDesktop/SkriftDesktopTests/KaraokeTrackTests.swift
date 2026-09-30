import XCTest
import Foundation

/// Q82 group 6: "which word is playing" is ONE shared rule (`KaraokeTrack`). This file is
/// identical in the phone and Mac test targets; the same input must give the same answers
/// on both, and it does because both compile the one `Shared/Pipeline` source.
final class KaraokeTrackTests: XCTestCase {

    private func timings(_ pairs: [(String, Double)]) -> [WordTiming] {
        pairs.map { WordTiming(word: $0.0, start: $0.1, end: $0.1 + 0.4) }
    }

    func testExactWhenShownWordsAreTheTimedWords() {
        let t = timings([("hello", 0), ("world", 1), ("this", 2)])
        let track = KaraokeTrack(displayedWords: ["Hello,", "world.", "This"], timings: t, duration: 10)
        XCTAssertEqual(track.basis, .exact)
        XCTAssertNil(track.activeIndex(at: -0.1))
        XCTAssertEqual(track.activeIndex(at: 0), 0)
        XCTAssertEqual(track.activeIndex(at: 1.5), 1)
        XCTAssertEqual(track.activeIndex(at: 99), 2)
        XCTAssertEqual(track.seekTime(forWord: 1), 1)
        XCTAssertNil(track.seekTime(forWord: 3))
        XCTAssertNil(track.seekTime(forWord: -1))
    }

    /// A copy-edited body: the playing word and the tap target both come from the alignment,
    /// so tapping the word that lights up seeks to it (the phone used to seek by proportion).
    func testAlignedWhenTheBodyWasCopyEdited() {
        let t = timings([("um", 0), ("the", 1), ("meeting", 2), ("you", 3),
                         ("know", 4), ("went", 5), ("really", 6), ("well", 7)])
        let track = KaraokeTrack(displayedWords: ["the", "meeting", "went", "well"], timings: t, duration: 8)
        XCTAssertEqual(track.basis, .aligned)
        XCTAssertEqual(track.starts, [1, 2, 5, 7])
        XCTAssertNil(track.activeIndex(at: 0.5))
        XCTAssertEqual(track.activeIndex(at: 4.5), 1, "still 'meeting' until 'went' starts")
        XCTAssertEqual(track.activeIndex(at: 5.2), 2)
        XCTAssertEqual(track.seekTime(forWord: 2), 5)
    }

    func testProportionalWhenNothingAlignsOrThereAreNoTimings() {
        let words = ["completely", "unrelated", "prose", "about"]
        let t = timings([("hello", 0), ("world", 1), ("this", 2), ("is", 3), ("great", 4)])
        for track in [KaraokeTrack(displayedWords: words, timings: t, duration: 8),
                      KaraokeTrack(displayedWords: words, timings: [], duration: 8)] {
            XCTAssertEqual(track.basis, .proportional)
            XCTAssertEqual(track.activeIndex(at: 0), 0)
            XCTAssertEqual(track.activeIndex(at: 4.1), 2)
            XCTAssertEqual(track.activeIndex(at: 99), 3)
            XCTAssertEqual(track.seekTime(forWord: 2), 4)
        }
        XCTAssertNil(KaraokeTrack(displayedWords: words, timings: [], duration: 0).seekTime(forWord: 1),
                     "no timings and no duration: nowhere to seek")
    }

    func testRolesPaintTheSameOnBothApps() {
        XCTAssertEqual(KaraokeRole.of(word: 0, active: nil), .upcoming)
        XCTAssertEqual(KaraokeRole.of(word: 0, active: 2), .read)
        XCTAssertEqual(KaraokeRole.of(word: 2, active: 2), .playing)
        XCTAssertEqual(KaraokeRole.of(word: 3, active: 2), .upcoming)
    }

    func testCacheRebuildsOnlyWhenTheBodyChanges() {
        let cache = KaraokeTrackCache()
        let t = timings([("a", 0), ("b", 1)])
        let first = cache.track(displayedWords: ["a", "b"], timings: t, duration: 2)
        let again = cache.track(displayedWords: ["a", "b"], timings: t, duration: 2)
        XCTAssertEqual(first, again)
        let edited = cache.track(displayedWords: ["a"], timings: t, duration: 2)
        XCTAssertEqual(edited.wordCount, 1)
    }
}
