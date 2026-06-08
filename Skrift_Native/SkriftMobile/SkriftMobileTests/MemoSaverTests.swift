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
            wordTimings: WordTimingsStore(directory: sidecarDir),
            metadataProvider: MockMetadataService()
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

    /// Append a follow-up recording to an existing memo: the new transcript is
    /// appended, the memo becomes user-edited (Mac trusts the combined text), and
    /// the clip is consumed. The placeholder audio can't be merged here, so the base
    /// audio is kept — the real audio merge is device-owed (like all real audio).
    @MainActor
    func testAppendRecordingAppendsTextAndMarksUserEdited() async {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"
        try? FileManager.default.createDirectory(at: AppPaths.recordingsDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: AppPaths.recordingsDirectory.appendingPathComponent(filename).path,
                                       contents: Data("AUDIO".utf8))
        repo.insert(Memo(id: id, audioFilename: filename, duration: 3, recordedAt: Date(),
                         transcript: "first part", transcriptStatus: .done, transcriptConfidence: 0.9))

        let saver = MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: "second part"),
            wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
            metadataProvider: MockMetadataService()
        )
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("add_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: temp.path, contents: Data("MORE".utf8))

        await saver.appendRecordingAsync(to: id, tempURL: temp, duration: 2)

        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.transcript, "first part\n\nsecond part")
        XCTAssertEqual(memo?.transcriptUserEdited, true)
        XCTAssertEqual(memo?.transcriptStatus, .done)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path), "appended clip should be consumed")
    }

    @MainActor
    func testPhotosBuildManifestAndInjectMarkers() async {
        let repo = NotesRepository(inMemory: true)
        let saver = MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: "one two three four five six"),
            wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
            metadataProvider: MockMetadataService()
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

    @MainActor
    func testImportAudioCopiesFilePreservesExtensionAndCreatesMemo() throws {
        let repo = NotesRepository(inMemory: true)
        let saver = MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: "imported audio"),
            wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
            metadataProvider: MockMetadataService()
        )

        // An external "shared" audio file — a non-m4a extension to prove the
        // import preserves it (so the Mac sees the right format).
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared_\(UUID().uuidString).wav")
        FileManager.default.createFile(atPath: source.path, contents: Data([0x52, 0x49, 0x46, 0x46]))

        let id = try XCTUnwrap(saver.importAudio(from: source))

        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.audioFilename, "memo_\(id.uuidString).wav")  // extension preserved
        XCTAssertEqual(memo?.syncStatus, .waiting)
        let copied = AppPaths.recordingsDirectory.appendingPathComponent("memo_\(id.uuidString).wav")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path), "imported audio not copied into recordings")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "import must copy, not move the source")
    }

    @MainActor
    func testMetadataCaptureMergesAndPreservesManifest() async {
        let repo = NotesRepository(inMemory: true)
        let captured = MemoMetadata(
            capturedAt: "2026-06-06T10:00:00.000Z",
            location: LocationInfo(latitude: 38.7, longitude: -9.1, placeName: "Lisbon"),
            dayPeriod: .morning,
            steps: 500,
            tags: []
        )
        let saver = MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: "one two three four five six"),
            wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
            metadataProvider: MockMetadataService(captured)
        )

        let audio = FileManager.default.temporaryDirectory.appendingPathComponent("rec_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: audio.path, contents: Data())
        let photo = FileManager.default.temporaryDirectory.appendingPathComponent("cap_\(UUID().uuidString).jpg")
        FileManager.default.createFile(atPath: photo.path, contents: Data([0xFF, 0xD8, 0xFF]))

        let id = await saver.saveAndTranscribe(tempURL: audio, duration: 2.0, photos: [(url: photo, offset: 0.35)])

        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.metadata?.location?.placeName, "Lisbon")   // captured context merged in
        XCTAssertEqual(memo?.metadata?.steps, 500)
        XCTAssertEqual(memo?.metadata?.dayPeriod, .morning)
        XCTAssertEqual(memo?.metadata?.imageManifest?.count, 1)         // photo manifest preserved
        XCTAssertTrue(memo?.transcript?.contains("[[img_001]]") ?? false)
    }
}
