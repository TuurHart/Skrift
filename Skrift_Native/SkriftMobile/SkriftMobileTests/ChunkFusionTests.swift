import XCTest
@testable import SkriftMobile

/// Wave-2 text-capture: chunk-seam fusion — cut at the last complete sentence,
/// re-transcribe the tail next chunk (no split/duplicated words at the seam).
final class ChunkFusionTests: XCTestCase {

    /// Build file-local words; the last char of a word ending a sentence carries
    /// terminating punctuation so `SentenceSnap.isSentenceEnd` fires.
    private func w(_ word: String, _ start: Double) -> WordTiming {
        WordTiming(word: word, start: start, end: start + 0.4)
    }

    func testKeepsCompleteSentencesAndReTranscribesTail() {
        // Two complete sentences then a partial third. Cut before the third.
        let words = [
            w("One", 0), w("two", 1), w("three.", 2),     // sentence A (start 0)
            w("Four", 3), w("five.", 4),                   // sentence B (start 3)
            w("Six", 5), w("seven", 6),                    // partial sentence C (start 5)
        ]
        let f = ChunkFusion.fuse(chunkWords: words, chunkStart: 0, chunkEnd: 7,
                                 isFinal: false, minProgress: 1)
        XCTAssertEqual(f.kept.map(\.word), ["One", "two", "three.", "Four", "five."])
        XCTAssertEqual(f.newFrontier, 5, accuracy: 0.0001)   // start of the partial sentence
    }

    func testFinalChunkKeepsEverything() {
        let words = [w("Last", 0), w("words", 1), w("here", 2)]   // no terminator, partial
        let f = ChunkFusion.fuse(chunkWords: words, chunkStart: 0, chunkEnd: 3,
                                 isFinal: true, minProgress: 1)
        XCTAssertEqual(f.kept.map(\.word), ["Last", "words", "here"])
        XCTAssertEqual(f.newFrontier, 3, accuracy: 0.0001)
    }

    func testEmptyChunkAdvancesPastSilence() {
        let f = ChunkFusion.fuse(chunkWords: [], chunkStart: 30, chunkEnd: 120,
                                 isFinal: false, minProgress: 1)
        XCTAssertEqual(f.kept, [])
        XCTAssertEqual(f.newFrontier, 120, accuracy: 0.0001)   // don't loop on silence
    }

    func testSingleRunOnSentenceKeepsAllToAvoidTinyStep() {
        // One giant sentence (no second start) → keep all, advance to chunk end
        // rather than fail to progress.
        let words = [w("a", 0), w("b", 1), w("c", 2), w("d", 3)]   // no terminators
        let f = ChunkFusion.fuse(chunkWords: words, chunkStart: 0, chunkEnd: 90,
                                 isFinal: false, minProgress: 45)
        XCTAssertEqual(f.kept.count, 4)
        XCTAssertEqual(f.newFrontier, 90, accuracy: 0.0001)
    }

    func testTinyAdvanceFallsBackToChunkEnd() {
        // The only later sentence boundary is very early; cutting there would
        // advance < minProgress, so keep all + advance to end instead.
        let words = [w("Hi.", 0)] + (1...20).map { w("word\($0)", Double($0)) }
        let f = ChunkFusion.fuse(chunkWords: words, chunkStart: 0, chunkEnd: 90,
                                 isFinal: false, minProgress: 45)
        XCTAssertEqual(f.newFrontier, 90, accuracy: 0.0001)
        XCTAssertEqual(f.kept.count, words.count)
    }
}
