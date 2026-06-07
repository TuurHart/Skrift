import XCTest
import Foundation

final class BPEMergeTests: XCTestCase {

    func testMergeSubwordsIntoWords() {
        let tokens = [
            RawToken(token: " hello", startTime: 0.0, endTime: 0.5),
            RawToken(token: " wor", startTime: 0.6, endTime: 0.8),
            RawToken(token: "ld", startTime: 0.8, endTime: 1.0),
        ]
        let words = BPEMerge.mergeBPETokens(tokens)
        XCTAssertEqual(words.map(\.text), ["hello", "world"])
        XCTAssertEqual(words[1].start, 0.6, accuracy: 0.0001)   // first sub-word's start
        XCTAssertEqual(words[1].end, 1.0, accuracy: 0.0001)     // last sub-word's end
    }

    func testFirstTokenWithoutLeadingSpaceStartsWord() {
        let words = BPEMerge.mergeBPETokens([
            RawToken(token: "Hi", startTime: 0, endTime: 0.2),
            RawToken(token: " there", startTime: 0.3, endTime: 0.6),
        ])
        XCTAssertEqual(words.map(\.text), ["Hi", "there"])
    }

    func testEmptyTokensSkipped() {
        let words = BPEMerge.mergeBPETokens([
            RawToken(token: "", startTime: 0, endTime: 0),
            RawToken(token: " a", startTime: 0, endTime: 0.1),
        ])
        XCTAssertEqual(words.map(\.text), ["a"])
    }

    func testPhantomGuard() {
        XCTAssertTrue(BPEMerge.shouldDropAsPhantom(rms: 0.5, wordCount: 0, isEmpty: true))     // empty
        XCTAssertTrue(BPEMerge.shouldDropAsPhantom(rms: 0.001, wordCount: 2, isEmpty: false))  // low + tiny
        XCTAssertFalse(BPEMerge.shouldDropAsPhantom(rms: 0.001, wordCount: 5, isEmpty: false)) // low but real length
        XCTAssertFalse(BPEMerge.shouldDropAsPhantom(rms: 0.5, wordCount: 1, isEmpty: false))   // loud + tiny = keep
        XCTAssertFalse(BPEMerge.shouldDropAsPhantom(rms: nil, wordCount: 1, isEmpty: false))   // unknown energy = keep
    }
}

final class ImageMarkersTests: XCTestCase {

    func testInsertsMarkerNearestWord() {
        let transcript = "hello world foo"
        let words = [
            TimedWord(text: "hello", start: 0.0, end: 0.4),
            TimedWord(text: "world", start: 1.0, end: 1.4),
            TimedWord(text: "foo", start: 2.0, end: 2.4),
        ]
        let manifest = [ImageManifestEntry(filename: "p1.jpg", offsetSeconds: 1.0)]  // nearest "world"
        let out = ImageMarkers.insert(transcript: transcript, words: words, manifest: manifest)

        XCTAssertTrue(out.contains("[[img_001]]"))
        let marker = out.range(of: "[[img_001]]")!
        let world = out.range(of: "world")!
        let foo = out.range(of: "foo")!
        XCTAssertTrue(world.upperBound <= marker.lowerBound)   // after "world"
        XCTAssertTrue(marker.upperBound <= foo.lowerBound)     // before "foo"
    }

    func testEmptyManifestLeavesTranscriptUntouched() {
        let words = [TimedWord(text: "hi", start: 0, end: 0.2)]
        XCTAssertEqual(ImageMarkers.insert(transcript: "hi", words: words, manifest: []), "hi")
    }
}
