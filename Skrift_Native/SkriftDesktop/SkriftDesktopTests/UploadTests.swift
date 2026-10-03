import XCTest
import SwiftData
import Foundation

/// Q214: `UploadService` has ONE typed entry — `ingest(memo:assets:into:)` / `prepare(memo:assets:)`
/// reading the `Memo` and its `MemoAsset`s directly. (These tests used to feed fake multipart
/// parts; the Bonjour/HTTP server those mirrored is retired.)
final class UploadServiceTests: XCTestCase {

    private func memoryContext() throws -> ModelContext {
        let container = try ModelContainer(for: PipelineFile.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func audio(_ memo: Memo, _ bytes: String = "AUDIO") -> MemoAsset {
        MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.audio,
                  filename: memo.audioFilename, blob: Data(bytes.utf8))
    }

    func testIngestTrustedTranscriptIsAccepted() throws {
        let svc = UploadService(outputDir: makeTempDir())
        let ctx = try memoryContext()
        let memo = Memo(audioFilename: "memo_abc.m4a", transcript: "hello world", transcriptStatus: .done,
                        transcriptConfidence: 0.9, metadataData: Data(#"{"transcriptConfidence":0.9}"#.utf8))
        let pf = try XCTUnwrap(svc.ingest(memo: memo, assets: [audio(memo)], into: ctx))
        XCTAssertEqual(pf.id, memo.id.uuidString)
        XCTAssertEqual(pf.filename, "memo_abc.m4a")
        XCTAssertEqual(pf.transcript, "hello world")
        XCTAssertEqual(pf.transcribeStatus, .done)             // trusted (conf 0.9)
        XCTAssertEqual(pf.sanitiseStatus, .pending)            // Mac links names
        XCTAssertTrue(FileManager.default.fileExists(atPath: pf.path))
        XCTAssertNotNil(pf.audioMetadataJSON)                  // metadata stored for downstream readers
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<PipelineFile>()).count, 1)
    }

    func testIngestReadsWordTimingsAndDiarizationSidecar() throws {
        let svc = UploadService(outputDir: makeTempDir())
        let ctx = try memoryContext()
        let words = Data(#"[{"word":"hi","start":0.0,"end":0.5},{"word":"there","start":0.5,"end":1.0}]"#.utf8)
        let diar = Data(#"{"segments":[{"speaker":0,"start":0.0,"end":1.0},{"speaker":1,"start":1.0,"end":2.0}],"slotNames":{"0":"Tiuri Hartog"}}"#.utf8)
        let memo = Memo(audioFilename: "memo_conv.m4a",
                        transcript: "**Tiuri Hartog:** hi\n\n**Speaker 2:** there", transcriptStatus: .done,
                        transcriptConfidence: 0.9)
        let assets = [
            audio(memo),
            MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.wordTimings, filename: "wt.json", blob: words),
            MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.diarization, filename: "diar.json", blob: diar),
        ]
        let pf = try XCTUnwrap(svc.ingest(memo: memo, assets: assets, into: ctx))
        // Word-timings drive Mac karaoke on a trusted memo it never re-transcribes.
        XCTAssertEqual(pf.wordTimings.map(\.word), ["hi", "there"])
        // Diarization segments retained for voice enrollment + mirrored to the sidecar.
        XCTAssertEqual(Set(pf.diarizationSegments.map(\.speaker)), [0, 1])
        let folder = URL(fileURLWithPath: pf.path).deletingLastPathComponent()
        let loaded = try XCTUnwrap(DiarizationSidecar().load(in: folder, id: pf.id))
        XCTAssertEqual(loaded.slotNames["0"], "Tiuri Hartog")
    }

    func testIngestWithoutSidecarsStaysByteCompatible() throws {
        // An older phone build (no wordTimings/diar assets) ingests exactly as before.
        let svc = UploadService(outputDir: makeTempDir())
        let ctx = try memoryContext()
        let memo = Memo(audioFilename: "memo_old.m4a", transcript: "hello", transcriptStatus: .done,
                        transcriptConfidence: 0.9)
        let pf = try XCTUnwrap(svc.ingest(memo: memo, assets: [audio(memo)], into: ctx))
        XCTAssertEqual(pf.transcript, "hello")
        XCTAssertTrue(pf.wordTimings.isEmpty)
        XCTAssertTrue(pf.diarizationSegments.isEmpty)
    }

    func testIngestUntrustedTranscriptIsDropped() throws {
        let svc = UploadService(outputDir: makeTempDir())
        let ctx = try memoryContext()
        let memo = Memo(audioFilename: "memo_xyz.m4a", transcript: "low conf", transcriptStatus: .done,
                        transcriptConfidence: 0.5)
        let pf = try XCTUnwrap(svc.ingest(memo: memo, assets: [audio(memo)], into: ctx))
        XCTAssertNil(pf.transcript)                            // dropped (conf 0.5 < 0.7, not edited)
        XCTAssertEqual(pf.transcribeStatus, .pending)
    }

    /// The trust gate is `Memo.isTrustedTranscript`, read straight off the memo's fields.
    func testTrustViaUserEditedFlag() throws {
        let svc = UploadService(outputDir: makeTempDir())
        func trusted(edited: Bool, confidence: Double?) throws -> Bool {
            let memo = Memo(audioFilename: "memo_t.m4a", transcript: "words", transcriptStatus: .done,
                            transcriptConfidence: confidence, transcriptUserEdited: edited)
            return try XCTUnwrap(svc.prepare(memo: memo, assets: [audio(memo)])).transcript != nil
        }
        XCTAssertTrue(try trusted(edited: true, confidence: nil))
        XCTAssertTrue(try trusted(edited: false, confidence: 0.7))
        XCTAssertFalse(try trusted(edited: false, confidence: 0.69))
        XCTAssertFalse(try trusted(edited: false, confidence: nil))
    }

    /// Phone-sent `significance` (flag-to-process rating) pre-fills the review slider.
    func testIngestReadsSignificance() throws {
        let svc = UploadService(outputDir: makeTempDir())
        let ctx = try memoryContext()
        let memo = Memo(audioFilename: "memo_sig.m4a", transcriptStatus: .done,
                        transcriptConfidence: 0.9, significance: 0.6)
        let pf = try XCTUnwrap(svc.ingest(memo: memo, assets: [audio(memo)], into: ctx))
        XCTAssertEqual(pf.significance, 0.6)

        // Significance 0 → stays nil (unrated on the Mac side).
        let bare = Memo(audioFilename: "memo_nosig.m4a", transcriptStatus: .done, transcriptConfidence: 0.9)
        let pf2 = try XCTUnwrap(svc.ingest(memo: bare, assets: [audio(bare, "A")], into: ctx))
        XCTAssertNil(pf2.significance)
    }

    /// A phone VIDEO import: keep the video's CONTENT date (`recordedAt`), NOT the
    /// upload time (the extracted m4a has no embedded date to backfill), and carry
    /// the `"video"` source marker so the Mac shows the video glyph + "Video" label.
    func testIngestVideoUsesRecordedDateAndMarksSource() throws {
        let svc = UploadService(outputDir: makeTempDir())
        let ctx = try memoryContext()
        let recorded = try XCTUnwrap(ISO8601.date(from: "2026-06-14T17:44:01.000Z"))
        let memo = Memo(audioFilename: "memo_vid.m4a", recordedAt: recorded, transcriptStatus: .done,
                        transcriptConfidence: 0.9, metadataData: Data(#"{"sourceType":"video"}"#.utf8))
        let pf = try XCTUnwrap(svc.ingest(memo: memo, assets: [audio(memo)], into: ctx))
        XCTAssertEqual(pf.mediaSource, "video", "video marker drives the source glyph + label")
        XCTAssertEqual(pf.uploadedAt.timeIntervalSince1970, recorded.timeIntervalSince1970, accuracy: 1.0,
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

    // MARK: Contract fixture — url capture (CAPTURE_CONTRACT.md literal example)

    /// The contract's literal url-capture fixture must produce one .capture PipelineFile
    /// with the annotation as transcript (transcribeStatus = .done) and significance pre-filled.
    func testUrlCaptureContractFixture() throws {
        let svc = UploadService(outputDir: makeTempDir())
        let ctx = try memoryContext()

        let shared = Data("""
        {
          "type": "url",
          "url": "https://swiftwithmajid.com/2026/05/rich-text-editing",
          "urlTitle": "Rich text editing in SwiftUI — strategies that work"
        }
        """.utf8)
        // No audio asset (C3 §1), no transcript (C3 §2), a sharedContent payload.
        let memo = Memo(audioFilename: "", recordedAt: ISO8601.date(from: "2026-06-11T14:02:00Z")!,
                        transcriptStatus: .done, significance: 0.6,
                        sharedContentData: shared,
                        annotationText: "Try this for the desktop body editor — the NSTextView part maps onto what Nick suggested.")
        let pf = try XCTUnwrap(svc.ingest(memo: memo, assets: [], into: ctx), "one capture per memo")
        XCTAssertEqual(pf.sourceType, .capture, "sourceType must be .capture")
        XCTAssertEqual(pf.transcribeStatus, .done, "ASR skipped — transcript already present")
        XCTAssertEqual(pf.transcript,
                        "Try this for the desktop body editor — the NSTextView part maps onto what Nick suggested.",
                        "annotation becomes the transcript")
        XCTAssertEqual(pf.significance ?? 0, 0.6, accuracy: 0.001, "significance pre-filled from the memo")
        XCTAssertNotNil(pf.audioMetadataJSON, "metadata stored for downstream readers")

        // The working folder must exist on disk (Pipeline writes sidecars there).
        XCTAssertTrue(FileManager.default.fileExists(atPath: pf.path), "working folder created")

        // The metadata carries the sharedContent object.
        let meta = try XCTUnwrap(
            (try? JSONSerialization.jsonObject(with: pf.audioMetadataJSON!)) as? [String: Any])
        let sc = try XCTUnwrap(meta["sharedContent"] as? [String: Any])
        XCTAssertEqual(sc["type"] as? String, "url")
        XCTAssertEqual(sc["url"] as? String, "https://swiftwithmajid.com/2026/05/rich-text-editing")
    }

    // MARK: Image capture — images/ folder + manifest

    func testImageCaptureWritesImageFolder() throws {
        let svc = UploadService(outputDir: makeTempDir())
        let ctx = try memoryContext()

        let memo = Memo(audioFilename: "", transcriptStatus: .done, significance: 0.7,
                        metadataData: Data(#"{"imageManifest":[{"filename":"whiteboard.jpg","offsetSeconds":0}]}"#.utf8),
                        sharedContentData: Data(#"{"type":"image","fileName":"whiteboard.jpg","mimeType":"image/jpeg"}"#.utf8),
                        annotationText: "The sync flow from Nick's session.")
        let image = MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.photo,
                              filename: "whiteboard.jpg", blob: Data("FAKEJPEG".utf8))
        let pf = try XCTUnwrap(svc.ingest(memo: memo, assets: [image], into: ctx))
        XCTAssertEqual(pf.sourceType, .capture)

        // The image must be saved under `<folder>/images/whiteboard.jpg`.
        let imagesDir = URL(fileURLWithPath: pf.path).appendingPathComponent("images")
        let imgPath = imagesDir.appendingPathComponent("whiteboard.jpg").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: imgPath), "image saved under images/")

        // image_manifest.json must exist alongside the image.
        let manifestPath = URL(fileURLWithPath: pf.path).appendingPathComponent("image_manifest.json").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestPath), "manifest written")
    }

    // MARK: Named audio whose asset has not synced yet → nothing created (preserved)

    func testMemoWithNamedAudioButNoAssetCreatesNothing() throws {
        let svc = UploadService(outputDir: makeTempDir())
        let ctx = try memoryContext()

        // A voice memo whose `MemoAsset` blob has not arrived: no audio asset, no sharedContent,
        // but it NAMES its file, so it is not a text note either — it waits for the asset.
        let memo = Memo(audioFilename: "memo_wait.m4a", transcriptStatus: .done, significance: 0.5)
        XCTAssertNil(try svc.ingest(memo: memo, assets: [], into: ctx),
                     "named audio + no asset + no sharedContent → nothing ingested, the next sweep retries")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<PipelineFile>()).count, 0)
    }

    // MARK: The audio / text / capture decision

    func testShapeDecidesAudioTextOrCaptureOnce() throws {
        let capture = Data(#"{"type":"url","url":"https://example.com"}"#.utf8)
        let named = Memo(audioFilename: "memo_n.m4a")
        let audio = MemoAsset(memoID: named.id, kind: MemoAsset.Kind.audio, filename: "memo_n.m4a", blob: Data("A".utf8))

        // Audio asset wins, even with a sharedContent key in the memo (the C3 discriminator).
        let both = Memo(audioFilename: "memo_n.m4a", sharedContentData: capture)
        guard case .audio? = UploadService.shape(memo: both, assets: [audio]) else { return XCTFail("audio") }
        // No audio + parsing payload = capture, whatever the filename.
        guard case .capture? = UploadService.shape(memo: Memo(audioFilename: "", sharedContentData: capture), assets: [])
        else { return XCTFail("capture") }
        // No audio, no filename, no payload = typed text.
        guard case .text? = UploadService.shape(memo: Memo(audioFilename: ""), assets: []) else { return XCTFail("text") }
        // A payload that does NOT parse never falls between the arms: text with no filename...
        guard case .text? = UploadService.shape(memo: Memo(audioFilename: "", sharedContentData: Data("nope".utf8)), assets: [])
        else { return XCTFail("unparseable payload, no filename = text") }
        // ...and waiting (nil) when the memo names audio that has not arrived.
        XCTAssertNil(UploadService.shape(memo: named, assets: []))
    }

    // MARK: Normal audio memo is byte-identical in behavior

    func testNormalAudioMemoUnchanged() throws {
        let svc = UploadService(outputDir: makeTempDir())
        let ctx = try memoryContext()
        let memo = Memo(audioFilename: "memo_audio.m4a", transcript: "real words", transcriptStatus: .done,
                        transcriptConfidence: 0.9, sharedContentData: Data(#"{"type":"url"}"#.utf8))
        let audio = MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.audio,
                              filename: "memo_audio.m4a", blob: Data("AUDIO".utf8))
        // An audio memo WITH a sharedContent key is still a memo (the audio asset takes
        // precedence per the C3 discriminator).
        let pf = try XCTUnwrap(svc.ingest(memo: memo, assets: [audio], into: ctx))
        XCTAssertEqual(pf.sourceType, .audio, "audio memo stays .audio")
        XCTAssertEqual(pf.transcript, "real words")
        XCTAssertEqual(pf.transcribeStatus, .done)
    }

    // MARK: Empty annotation capture

    func testEmptyAnnotationCapture() throws {
        let svc = UploadService(outputDir: makeTempDir())
        let ctx = try memoryContext()

        let memo = Memo(audioFilename: "", transcriptStatus: .done, significance: 0.5,
                        sharedContentData: Data(#"{"type":"text","text":"Some quote"}"#.utf8))
        let pf = try XCTUnwrap(svc.ingest(memo: memo, assets: [], into: ctx))
        XCTAssertEqual(pf.sourceType, .capture)
        XCTAssertEqual(pf.transcript, "", "empty annotation → empty transcript (not nil)")
        XCTAssertEqual(pf.transcribeStatus, .done, "ASR still skipped for empty annotation")
    }
}
