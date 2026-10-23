import XCTest
@testable import SkriftMobile

/// Q479 (C149): an interruption (call, Siri, alarm) is a pause. The recording clock stops while
/// the system owns the mic and photo offsets read that clock, so a picture snapped after a call
/// lands where it was taken. Fixture: corpus `pic-after-interruption`.
final class InterruptionClockTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testInterruptionStopsTheClock() {
        var clock = RecordingCore.Clock()
        clock.start(at: at(0))
        XCTAssertEqual(clock.reading(at: at(3)), 3, accuracy: 1e-9)
        clock.setInterrupted(true, at: at(3))
        XCTAssertEqual(clock.reading(at: at(43)), 3, accuracy: 1e-9, "a 40 s call adds nothing")
        clock.setInterrupted(false, at: at(43))
        XCTAssertEqual(clock.reading(at: at(45)), 5, accuracy: 1e-9)
    }

    func testPauseAndInterruptionOverlapRunsOnlyWhenBothRelease() {
        var clock = RecordingCore.Clock()
        clock.start(at: at(0))
        clock.setPaused(true, at: at(2))
        clock.setInterrupted(true, at: at(3))
        clock.setPaused(false, at: at(5))       // resume tapped mid-call: still the system's mic
        XCTAssertEqual(clock.reading(at: at(9)), 2, accuracy: 1e-9)
        clock.setInterrupted(false, at: at(10))
        XCTAssertEqual(clock.reading(at: at(11)), 3, accuracy: 1e-9)
        clock.setInterrupted(true, at: at(11))
        clock.setPaused(true, at: at(12))       // paused during a second call
        clock.setInterrupted(false, at: at(20)) // the call ends, the user's pause still holds
        XCTAssertEqual(clock.reading(at: at(30)), 3, accuracy: 1e-9)
    }

    func testRepeatedTogglesAreIdempotentAndStopBanks() {
        var clock = RecordingCore.Clock()
        clock.start(at: at(0))
        clock.setInterrupted(false, at: at(1))  // an `.ended` with no `.began` changes nothing
        clock.setInterrupted(true, at: at(2))
        clock.setInterrupted(true, at: at(4))   // a second `.began` doesn't double-bank
        clock.setInterrupted(false, at: at(6))
        clock.stop(at: at(7))
        XCTAssertEqual(clock.reading(at: at(100)), 3, accuracy: 1e-9, "stopped = frozen")
        clock.start(at: at(200))
        XCTAssertEqual(clock.reading(at: at(201)), 1, accuracy: 1e-9, "a new take starts from 0")
    }

    // MARK: - corpus `pic-after-interruption`

    private struct Fixture: Decodable {
        struct Metadata: Decodable { let imageManifest: [ImageManifestEntry] }
        struct Expect: Decodable { let callStartsAt: Double; let callSeconds: Double; let wallClockOffset: Double }
        let transcript: String
        let metadata: Metadata
        let expect: Expect
    }

    private func fixture() throws -> (Fixture, [WordTiming], String) {
        let dir = CorpusSeed.fixtureRoot(file: #filePath).appendingPathComponent("notes/pic-after-interruption")
        let note = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: dir.appendingPathComponent("note.json")))
        let words = try JSONDecoder().decode([WordTiming].self, from: Data(contentsOf: dir.appendingPathComponent("word_timings.json")))
        let body = try String(contentsOf: dir.appendingPathComponent("expect_body.txt"), encoding: .utf8)
        return (note, words, body)
    }

    func testThePictureAfterTheCallLandsWhereItWasTaken() throws {
        let (note, words, expected) = try fixture()
        let manifest = try XCTUnwrap(note.metadata.imageManifest.first)

        // Replay the take on the clock: speech, the call, speech, the shutter.
        var clock = RecordingCore.Clock()
        clock.start(at: at(0))
        clock.setInterrupted(true, at: at(note.expect.callStartsAt))
        clock.setInterrupted(false, at: at(note.expect.callStartsAt + note.expect.callSeconds))
        let shutterWall = manifest.offsetSeconds + note.expect.callSeconds
        XCTAssertEqual(shutterWall, note.expect.wallClockOffset, accuracy: 0.01)
        XCTAssertEqual(clock.reading(at: at(shutterWall)), manifest.offsetSeconds, accuracy: 0.01,
                       "the offset a photo stores is the recording clock, not the wall clock")

        func body(_ offset: Double) -> String {
            var entry = manifest
            entry.offsetSeconds = offset
            return BodyV2.committed(.init(text: note.transcript, words: words, manifest: [entry], source: .speech))
        }
        XCTAssertEqual(body(clock.reading(at: at(shutterWall))), expected)
        XCTAssertNotEqual(body(note.expect.wallClockOffset), expected,
                          "the wall-clock offset would put the picture after the last sentence")
        XCTAssertTrue(body(note.expect.wallClockOffset).hasSuffix("[[img_001]]"))
    }
}
