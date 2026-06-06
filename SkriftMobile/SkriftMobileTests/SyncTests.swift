import XCTest
@testable import SkriftMobile

final class UploadPayloadTests: XCTestCase {

    @MainActor
    func testMultipartHasExpectedPartsAndNeverSanitised() {
        let memo = Memo(
            id: UUID(),
            audioFilename: "memo_x.m4a",
            duration: 5,
            recordedAt: Date(),
            syncStatus: .waiting,
            transcript: "hello",
            transcriptStatus: .done,
            transcriptConfidence: 0.9,
            metadata: MemoMetadata(capturedAt: "2026-06-06T10:00:00.000Z", dayPeriod: .morning, tags: [])
        )
        let (body, contentType) = UploadPayload.build(
            memo: memo,
            audioData: Data("AUDIO".utf8),
            photos: [("photo_x_001.jpg", Data("IMG".utf8))]
        )
        let text = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        XCTAssertTrue(text.contains(#"name="files"; filename="memo_x.m4a""#))
        XCTAssertTrue(text.contains(#"name="metadata""#))
        XCTAssertTrue(text.contains(#""source":"mobile""#))
        XCTAssertTrue(text.contains(#"name="transcript""#))
        XCTAssertTrue(text.contains("hello"))
        XCTAssertTrue(text.contains(#"name="images"; filename="photo_x_001.jpg""#))
        XCTAssertFalse(text.contains("sanitised"))   // name-linking is Mac-side; never sent
    }

    @MainActor
    func testTranscriptOmittedWhenNotDone() {
        let memo = Memo(audioFilename: "memo_y.m4a", transcriptStatus: .pending)
        let (body, _) = UploadPayload.build(memo: memo, audioData: Data("A".utf8), photos: [])
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(#"name="transcript""#))
    }
}

final class SyncCoordinatorTests: XCTestCase {

    @MainActor
    func testUploadsWaitingMemoAndMarksSynced() async {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"
        let url = AppPaths.recordingsDirectory.appendingPathComponent(filename)
        FileManager.default.createFile(atPath: url.path, contents: Data("AUDIO".utf8))
        repo.insert(Memo(id: id, audioFilename: filename, duration: 3, recordedAt: Date(),
                         syncStatus: .waiting, transcript: "hi", transcriptStatus: .done, transcriptConfidence: 0.9))

        let mock = MockMacTransport()
        let synced = await SyncCoordinator(repository: repo, macTransport: mock, namesTransport: nil).syncAll()

        XCTAssertEqual(synced, 1)
        XCTAssertEqual(repo.memo(id: id)?.syncStatus, .synced)
        XCTAssertEqual(mock.uploadedBodies.count, 1)
    }

    @MainActor
    func testReconcileMarksSyncedByFilenameWithoutReupload() async {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"
        repo.insert(Memo(id: id, audioFilename: filename, syncStatus: .waiting))

        let mock = MockMacTransport()
        mock.knownFilenames = [filename]   // the Mac already has this one
        _ = await SyncCoordinator(repository: repo, macTransport: mock, namesTransport: nil).syncAll()

        XCTAssertEqual(repo.memo(id: id)?.syncStatus, .synced)
        XCTAssertEqual(mock.uploadedBodies.count, 0)
    }
}
