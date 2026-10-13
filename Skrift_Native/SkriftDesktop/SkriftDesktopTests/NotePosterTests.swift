import XCTest

/// Q391: a video block's poster is made off the main thread, once per file (Shared `NotePoster`),
/// so opening a note with a large video never decodes on the main thread.
final class NotePosterTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("NotePosterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testTheFirstAskReturnsAtOnceAndThePosterLandsLater() {
        let url = dir.appendingPathComponent("clip.mov")
        NoteAttachmentFixture.writeMovie(to: url, seconds: 1)
        let poster = NotePoster()
        let landed = expectation(forNotification: NotePoster.ready, object: nil) { ($0.object as? URL) == url }
        XCTAssertNil(poster.frame(for: url), "the first ask must not decode the file in line")
        wait(for: [landed], timeout: 20)
        let frame = poster.frame(for: url)
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame?.width, 640)
        XCTAssertEqual(frame?.height, 360)
    }

    func testTenDrawsOfOneVideoStartOneGeneration() {
        let url = dir.appendingPathComponent("clip.mov")
        NoteAttachmentFixture.writeMovie(to: url, seconds: 1)
        let poster = NotePoster()
        let landed = expectation(forNotification: NotePoster.ready, object: nil) { ($0.object as? URL) == url }
        for _ in 0..<10 { _ = poster.frame(for: url) }
        wait(for: [landed], timeout: 20)
        for _ in 0..<10 { XCTAssertNotNil(poster.frame(for: url)) }
        XCTAssertEqual(poster.generationCount, 1)
    }

    func testAFileThatIsNotAVideoIsTriedOnce() {
        let url = dir.appendingPathComponent("not-a-movie.mov")
        try? Data("hello".utf8).write(to: url)
        let poster = NotePoster()
        XCTAssertNil(poster.frame(for: url))
        let settle = expectation(description: "generation settles")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { settle.fulfill() }
        wait(for: [settle], timeout: 5)
        XCTAssertNil(poster.frame(for: url))
        XCTAssertEqual(poster.generationCount, 1, "a failed file is not retried on every draw")
    }
}
