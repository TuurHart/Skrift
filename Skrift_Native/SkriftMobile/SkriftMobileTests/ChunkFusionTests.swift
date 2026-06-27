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
        // advance < minProgress, AND rewinding the last word still wouldn't make
        // minProgress (the words are bunched in the first 20s of a 90s budget), so
        // keep all + advance to end to guarantee forward motion.
        let words = [w("Hi.", 0)] + (1...20).map { w("word\($0)", Double($0)) }
        let f = ChunkFusion.fuse(chunkWords: words, chunkStart: 0, chunkEnd: 90,
                                 isFinal: false, minProgress: 45)
        XCTAssertEqual(f.newFrontier, 90, accuracy: 0.0001)
        XCTAssertEqual(f.kept.count, words.count)
    }

    func testRunOnSentenceRewindsTrailingWordInsteadOfKeepingTruncatedCut() {
        // Regression (device bug 2026-06-27): a long run-on sentence fills the
        // chunk so the last sentence start is too far back (< minProgress advance)
        // → fallback. The OLD fallback kept every word up to the arbitrary 60s cut,
        // which lands mid-word — the truncated boundary word ("session" → "summer")
        // was mis-decoded, lost its period, and merged two sentences. The fix
        // rewinds to the last word's start so the next chunk re-transcribes it
        // whole: that final word must NOT be kept here, and the frontier must be
        // its start (not the raw chunkEnd).
        let words = [w("The", 1)] + (2...58).map { w("word\($0)", Double($0)) }
            + [w("session", 59)]   // straddles the chunkEnd cut → must be redone next chunk
        let f = ChunkFusion.fuse(chunkWords: words, chunkStart: 0, chunkEnd: 60,
                                 isFinal: false, minProgress: 30)
        XCTAssertEqual(f.kept.last?.word, "word58")           // truncated word dropped
        XCTAssertFalse(f.kept.contains { $0.word == "session" })
        XCTAssertEqual(f.newFrontier, 59, accuracy: 0.0001)   // next chunk re-transcribes it whole
    }

    func testRunOnSentenceWithFewWordsStillFallsBackToCut() {
        // Degenerate: a handful of words bunched early, then the chunk is mostly
        // silence. Rewinding the last word wouldn't make minProgress, so accept the
        // cut rather than risk a no-progress loop.
        let words = [w("a", 0), w("b", 1), w("c", 2)]
        let f = ChunkFusion.fuse(chunkWords: words, chunkStart: 0, chunkEnd: 60,
                                 isFinal: false, minProgress: 30)
        XCTAssertEqual(f.kept.count, 3)
        XCTAssertEqual(f.newFrontier, 60, accuracy: 0.0001)
    }
}
