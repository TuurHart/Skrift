import XCTest
@testable import SkriftMobile

/// The "split into N speakers" merge: collapse over-segmented slots to a target count by
/// merging the most voice-similar pair. Pure cosine over given embeddings.
final class SpeakerClusteringTests: XCTestCase {
    func testMergesPhantomIntoItsNearestVoice() {
        // 3 slots: 0 and 2 are the same voice (a phantom echo); 1 is distinct. Target 2 →
        // the echo (2) merges into 0; 1 stays separate.
        let emb: [Int: [Float]] = [0: [1, 0, 0], 1: [0, 1, 0], 2: [0.98, 0.1, 0]]
        let mapping = SpeakerClustering.merge(embeddings: emb, target: 2)
        XCTAssertEqual(mapping[2], 0, "the echo slot folds into its matching voice")
        XCTAssertEqual(mapping[0], 0)
        XCTAssertEqual(mapping[1], 1)
        XCTAssertEqual(Set(mapping.values).count, 2)   // exactly 2 speakers remain
    }

    func testForceToOne() {
        let emb: [Int: [Float]] = [0: [1, 0], 1: [0, 1], 2: [1, 1]]
        let mapping = SpeakerClustering.merge(embeddings: emb, target: 1)
        XCTAssertEqual(Set(mapping.values).count, 1)
    }

    func testNoMergeWhenAtOrUnderTarget() {
        let emb: [Int: [Float]] = [0: [1, 0], 1: [0, 1]]
        XCTAssertEqual(SpeakerClustering.merge(embeddings: emb, target: 3), [0: 0, 1: 1])
        XCTAssertEqual(SpeakerClustering.merge(embeddings: emb, target: 2), [0: 0, 1: 1])
    }

    func testKeepsLowerSlotIdAsSurvivor() {
        let emb: [Int: [Float]] = [0: [1, 0, 0], 1: [1, 0, 0], 2: [0, 1, 0]]   // 0,1 identical
        let mapping = SpeakerClustering.merge(embeddings: emb, target: 2)
        XCTAssertEqual(mapping[1], 0)   // merged into the lower id
        XCTAssertEqual(mapping[0], 0)
        XCTAssertEqual(mapping[2], 2)
    }
}
