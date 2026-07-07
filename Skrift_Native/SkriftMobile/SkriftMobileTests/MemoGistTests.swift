import XCTest
@testable import SkriftMobile

final class MemoGistTests: XCTestCase {

    // ── speaker headers ──

    func testStripSpeakerHeadersRemovesTurnMarkers() {
        let convo = "**Jack:** the sourdough theory again\n**Tuur:** you don't own a starter"
        let stripped = MemoGist.stripSpeakerHeaders(convo)
        XCTAssertEqual(stripped, "the sourdough theory again\nyou don't own a starter")
    }

    func testStripSpeakerHeadersLeavesBoldProse() {
        let text = "this is **really important** and stays"
        XCTAssertEqual(MemoGist.stripSpeakerHeaders(text), text)
    }

    // ── gist ──

    func testGistPrefersSummaryOverBody() {
        let gist = MemoGist.compose(title: "T", summary: "the summary", body: "the body",
                                    place: "Lisboa", people: ["Jack"], tags: ["idea"])
        XCTAssertTrue(gist.contains("the summary"))
        XCTAssertFalse(gist.contains("the body"))
        XCTAssertTrue(gist.contains("Lisboa"))
        XCTAssertTrue(gist.contains("Jack"))
    }

    func testGistFallsBackToLeadingBodyAndCaps() {
        let longBody = String(repeating: "woord ", count: 400)
        let gist = MemoGist.compose(title: nil, summary: nil, body: longBody,
                                    place: nil, people: [], tags: [])
        XCTAssertLessThanOrEqual(gist.count, MemoGist.gistMaxChars)
        XCTAssertTrue(gist.hasPrefix("woord"))
    }

    // ── chunker ──

    func testShortBodyIsOneChunkCoveringWholeText() {
        let body = "One sentence here. And a second one."
        let chunks = MemoGist.chunks(body: body)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].start, 0)
        XCTAssertEqual(chunks[0].end, body.count)
        XCTAssertEqual(chunks[0].text, body)
    }

    func testLongBodySplitsAtSentenceBoundariesWithOffsets() {
        let sentence = "Dit is een zin met precies acht woorden erin. "
        let body = String(repeating: sentence, count: 60).trimmingCharacters(in: .whitespaces)
        let chunks = MemoGist.chunks(body: body, targetWords: 50)
        XCTAssertGreaterThan(chunks.count, 1)
        // Chunks tile the body in order without gaps between start offsets.
        for pair in zip(chunks, chunks.dropFirst()) {
            XCTAssertLessThan(pair.0.start, pair.1.start)
            XCTAssertLessThanOrEqual(pair.0.end, pair.1.start + 1)
        }
        // Every chunk's text is findable at its recorded offsets.
        for chunk in chunks {
            let start = body.index(body.startIndex, offsetBy: chunk.start)
            let end = body.index(body.startIndex, offsetBy: chunk.end)
            XCTAssertEqual(String(body[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines),
                           chunk.text)
        }
        XCTAssertEqual(chunks.last!.end, body.count)
    }

    func testEmptyBodyProducesNoChunks() {
        XCTAssertTrue(MemoGist.chunks(body: "   \n ").isEmpty)
    }

    // ── hash ──

    func testTextHashIsStableAndContentSensitive() {
        XCTAssertEqual(MemoGist.textHash("abc"), MemoGist.textHash("abc"))
        XCTAssertNotEqual(MemoGist.textHash("abc"), MemoGist.textHash("abd"))
        XCTAssertEqual(MemoGist.textHash("abc").count, 16)
    }
}
