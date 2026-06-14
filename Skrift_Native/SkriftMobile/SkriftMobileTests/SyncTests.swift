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

    @MainActor
    func testWordTimingsAndDiarPartsIncludedWhenPresent() {
        let memo = Memo(audioFilename: "memo_c.m4a", transcript: "**Tuur:** hi", transcriptStatus: .done, transcriptConfidence: 0.9)
        let wt = Data(#"[{"word":"hi","start":0,"end":0.5}]"#.utf8)
        let diar = Data(#"{"segments":[{"speaker":0,"start":0,"end":1}],"slotNames":{"0":"Tuur"}}"#.utf8)
        let text = String(decoding: UploadPayload.build(
            memo: memo, audioData: Data("A".utf8), photos: [],
            wordTimingsJSON: wt, diarizationJSON: diar).body, as: UTF8.self)
        XCTAssertTrue(text.contains(#"name="wordTimings""#), "word-timings part attached")
        XCTAssertTrue(text.contains(#"name="diar""#), "diarization part attached")
        XCTAssertFalse(text.contains("sanitised"))
    }

    @MainActor
    func testWordTimingsAndDiarPartsOmittedWhenAbsent() {
        // No sidecars → byte-compatible with older builds (no new parts).
        let memo = Memo(audioFilename: "memo_p.m4a", transcript: "hi", transcriptStatus: .done, transcriptConfidence: 0.9)
        let text = String(decoding: UploadPayload.build(memo: memo, audioData: Data("A".utf8), photos: []).body, as: UTF8.self)
        XCTAssertFalse(text.contains(#"name="wordTimings""#))
        XCTAssertFalse(text.contains(#"name="diar""#))
    }

    @MainActor
    func testTitleRidesInMetadataWhenSet() {
        let titled = Memo(audioFilename: "m.m4a", title: "Harbor renovation ideas", transcriptStatus: .pending)
        let withTitle = String(decoding: UploadPayload.build(memo: titled, audioData: Data("A".utf8), photos: []).body, as: UTF8.self)
        XCTAssertTrue(withTitle.contains(#""title":"Harbor renovation ideas""#),
                      "phone-set title should ride in the upload metadata")

        let untitled = Memo(audioFilename: "m.m4a", transcriptStatus: .pending)
        let noTitle = String(decoding: UploadPayload.build(memo: untitled, audioData: Data("A".utf8), photos: []).body, as: UTF8.self)
        XCTAssertFalse(noTitle.contains(#""title":"#), "no title key when unset")
    }

    @MainActor
    func testSignificanceRidesInMetadataWhenSet() {
        let rated = Memo(audioFilename: "m.m4a", transcriptStatus: .pending, significance: 0.5)
        let withSig = String(decoding: UploadPayload.build(memo: rated, audioData: Data("A".utf8), photos: []).body, as: UTF8.self)
        XCTAssertTrue(withSig.contains(#""significance":0.5"#), "rating should ride in the upload metadata")

        // Unrated (0) memos aren't uploaded at all, and carry no significance key.
        let unrated = Memo(audioFilename: "m.m4a", transcriptStatus: .pending, significance: 0)
        let noSig = String(decoding: UploadPayload.build(memo: unrated, audioData: Data("A".utf8), photos: []).body, as: UTF8.self)
        XCTAssertFalse(noSig.contains(#""significance":"#), "no significance key when unrated")
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
                         syncStatus: .waiting, transcript: "hi", transcriptStatus: .done,
                         transcriptConfidence: 0.9, significance: 0.7))   // flagged → eligible

        let mock = MockMacTransport()
        let synced = await SyncCoordinator(repository: repo, macTransport: mock, namesTransport: nil).syncAll()

        XCTAssertEqual(synced, 1)
        XCTAssertEqual(repo.memo(id: id)?.syncStatus, .synced)
        XCTAssertEqual(mock.uploadedBodies.count, 1)
    }

    /// Flag-to-send: an unrated memo (significance 0) is NOT uploaded — it stays on
    /// the phone, still `waiting`, until the user rates it.
    @MainActor
    func testZeroSignificanceMemoIsNotUploaded() async {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"
        let url = AppPaths.recordingsDirectory.appendingPathComponent(filename)
        FileManager.default.createFile(atPath: url.path, contents: Data("AUDIO".utf8))
        repo.insert(Memo(id: id, audioFilename: filename, duration: 3, recordedAt: Date(),
                         syncStatus: .waiting, transcript: "hi", transcriptStatus: .done,
                         transcriptConfidence: 0.9, significance: 0))   // unrated → gated out

        let mock = MockMacTransport()
        let synced = await SyncCoordinator(repository: repo, macTransport: mock, namesTransport: nil).syncAll()

        XCTAssertEqual(synced, 0)
        XCTAssertEqual(repo.memo(id: id)?.syncStatus, .waiting)
        XCTAssertEqual(mock.uploadedBodies.count, 0)
    }

    /// A capture whose dictated voice note is still transcribing must NOT upload —
    /// the annotation IS the body for captures, so an early upload would drop the
    /// spoken part. It uploads on the next sync once the text has landed.
    @MainActor
    func testCaptureHeldWhileDictationTranscribing() async {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        repo.insert(Memo(id: id, audioFilename: "", duration: 0, recordedAt: Date(),
                         syncStatus: .waiting, transcript: nil, transcriptStatus: .transcribing,
                         significance: 0.6,
                         sharedContent: SharedContent(type: .url, url: "https://a.com", urlTitle: "A",
                                                      text: nil, fileName: nil, mimeType: nil),
                         annotationText: "typed"))

        let mock = MockMacTransport()
        let coordinator = SyncCoordinator(repository: repo, macTransport: mock, namesTransport: nil)
        let held = await coordinator.syncAll()
        XCTAssertEqual(held, 0)
        XCTAssertEqual(repo.memo(id: id)?.syncStatus, .waiting, "stays waiting, not dropped")

        // Dictation lands → next sync uploads it.
        repo.memo(id: id)?.transcriptStatus = .done
        repo.save()
        let synced = await coordinator.syncAll()
        XCTAssertEqual(synced, 1)
        XCTAssertEqual(repo.memo(id: id)?.syncStatus, .synced)
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
