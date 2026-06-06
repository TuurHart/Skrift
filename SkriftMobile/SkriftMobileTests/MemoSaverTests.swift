import XCTest
@testable import SkriftMobile

final class MemoSaverTests: XCTestCase {

    @MainActor
    func testSaveAndTranscribeFillsMemoAndSidecar() async {
        let repo = NotesRepository(inMemory: true)
        let sidecarDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)
        let saver = MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: "hello world from skrift"),
            wordTimings: WordTimingsStore(directory: sidecarDir)
        )

        // A placeholder temp audio file for the save to move into place.
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: temp.path, contents: Data())

        let id = await saver.saveAndTranscribe(tempURL: temp, duration: 3.2)

        let memo = repo.memo(id: id)
        XCTAssertNotNil(memo)
        XCTAssertEqual(memo?.transcript, "hello world from skrift")
        XCTAssertEqual(memo?.transcriptStatus, .done)
        XCTAssertEqual(memo?.transcriptConfidence, 1.0)
        XCTAssertEqual(memo?.duration, 3.2)
        XCTAssertEqual(memo?.audioFilename, "memo_\(id.uuidString).m4a")

        let timings = WordTimingsStore(directory: sidecarDir).load(for: id)
        XCTAssertEqual(timings?.count, 4)   // four words
    }
}
