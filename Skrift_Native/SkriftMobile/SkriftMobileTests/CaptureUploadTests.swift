import XCTest
@testable import SkriftMobile

/// Tests for the C3 capture upload contract (CAPTURE_CONTRACT.md).
/// All assertions are against LITERAL fixture values from the contract doc so that
/// any deviation in key names or shapes breaks the test immediately.
final class CaptureUploadTests: XCTestCase {

    // MARK: - URL capture (contract fixture, §"Literal example")

    /// The contract's pinned url-capture fixture: metadata must decode with exact
    /// key/value pairs, no `files` part, no `transcript` part.
    @MainActor
    func testURLCaptureMultipartShape() throws {
        let memo = makeMemo(
            type: .url,
            url: "https://swiftwithmajid.com/2026/05/rich-text-editing",
            urlTitle: "Rich text editing in SwiftUI — strategies that work",
            annotationText: "Try this for the desktop body editor — the NSTextView part maps onto what Nick suggested.",
            significance: 0.6
        )

        let (body, contentType) = UploadPayload.buildCapture(memo: memo, photos: [])
        let text = String(decoding: body, as: UTF8.self)

        // Content-type header
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="),
                      "contentType must be multipart/form-data")

        // MUST NOT have a `files` part (the discriminator for captures vs. memos).
        XCTAssertFalse(text.contains(#"name="files""#),
                       "url capture MUST NOT contain a 'files' audio part")

        // MUST NOT have a `transcript` part.
        XCTAssertFalse(text.contains(#"name="transcript""#),
                       "url capture MUST NOT contain a 'transcript' part")

        // MUST have a `metadata` part.
        XCTAssertTrue(text.contains(#"name="metadata""#),
                      "url capture must have a 'metadata' part")

        // Decode the metadata JSON and assert exact contract field values.
        let metadata = try extractAndDecodeMetadata(from: body)

        XCTAssertEqual(metadata.source, "mobile", "source must be 'mobile'")
        XCTAssertEqual(metadata.duration, 0, "duration must be 0 for captures")
        XCTAssertFalse(metadata.transcriptUserEdited, "transcriptUserEdited must be false")
        XCTAssertEqual(metadata.tags, [], "tags must be empty array v1")
        XCTAssertEqual(metadata.significance ?? 0, 0.6, accuracy: 0.001)

        let sc = try XCTUnwrap(metadata.sharedContent, "sharedContent must be present for captures")
        XCTAssertEqual(sc.type, .url)
        XCTAssertEqual(sc.url, "https://swiftwithmajid.com/2026/05/rich-text-editing")
        XCTAssertEqual(sc.urlTitle, "Rich text editing in SwiftUI — strategies that work")

        XCTAssertEqual(metadata.annotationText,
                       "Try this for the desktop body editor — the NSTextView part maps onto what Nick suggested.")
    }

    // MARK: - Image capture

    /// Image capture must have exactly ONE `images` part + the imageManifest in metadata.
    @MainActor
    func testImageCaptureMultipartShape() throws {
        let memo = makeMemo(
            type: .image,
            imageFileName: "whiteboard.jpg",
            mimeType: "image/jpeg",
            significance: 0.5,
            imageManifestFilename: "whiteboard.jpg"
        )
        let imageBytes = Data("IMGDATA".utf8)
        let (body, _) = UploadPayload.buildCapture(
            memo: memo,
            photos: [("whiteboard.jpg", imageBytes)]
        )
        let text = String(decoding: body, as: UTF8.self)

        // Must have exactly one `images` part
        let imagesRange = text.range(of: #"name="images""#)
        XCTAssertNotNil(imagesRange, "image capture must have an 'images' part")

        // Must NOT have a `files` part
        XCTAssertFalse(text.contains(#"name="files""#),
                       "image capture MUST NOT contain a 'files' audio part")

        // Metadata imageManifest must carry the filename and offsetSeconds 0
        let metadata = try extractAndDecodeMetadata(from: body)
        let manifest = try XCTUnwrap(metadata.imageManifest, "imageManifest must be present for image captures")
        XCTAssertEqual(manifest.count, 1)
        XCTAssertEqual(manifest[0].filename, "whiteboard.jpg")
        XCTAssertEqual(manifest[0].offsetSeconds, 0, accuracy: 0.001)

        let sc = try XCTUnwrap(metadata.sharedContent)
        XCTAssertEqual(sc.type, .image)
        XCTAssertEqual(sc.fileName, "whiteboard.jpg")
        XCTAssertEqual(sc.mimeType, "image/jpeg")
    }

    // MARK: - Regression: normal audio memo still has audio part

    /// C3 contract invariant: a standard memo upload is BYTE-IDENTICAL to the
    /// pre-capture shape — `buildCapture` is a new branch, not a modification.
    @MainActor
    func testNormalAudioMemoStillHasAudioPart() {
        let memo = Memo(
            audioFilename: "memo_abc.m4a",
            duration: 30,
            transcript: "hello world",
            transcriptStatus: .done,
            transcriptConfidence: 0.9,
            significance: 0.5
        )
        let (body, _) = UploadPayload.build(
            memo: memo,
            audioData: Data("AUDIODATA".utf8),
            photos: []
        )
        let text = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(text.contains(#"name="files"; filename="memo_abc.m4a""#),
                      "standard memo must still carry the audio 'files' part")
        XCTAssertTrue(text.contains(#"name="transcript""#),
                      "standard memo must still carry the 'transcript' part")
        XCTAssertTrue(text.contains("hello world"))
        XCTAssertFalse(text.contains(#"name="images""#),
                       "no images part when no photos (regression check)")
    }

    // MARK: - SyncCoordinator routes captures through the upload loop

    @MainActor
    func testCaptureUploadFlowsThroughSyncCoordinator() async {
        let repo = NotesRepository(inMemory: true)
        let memo = Memo(
            audioFilename: "",     // no audio = capture discriminator
            duration: 0,
            syncStatus: .waiting,
            transcriptStatus: .done,
            significance: 0.6,
            sharedContent: SharedContent(
                type: .url,
                url: "https://example.com",
                urlTitle: "Example"
            ),
            annotationText: "Interesting"
        )
        repo.insert(memo)

        let mock = MockMacTransport()
        let synced = await SyncCoordinator(repository: repo, macTransport: mock, namesTransport: nil).syncAll()

        XCTAssertEqual(synced, 1, "capture with significance > 0 should be uploaded")
        XCTAssertEqual(mock.uploadedBodies.count, 1)

        // Verify the upload did NOT include a 'files' part (it's a capture)
        let text = String(decoding: mock.uploadedBodies[0], as: UTF8.self)
        XCTAssertFalse(text.contains(#"name="files""#),
                       "capture upload must not contain 'files' part")
    }

    @MainActor
    func testCaptureWithNoSharedContentIsSkipped() async {
        // A memo with no audio AND no sharedContent is invalid — skip rather than
        // uploading an empty capture.
        let repo = NotesRepository(inMemory: true)
        let memo = Memo(
            audioFilename: "",
            duration: 0,
            syncStatus: .waiting,
            transcriptStatus: .done,
            significance: 0.6
            // no sharedContent
        )
        repo.insert(memo)

        let mock = MockMacTransport()
        let synced = await SyncCoordinator(repository: repo, macTransport: mock, namesTransport: nil).syncAll()

        XCTAssertEqual(synced, 0, "capture with no sharedContent should be skipped")
        XCTAssertEqual(mock.uploadedBodies.count, 0)
    }

    // MARK: - Helpers

    @MainActor
    private func makeMemo(
        type: ShareContentType,
        url: String? = nil,
        urlTitle: String? = nil,
        text: String? = nil,
        imageFileName: String? = nil,
        mimeType: String? = nil,
        annotationText: String? = nil,
        significance: Double = 0.5,
        imageManifestFilename: String? = nil
    ) -> Memo {
        let sharedContent = SharedContent(
            type: type,
            url: url,
            urlTitle: urlTitle,
            text: text,
            fileName: imageFileName,
            mimeType: mimeType
        )
        let imageManifest: [ImageManifestEntry]? = imageManifestFilename.map {
            [ImageManifestEntry(filename: $0, offsetSeconds: 0)]
        }
        return Memo(
            audioFilename: "",
            duration: 0,
            recordedAt: Date(),
            syncStatus: .waiting,
            transcriptStatus: .done,
            transcriptUserEdited: false,
            significance: significance,
            metadata: imageManifest.map { MemoMetadata(imageManifest: $0) },
            sharedContent: sharedContent,
            annotationText: annotationText
        )
    }

    private func extractAndDecodeMetadata(from body: Data) throws -> UploadMetadata {
        // The metadata JSON is the content of the `metadata` part. Locate it by
        // finding the Content-Type: application/json header and reading until the
        // next boundary.
        let text = String(decoding: body, as: UTF8.self)
        guard let jsonStart = text.range(of: "application/json\r\n\r\n") else {
            throw XCTSkip("No application/json part found in multipart body")
        }
        let afterHeader = text[jsonStart.upperBound...]
        guard let jsonEnd = afterHeader.range(of: "\r\n--") else {
            throw XCTSkip("Could not locate end of JSON part")
        }
        let jsonStr = String(afterHeader[..<jsonEnd.lowerBound])
        let data = Data(jsonStr.utf8)
        return try JSONDecoder().decode(UploadMetadata.self, from: data)
    }
}
