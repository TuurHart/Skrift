import XCTest
import SwiftData
import Foundation

final class UploadServiceTests: XCTestCase {

    private func memoryContext() throws -> ModelContext {
        let container = try ModelContainer(for: PipelineFile.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("up_\(UUID().uuidString)", isDirectory: true)
    }

    func testIngestTrustedTranscriptIsAccepted() throws {
        let svc = UploadService(outputDir: tempDir())
        let ctx = try memoryContext()
        let parts = [
            MultipartPart(name: "files", filename: "memo_abc.m4a", contentType: "audio/mp4", data: Data("AUDIO".utf8)),
            MultipartPart(name: "metadata", filename: nil, contentType: "application/json",
                          data: Data(#"{"transcriptConfidence":0.9}"#.utf8)),
            MultipartPart(name: "transcript", filename: nil, contentType: nil, data: Data("hello world".utf8)),
        ]
        let created = try svc.ingest(parts: parts, into: ctx)
        XCTAssertEqual(created.count, 1)
        let pf = created[0]
        XCTAssertEqual(pf.filename, "memo_abc.m4a")
        XCTAssertEqual(pf.transcript, "hello world")
        XCTAssertEqual(pf.transcribeStatus, .done)             // trusted (conf 0.9)
        XCTAssertEqual(pf.sanitiseStatus, .pending)            // Mac links names
        XCTAssertTrue(FileManager.default.fileExists(atPath: pf.path))
        XCTAssertNotNil(pf.audioMetadataJSON)                  // metadata preserved verbatim
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<PipelineFile>()).count, 1)
    }

    func testIngestReadsWordTimingsAndDiarizationSidecar() throws {
        let svc = UploadService(outputDir: tempDir())
        let ctx = try memoryContext()
        let words = Data(#"[{"word":"hi","start":0.0,"end":0.5},{"word":"there","start":0.5,"end":1.0}]"#.utf8)
        let diar = Data(#"{"segments":[{"speaker":0,"start":0.0,"end":1.0},{"speaker":1,"start":1.0,"end":2.0}],"slotNames":{"0":"Tiuri Hartog"}}"#.utf8)
        let parts = [
            MultipartPart(name: "files", filename: "memo_conv.m4a", contentType: "audio/mp4", data: Data("AUDIO".utf8)),
            MultipartPart(name: "metadata", filename: nil, contentType: "application/json",
                          data: Data(#"{"transcriptConfidence":0.9,"source":"mobile"}"#.utf8)),
            MultipartPart(name: "transcript", filename: nil, contentType: nil,
                          data: Data("**Tiuri Hartog:** hi\n\n**Speaker 2:** there".utf8)),
            MultipartPart(name: "wordTimings", filename: nil, contentType: "application/json", data: words),
            MultipartPart(name: "diar", filename: nil, contentType: "application/json", data: diar),
        ]
        let pf = try XCTUnwrap(svc.ingest(parts: parts, into: ctx).first)
        // Word-timings drive Mac karaoke on a trusted memo it never re-transcribes.
        XCTAssertEqual(pf.wordTimings.map(\.word), ["hi", "there"])
        // Diarization segments retained for voice enrollment + mirrored to the sidecar.
        XCTAssertEqual(Set(pf.diarizationSegments.map(\.speaker)), [0, 1])
        let folder = URL(fileURLWithPath: pf.path).deletingLastPathComponent()
        let loaded = try XCTUnwrap(DiarizationSidecar().load(in: folder, id: pf.id))
        XCTAssertEqual(loaded.slotNames["0"], "Tiuri Hartog")
    }

    func testIngestWithoutNewPartsStaysByteCompatible() throws {
        // An older phone build (no wordTimings/diar parts) ingests exactly as before.
        let svc = UploadService(outputDir: tempDir())
        let ctx = try memoryContext()
        let parts = [
            MultipartPart(name: "files", filename: "memo_old.m4a", contentType: "audio/mp4", data: Data("AUDIO".utf8)),
            MultipartPart(name: "metadata", filename: nil, contentType: "application/json",
                          data: Data(#"{"transcriptConfidence":0.9}"#.utf8)),
            MultipartPart(name: "transcript", filename: nil, contentType: nil, data: Data("hello".utf8)),
        ]
        let pf = try XCTUnwrap(svc.ingest(parts: parts, into: ctx).first)
        XCTAssertEqual(pf.transcript, "hello")
        XCTAssertTrue(pf.wordTimings.isEmpty)
        XCTAssertTrue(pf.diarizationSegments.isEmpty)
    }

    func testIngestUntrustedTranscriptIsDropped() throws {
        let svc = UploadService(outputDir: tempDir())
        let ctx = try memoryContext()
        let parts = [
            MultipartPart(name: "files", filename: "memo_xyz.m4a", contentType: "audio/mp4", data: Data("AUDIO".utf8)),
            MultipartPart(name: "metadata", filename: nil, contentType: "application/json",
                          data: Data(#"{"transcriptConfidence":0.5}"#.utf8)),
            MultipartPart(name: "transcript", filename: nil, contentType: nil, data: Data("low conf".utf8)),
        ]
        let pf = try XCTUnwrap(svc.ingest(parts: parts, into: ctx).first)
        XCTAssertNil(pf.transcript)                            // dropped (conf 0.5 < 0.7, not edited)
        XCTAssertEqual(pf.transcribeStatus, .pending)
    }

    func testTrustViaUserEditedFlag() throws {
        let svc = UploadService()
        XCTAssertTrue(svc.isTranscriptTrusted(["transcriptUserEdited": true]))
        XCTAssertTrue(svc.isTranscriptTrusted(["transcriptConfidence": 0.7]))
        XCTAssertFalse(svc.isTranscriptTrusted(["transcriptConfidence": 0.69]))
        XCTAssertFalse(svc.isTranscriptTrusted(nil))
    }

    /// Phone-sent `significance` (flag-to-send rating) pre-fills the review slider.
    func testIngestReadsSignificanceFromMetadata() throws {
        let svc = UploadService(outputDir: tempDir())
        let ctx = try memoryContext()
        let parts = [
            MultipartPart(name: "files", filename: "memo_sig.m4a", contentType: "audio/mp4", data: Data("AUDIO".utf8)),
            MultipartPart(name: "metadata", filename: nil, contentType: "application/json",
                          data: Data(#"{"transcriptConfidence":0.9,"significance":0.6}"#.utf8)),
        ]
        let pf = try XCTUnwrap(svc.ingest(parts: parts, into: ctx).first)
        XCTAssertEqual(pf.significance, 0.6)

        // No significance key → stays nil (unrated on the Mac side).
        let bare = [
            MultipartPart(name: "files", filename: "memo_nosig.m4a", contentType: "audio/mp4", data: Data("A".utf8)),
            MultipartPart(name: "metadata", filename: nil, contentType: "application/json",
                          data: Data(#"{"transcriptConfidence":0.9}"#.utf8)),
        ]
        let pf2 = try XCTUnwrap(svc.ingest(parts: bare, into: ctx).first)
        XCTAssertNil(pf2.significance)
    }

    /// A phone VIDEO import: keep the video's CONTENT date (`recordedAt`), NOT the
    /// upload time (the extracted m4a has no embedded date to backfill), and carry
    /// the `"video"` source marker so the Mac shows the video glyph + "Video" label.
    func testIngestVideoUsesRecordedDateAndMarksSource() throws {
        let svc = UploadService(outputDir: tempDir())
        let ctx = try memoryContext()
        let metaJSON = #"{"transcriptConfidence":0.9,"recordedAt":"2026-06-14T17:44:01.000Z","sourceType":"video"}"#
        let parts = [
            MultipartPart(name: "files", filename: "memo_vid.m4a", contentType: "audio/mp4", data: Data("AUDIO".utf8)),
            MultipartPart(name: "metadata", filename: nil, contentType: "application/json", data: Data(metaJSON.utf8)),
        ]
        let pf = try XCTUnwrap(svc.ingest(parts: parts, into: ctx).first)
        XCTAssertEqual(pf.mediaSource, "video", "video marker drives the source glyph + label")
        let expected = try XCTUnwrap(ISO8601.date(from: "2026-06-14T17:44:01.000Z"))
        XCTAssertEqual(pf.uploadedAt.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1.0,
                       "the phone's recordedAt (content date) must win over the upload time")
    }
}

// MARK: - C3 Capture ingest tests

final class CaptureIngestTests: XCTestCase {

    private func memoryContext() throws -> ModelContext {
        let container = try ModelContainer(for: PipelineFile.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("cap_\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: Contract fixture — url capture (CAPTURE_CONTRACT.md literal example)

    /// The contract's literal url-capture fixture must produce one .capture PipelineFile
    /// with the annotation as transcript (transcribeStatus = .done) and significance pre-filled.
    func testUrlCaptureContractFixture() throws {
        let svc = UploadService(outputDir: tempDir())
        let ctx = try memoryContext()

        let metaJSON = """
        {
          "sharedContent": {
            "type": "url",
            "url": "https://swiftwithmajid.com/2026/05/rich-text-editing",
            "urlTitle": "Rich text editing in SwiftUI — strategies that work"
          },
          "annotationText": "Try this for the desktop body editor — the NSTextView part maps onto what Nick suggested.",
          "tags": [],
          "source": "mobile",
          "recordedAt": "2026-06-11T14:02:00Z",
          "duration": 0,
          "transcriptUserEdited": false,
          "transcriptMarkersInjected": false,
          "significance": 0.6
        }
        """.data(using: .utf8)!

        // No `files` part (C3 §1), no `transcript` part (C3 §2), metadata only.
        let parts = [
            MultipartPart(name: "metadata", filename: nil, contentType: "application/json", data: metaJSON),
        ]
        let created = try svc.ingest(parts: parts, into: ctx)

        XCTAssertEqual(created.count, 1, "one capture per upload")
        let pf = created[0]
        XCTAssertEqual(pf.sourceType, .capture, "sourceType must be .capture")
        XCTAssertEqual(pf.transcribeStatus, .done, "ASR skipped — transcript already present")
        XCTAssertEqual(pf.transcript,
                        "Try this for the desktop body editor — the NSTextView part maps onto what Nick suggested.",
                        "annotation becomes the transcript")
        XCTAssertEqual(pf.significance ?? 0, 0.6, accuracy: 0.001, "significance pre-filled from metadata")
        XCTAssertNotNil(pf.audioMetadataJSON, "metadata stored verbatim")

        // The working folder must exist on disk (Pipeline writes sidecars there).
        XCTAssertTrue(FileManager.default.fileExists(atPath: pf.path), "working folder created")

        // Check the metadata round-trips the sharedContent (raw JSON passthrough).
        let meta = try XCTUnwrap(
            (try? JSONSerialization.jsonObject(with: pf.audioMetadataJSON!)) as? [String: Any])
        let sc = try XCTUnwrap(meta["sharedContent"] as? [String: Any])
        XCTAssertEqual(sc["type"] as? String, "url")
        XCTAssertEqual(sc["url"] as? String, "https://swiftwithmajid.com/2026/05/rich-text-editing")
    }

    // MARK: Image capture — images/ folder + manifest

    func testImageCaptureWritesImageFolder() throws {
        let svc = UploadService(outputDir: tempDir())
        let ctx = try memoryContext()

        let metaJSON = """
        {
          "sharedContent": {"type": "image", "fileName": "whiteboard.jpg", "mimeType": "image/jpeg"},
          "annotationText": "The sync flow from Nick's session.",
          "imageManifest": [{"filename": "whiteboard.jpg", "offsetSeconds": 0}],
          "significance": 0.7
        }
        """.data(using: .utf8)!

        let imageData = Data("FAKEJPEG".utf8)
        let parts = [
            MultipartPart(name: "metadata", filename: nil, contentType: "application/json", data: metaJSON),
            MultipartPart(name: "images", filename: "whiteboard.jpg", contentType: "image/jpeg", data: imageData),
        ]
        let created = try svc.ingest(parts: parts, into: ctx)
        let pf = try XCTUnwrap(created.first)
        XCTAssertEqual(pf.sourceType, .capture)

        // The image must be saved under `<folder>/images/whiteboard.jpg`.
        let imagesDir = URL(fileURLWithPath: pf.path).appendingPathComponent("images")
        let imgPath = imagesDir.appendingPathComponent("whiteboard.jpg").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: imgPath), "image saved under images/")

        // image_manifest.json must exist alongside the image.
        let manifestPath = URL(fileURLWithPath: pf.path).appendingPathComponent("image_manifest.json").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestPath), "manifest written")
    }

    // MARK: No sharedContent + no audio → nothing created (current behavior preserved)

    func testUploadWithNoFilesAndNoSharedContentCreatesNothing() throws {
        let svc = UploadService(outputDir: tempDir())
        let ctx = try memoryContext()

        // A malformed / incomplete upload — no audio, no sharedContent.
        let parts = [
            MultipartPart(name: "metadata", filename: nil, contentType: "application/json",
                          data: Data(#"{"source":"mobile"}"#.utf8)),
        ]
        let created = try svc.ingest(parts: parts, into: ctx)
        XCTAssertEqual(created.count, 0, "no files + no sharedContent → nothing ingested")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<PipelineFile>()).count, 0)
    }

    // MARK: Normal audio upload is byte-identical in behavior

    func testNormalAudioUploadUnchanged() throws {
        let svc = UploadService(outputDir: tempDir())
        let ctx = try memoryContext()
        let parts = [
            MultipartPart(name: "files", filename: "memo_audio.m4a", contentType: "audio/mp4", data: Data("AUDIO".utf8)),
            MultipartPart(name: "metadata", filename: nil, contentType: "application/json",
                          data: Data(#"{"transcriptConfidence":0.9,"sharedContent":{"type":"url"}}"#.utf8)),
            MultipartPart(name: "transcript", filename: nil, contentType: nil, data: Data("real words".utf8)),
        ]
        // Audio upload WITH a sharedContent key in metadata is still treated as a memo
        // (the `files` part takes precedence per the C3 discriminator).
        let created = try svc.ingest(parts: parts, into: ctx)
        XCTAssertEqual(created.count, 1)
        let pf = created[0]
        XCTAssertEqual(pf.sourceType, .audio, "audio upload stays .audio")
        XCTAssertEqual(pf.transcript, "real words")
        XCTAssertEqual(pf.transcribeStatus, .done)
    }

    // MARK: Empty annotation capture

    func testEmptyAnnotationCapture() throws {
        let svc = UploadService(outputDir: tempDir())
        let ctx = try memoryContext()

        let metaJSON = Data(#"{"sharedContent":{"type":"text","text":"Some quote"},"significance":0.5}"#.utf8)
        let parts = [
            MultipartPart(name: "metadata", filename: nil, contentType: "application/json", data: metaJSON),
        ]
        let created = try svc.ingest(parts: parts, into: ctx)
        let pf = try XCTUnwrap(created.first)
        XCTAssertEqual(pf.sourceType, .capture)
        XCTAssertEqual(pf.transcript, "", "empty annotation → empty transcript (not nil)")
        XCTAssertEqual(pf.transcribeStatus, .done, "ASR still skipped for empty annotation")
    }
}
