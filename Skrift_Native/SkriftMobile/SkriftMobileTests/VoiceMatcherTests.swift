import XCTest
@testable import SkriftMobile

/// The pure identity-match logic (cosine + best-match over multi-embedding voiceprints).
/// The embedding EXTRACTION is device-only; this is the deterministic part the auto-match
/// hinges on, so it's covered here on the sim. Thresholds mirror the spike's measurements.
final class VoiceMatcherTests: XCTestCase {
    private func emb(_ v: [Float]) -> VoiceEmbedding { VoiceEmbedding(vector: v.map(Double.init)) }
    private func person(_ name: String, _ vectors: [[Float]]) -> Person {
        Person(canonical: "[[\(name)]]", voiceEmbeddings: vectors.map { emb($0) }, lastModifiedAt: "2026-06-09T00:00:00.000Z")
    }

    func testCosineIdenticalOrthogonalOpposite() {
        XCTAssertEqual(VoiceMatcher.cosine([1, 0, 0], [1, 0, 0]), 1, accuracy: 1e-5)
        XCTAssertEqual(VoiceMatcher.cosine([1, 0], [0, 1]), 0, accuracy: 1e-5)
        XCTAssertEqual(VoiceMatcher.cosine([1, 1], [-1, -1]), -1, accuracy: 1e-5)
    }

    /// Cosine is magnitude-invariant (embeddings aren't unit-norm in practice).
    func testCosineIgnoresMagnitude() {
        XCTAssertEqual(VoiceMatcher.cosine([2, 0, 0], [9, 0, 0]), 1, accuracy: 1e-5)
    }

    /// A dimension mismatch (e.g. a legacy/foreign embedding) never matches.
    func testCosineShapeMismatchIsZero() {
        XCTAssertEqual(VoiceMatcher.cosine([1, 2, 3], [1, 2]), 0)
        XCTAssertEqual(VoiceMatcher.cosine([], [1]), 0)
    }

    func testBestMatchPicksHighestPersonAboveThreshold() {
        let tiuri = person("Tiuri", [[1, 0, 0]])
        let jane = person("Jane", [[0, 1, 0]])
        let query: [Float] = [0.9, 0.1, 0]   // closest to Tiuri
        let match = VoiceMatcher.bestMatch(embedding: query, people: [jane, tiuri], threshold: 0.5)
        XCTAssertEqual(match?.person.displayName, "Tiuri")
        XCTAssertGreaterThan(match?.similarity ?? 0, 0.9)
    }

    func testBestMatchReturnsNilBelowThreshold() {
        let tiuri = person("Tiuri", [[1, 0, 0]])
        // ~63° away → cosine ~0.45, below 0.5.
        let query: [Float] = [0.45, 0.89, 0]
        XCTAssertNil(VoiceMatcher.bestMatch(embedding: query, people: [tiuri], threshold: 0.5))
    }

    /// Multi-embedding: match if ANY of a person's voiceprints is close (max-cosine), so a
    /// phone-mic enrollment still matches an AirPods recording and vice-versa.
    func testMultiEmbeddingMatchesOnAnyVoiceprint() {
        let tiuri = person("Tiuri", [[0, 1, 0], [1, 0, 0]])   // two distinct conditions
        let query: [Float] = [0.98, 0.2, 0]                   // matches the 2nd only
        let match = VoiceMatcher.bestMatch(embedding: query, people: [tiuri], threshold: 0.5)
        XCTAssertEqual(match?.person.displayName, "Tiuri")
    }

    func testPeopleWithoutVoiceprintsAreSkipped() {
        let noVoice = Person(canonical: "[[Bob]]", lastModifiedAt: "2026-06-09T00:00:00.000Z")
        XCTAssertNil(VoiceMatcher.bestMatch(embedding: [1, 0, 0], people: [noVoice], threshold: 0.5))
    }

    func testThresholdDefaultsTo0_5AndReadsOverride() {
        UserDefaults.standard.removeObject(forKey: "voiceMatchThreshold")
        XCTAssertEqual(VoiceMatcher.threshold, 0.5, accuracy: 1e-6)
        UserDefaults.standard.set(0.62, forKey: "voiceMatchThreshold")
        XCTAssertEqual(VoiceMatcher.threshold, 0.62, accuracy: 1e-6)
        UserDefaults.standard.removeObject(forKey: "voiceMatchThreshold")
    }
}
