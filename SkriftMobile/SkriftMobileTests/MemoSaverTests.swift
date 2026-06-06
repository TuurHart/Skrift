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

    @MainActor
    func testPhotosBuildManifestAndInjectMarkers() async {
        let repo = NotesRepository(inMemory: true)
        let saver = MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: "one two three four five six"),
            wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true))
        )

        let audio = FileManager.default.temporaryDirectory.appendingPathComponent("rec_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: audio.path, contents: Data())
        let photo = FileManager.default.temporaryDirectory.appendingPathComponent("cap_\(UUID().uuidString).jpg")
        FileManager.default.createFile(atPath: photo.path, contents: Data([0xFF, 0xD8, 0xFF]))

        let id = await saver.saveAndTranscribe(tempURL: audio, duration: 2.0, photos: [(url: photo, offset: 0.35)])

        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.metadata?.imageManifest?.count, 1)
        XCTAssertEqual(memo?.metadata?.imageManifest?.first?.filename, "photo_\(id.uuidString)_001.jpg")
        XCTAssertEqual(memo?.transcriptMarkersInjected, true)
        XCTAssertTrue(memo?.transcript?.contains("[[img_001]]") ?? false, "marker not injected into transcript")

        let movedPhoto = AppPaths.recordingsDirectory.appendingPathComponent("photo_\(id.uuidString)_001.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedPhoto.path))
    }
}
