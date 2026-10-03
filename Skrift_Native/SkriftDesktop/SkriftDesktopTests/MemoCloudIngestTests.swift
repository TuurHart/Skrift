import XCTest
import SwiftData
import Foundation

/// 8b golden tests for the Mac→CloudKit READ bridge (`MemoCloudIngest`): a synced `Memo`
/// (+ `MemoAsset`s) must reshape into the SAME `PipelineFile` the HTTP `UploadService` path
/// produces — so a memo behaves identically whichever transport delivered it.
final class MemoCloudIngestTests: XCTestCase {

    private func memoryContext() throws -> ModelContext {
        let container = try ModelContainer(for: PipelineFile.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    /// Encode a phone-`MemoMetadata`-shaped blob (property-name keys, like JSONEncoder).
    private func metadataBlob(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }

    private func audioAsset(_ memo: Memo, bytes: String = "AUDIO") -> MemoAsset {
        MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.audio,
                  filename: MemoCloudIngest.audioFilename(for: memo), blob: Data(bytes.utf8))
    }

    // MARK: - Golden parity: CloudKit ingest == HTTP ingest for the same memo

    func testCloudIngestMatchesHTTPIngest() throws {
        let recordedAt = ISO8601.date(from: "2026-06-06T10:00:00.000Z")!
        let meta = metadataBlob([
            "location": ["latitude": 38.71, "longitude": -9.14, "placeName": "Alfama, Lisbon"],
            "dayPeriod": "morning",
            "steps": 1200,
            "bookTitle": "Dune", "bookAuthor": "Herbert", "bookChapter": "4",
            "sourceType": "video",
        ])
        let memo = Memo(id: UUID(), audioFilename: "memo_\(UUID().uuidString).m4a", duration: 12,
                        recordedAt: recordedAt, tags: ["idea"], title: "Coffee with Hendri",
                        transcript: "Met up with Hendri today.", transcriptStatus: .done,
                        transcriptConfidence: 0.9, significance: 0.5, metadataData: meta)
        let assets = [audioAsset(memo)]

        // CloudKit path.
        let cloudCtx = try memoryContext()
        let pf1 = try MemoCloudIngest.ingest(memo: memo, assets: assets,
                                             upload: UploadService(outputDir: makeTempDir()), into: cloudCtx)
        let cloud = try XCTUnwrap(pf1)

        // HTTP path: feed the SAME synthesized parts straight through UploadService (no memoID
        // → a fresh random id, exactly as a phone upload). Proves the bridge adds no
        // behavioral divergence beyond the deliberate memo-UUID id.
        let httpCtx = try memoryContext()
        let parts = MemoCloudIngest.buildParts(memo: memo, assets: assets,
                                               filename: MemoCloudIngest.audioFilename(for: memo))
        let http = try XCTUnwrap(try UploadService(outputDir: makeTempDir()).ingest(parts: parts, into: httpCtx).first)

        // id: CloudKit forces the memo UUID; HTTP mints a random one.
        XCTAssertEqual(cloud.id, memo.id.uuidString)
        XCTAssertNotEqual(http.id, cloud.id)

        // Everything else must match field-for-field.
        XCTAssertEqual(cloud.filename, http.filename)
        XCTAssertEqual(cloud.transcript, http.transcript)
        XCTAssertEqual(cloud.transcribeStatus, http.transcribeStatus)
        XCTAssertEqual(cloud.significance, http.significance)
        XCTAssertEqual(cloud.uploadedAt, http.uploadedAt)
        XCTAssertEqual(cloud.enhancedTitle, http.enhancedTitle)
        XCTAssertEqual(cloud.mediaSource, http.mediaSource)
        XCTAssertEqual(cloud.sourceType, http.sourceType)
        XCTAssertEqual(cloud.bookCapture, http.bookCapture)
        XCTAssertEqual(cloud.audioMetadataJSON, http.audioMetadataJSON)

        // ...and the concrete expected values (not just "equal to each other").
        XCTAssertEqual(cloud.transcript, "Met up with Hendri today.")
        XCTAssertEqual(cloud.transcribeStatus, .done)              // trusted (confidence 0.9)
        XCTAssertEqual(cloud.significance, 0.5)
        XCTAssertEqual(cloud.uploadedAt, recordedAt)               // content date, not "now"
        XCTAssertEqual(cloud.enhancedTitle, "Coffee with Hendri")  // phone title honored
        XCTAssertEqual(cloud.mediaSource, "video")
        XCTAssertEqual(cloud.bookCapture?.title, "Dune")
        XCTAssertEqual(cloud.bookCapture?.author, "Herbert")
        XCTAssertEqual(cloud.bookCapture?.chapter, "4")

        // The metadata JSON decodes through the desktop PhoneMetadata exactly.
        let phoneMeta = try JSONDecoder().decode(PhoneMetadata.self, from: try XCTUnwrap(cloud.audioMetadataJSON))
        XCTAssertEqual(phoneMeta.location?.placeName, "Alfama, Lisbon")
        XCTAssertEqual(phoneMeta.dayPeriod, "morning")
        XCTAssertEqual(phoneMeta.steps, 1200)
        XCTAssertEqual(phoneMeta.recordedAt, "2026-06-06T10:00:00.000Z")
    }

    // MARK: - Trust gate

    func testUntrustedTranscriptIsDropped() throws {
        let memo = Memo(id: UUID(), audioFilename: "memo_x.m4a", recordedAt: Date(),
                        transcript: "rough draft", transcriptStatus: .done,
                        transcriptConfidence: 0.4, transcriptUserEdited: false, significance: 0.6)
        let ctx = try memoryContext()
        let pf = try XCTUnwrap(try MemoCloudIngest.ingest(memo: memo, assets: [audioAsset(memo)],
                                                          upload: UploadService(outputDir: makeTempDir()), into: ctx))
        XCTAssertNil(pf.transcript, "low-confidence, un-edited transcript must not be trusted")
        XCTAssertEqual(pf.transcribeStatus, .pending, "Mac must re-ASR an untrusted transcript")
    }

    func testUserEditedTranscriptIsTrustedEvenAtLowConfidence() throws {
        let memo = Memo(id: UUID(), audioFilename: "memo_y.m4a", recordedAt: Date(),
                        transcript: "hand-fixed", transcriptStatus: .done,
                        transcriptConfidence: 0.1, transcriptUserEdited: true, significance: 0.6)
        let ctx = try memoryContext()
        let pf = try XCTUnwrap(try MemoCloudIngest.ingest(memo: memo, assets: [audioAsset(memo)],
                                                          upload: UploadService(outputDir: makeTempDir()), into: ctx))
        XCTAssertEqual(pf.transcript, "hand-fixed")
        XCTAssertEqual(pf.transcribeStatus, .done)
    }

    // MARK: - Significance gate (flag-to-send)

    func testSignificanceZeroIsSkipped() throws {
        let memo = Memo(id: UUID(), audioFilename: "memo_z.m4a", recordedAt: Date(),
                        transcriptStatus: .done, significance: 0)
        let ctx = try memoryContext()
        XCTAssertNil(try MemoCloudIngest.ingest(memo: memo, assets: [audioAsset(memo)],
                                                upload: UploadService(outputDir: makeTempDir()), into: ctx),
                     "significance 0 syncs but never enters the queue")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<PipelineFile>()), 0)
    }

    func testProcessEverythingOverridesSignificanceGate() throws {
        let memo = Memo(id: UUID(), audioFilename: "memo_z2.m4a", recordedAt: Date(),
                        transcriptStatus: .done, significance: 0)
        let ctx = try memoryContext()
        let pf = try MemoCloudIngest.ingest(memo: memo, assets: [audioAsset(memo)],
                                            upload: UploadService(outputDir: makeTempDir()), into: ctx,
                                            processEverything: true)
        XCTAssertNotNil(pf, "the 8d 'process everything' override ingests significance-0 memos")
    }

    func testTrashedMemoIsSkipped() throws {
        let memo = Memo(id: UUID(), audioFilename: "memo_t.m4a", recordedAt: Date(),
                        transcriptStatus: .done, significance: 0.6, deletedAt: Date())
        let ctx = try memoryContext()
        XCTAssertNil(try MemoCloudIngest.ingest(memo: memo, assets: [audioAsset(memo)],
                                                upload: UploadService(outputDir: makeTempDir()), into: ctx))
    }

    // MARK: - Dedup (one PipelineFile per memo, regardless of transport)

    func testReingestDedupsByMemoUUID() throws {
        let memo = Memo(id: UUID(), audioFilename: "memo_d.m4a", recordedAt: Date(),
                        transcript: "hi", transcriptStatus: .done, transcriptConfidence: 0.9, significance: 0.6)
        let ctx = try memoryContext()
        let upload = UploadService(outputDir: makeTempDir())
        XCTAssertNotNil(try MemoCloudIngest.ingest(memo: memo, assets: [audioAsset(memo)], upload: upload, into: ctx))
        XCTAssertNil(try MemoCloudIngest.ingest(memo: memo, assets: [audioAsset(memo)], upload: upload, into: ctx),
                     "a second reconcile of the same memo must not create a duplicate")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<PipelineFile>()), 1)
    }

    func testDedupsAgainstBonjourIngestedFilename() throws {
        // Simulate a Bonjour upload first: same filename, but a RANDOM id (HTTP behavior).
        let memo = Memo(id: UUID(), audioFilename: "memo_b.m4a", recordedAt: Date(),
                        transcript: "hi", transcriptStatus: .done, transcriptConfidence: 0.9, significance: 0.6)
        let ctx = try memoryContext()
        let bonjourParts = MemoCloudIngest.buildParts(memo: memo, assets: [audioAsset(memo)],
                                                      filename: memo.audioFilename)
        _ = try UploadService(outputDir: makeTempDir()).ingest(parts: bonjourParts, into: ctx)  // random id
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<PipelineFile>()), 1)

        XCTAssertNil(try MemoCloudIngest.ingest(memo: memo, assets: [audioAsset(memo)],
                                                upload: UploadService(outputDir: makeTempDir()), into: ctx),
                     "CloudKit ingest must dedup against a Bonjour-ingested row by filename")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<PipelineFile>()), 1)
    }

    // MARK: - Capture memo (no audio, sharedContent)

    func testCaptureMemoIngest() throws {
        let memo = Memo(id: UUID(), audioFilename: "", recordedAt: Date(),
                        transcriptStatus: .done, significance: 0.6, annotationText: "Worth reading.")
        memo.sharedContentData = metadataBlob(["type": "url", "url": "https://example.com", "urlTitle": "Example"])
        let ctx = try memoryContext()
        let pf = try XCTUnwrap(try MemoCloudIngest.ingest(memo: memo, assets: [],
                                                          upload: UploadService(outputDir: makeTempDir()), into: ctx))
        XCTAssertEqual(pf.id, memo.id.uuidString)
        XCTAssertEqual(pf.sourceType, .capture, "no audio + sharedContent → capture")
        XCTAssertEqual(pf.transcript, "Worth reading.", "annotation becomes the transcript")
        XCTAssertEqual(pf.transcribeStatus, .done)
        let sc = try XCTUnwrap(SharedContent.decode(from: pf.audioMetadataJSON))
        XCTAssertEqual(sc.type, .url)
        XCTAssertEqual(sc.url, "https://example.com")
    }

    func testFileCaptureDocumentMaterializes() throws {
        let memo = Memo(id: UUID(), audioFilename: "", recordedAt: Date(),
                        transcriptStatus: .done, significance: 0.6, annotationText: "See the PDF.")
        memo.sharedContentData = metadataBlob(["type": "file", "fileName": "attention.pdf",
                                               "mimeType": "application/pdf"])
        let name = "file_\(memo.id.uuidString).pdf"
        let doc = MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.document,
                            filename: name, blob: Data("%PDF-1.4 fake".utf8))
        let ctx = try memoryContext()
        let pf = try XCTUnwrap(try MemoCloudIngest.ingest(memo: memo, assets: [doc],
                                                          upload: UploadService(outputDir: makeTempDir()), into: ctx))
        // 3b: the synced document lands under the capture folder's files/ so the Mac can open it.
        let filesDir = URL(fileURLWithPath: pf.path).appendingPathComponent("files")
        let contents = try FileManager.default.contentsOfDirectory(at: filesDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(contents.map(\.lastPathComponent), [name])
        XCTAssertEqual(try Data(contentsOf: filesDir.appendingPathComponent(name)), Data("%PDF-1.4 fake".utf8))
    }

    // MARK: - Word-timings / diarization sidecars (trusted only)

    func testWordTimingsAndDiarizationMaterialize() throws {
        let memo = Memo(id: UUID(), audioFilename: "memo_wt.m4a", recordedAt: Date(),
                        transcript: "one two", transcriptStatus: .done, transcriptConfidence: 0.9, significance: 0.6)
        let timings = [WordTiming(word: "one", start: 0, end: 0.5), WordTiming(word: "two", start: 0.5, end: 1)]
        let wtBlob = try JSONEncoder().encode(timings)
        let diar = DiarizationData(segments: [DiarizedSegment(speaker: 0, start: 0, end: 1)],
                                   slotNames: [:], turnSlots: nil)
        let diarBlob = try JSONEncoder().encode(diar)
        let assets = [
            audioAsset(memo),
            MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.wordTimings, filename: "wt.json", blob: wtBlob),
            MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.diarization, filename: "diar.json", blob: diarBlob),
        ]
        let ctx = try memoryContext()
        let pf = try XCTUnwrap(try MemoCloudIngest.ingest(memo: memo, assets: assets,
                                                          upload: UploadService(outputDir: makeTempDir()), into: ctx))
        XCTAssertEqual(pf.wordTimings.map(\.word), ["one", "two"])
        XCTAssertEqual(pf.diarizationSegments.count, 1)
        XCTAssertEqual(pf.diarizationSegments.first?.speaker, 0)
    }

    // MARK: - Row mirrors (lock / reminder / photo OCR) set at ingest

    func testIngestMirrorsLockReminderAndOCR() throws {
        let remind = Date().addingTimeInterval(7200)
        // NB: `tags` is non-optional in the typed MemoMetadata decode (the phone always
        // writes it) — a blob without it fails to decode and would yield no OCR text.
        let meta = metadataBlob([
            "tags": [],
            "imageManifest": [["filename": "img_001.jpg", "offsetSeconds": 1.0, "text": "WHITEBOARD ROADMAP"]],
        ])
        let memo = Memo(id: UUID(), audioFilename: "memo_\(UUID().uuidString).m4a", duration: 5,
                        transcript: "t", transcriptStatus: .done, transcriptConfidence: 0.9,
                        significance: 0.5, metadataData: meta)
        memo.locked = true
        memo.remindAt = remind

        let ctx = try memoryContext()
        let pf = try XCTUnwrap(try MemoCloudIngest.ingest(memo: memo, assets: [audioAsset(memo)],
                                                          upload: UploadService(outputDir: makeTempDir()), into: ctx))
        XCTAssertTrue(pf.locked)
        XCTAssertEqual(pf.remindAt, remind)
        XCTAssertEqual(pf.imageOCRText, "WHITEBOARD ROADMAP")
    }

    // MARK: - Text-only memo (no audio, no sharedContent) — the typed note

    /// THE rate→row hole (Tuur, 2026-08-19): a note TYPED on the Mac or iPad has no audio
    /// asset and no `sharedContent`, so `UploadService.prepare` fell through both its
    /// branches and returned ZERO descriptors — `ingest` handed back nil on every sweep,
    /// forever. Rated, the memo then sat in limbo: no pipeline row (no Process button, no
    /// queue section) and excluded from the quiet rows (those are the UNRATED ones), i.e.
    /// invisible in every list section while the text sat safe in the cloud store.
    func testTypedNoteIngestsAsANoteRow() throws {
        let memo = try typedMemo(text: "Mats was tien jaar.\n\nHij keek naar de zee.", significance: 0.1)
        let ctx = try memoryContext()
        let pf = try XCTUnwrap(try MemoCloudIngest.ingest(memo: memo, assets: [],
                                                          upload: UploadService(outputDir: makeTempDir()), into: ctx),
                               "a rated typed note MUST become a row — anything else is an invisible note")
        XCTAssertEqual(pf.id, memo.id.uuidString, "the memo UUID is the contract spine")
        XCTAssertEqual(pf.sourceType, .note, "no audio + no sharedContent → a text note row")
        XCTAssertEqual(pf.transcript, memo.transcript, "the typed text IS the body, verbatim")
        XCTAssertEqual(pf.transcribeStatus, .done, "there is nothing to transcribe")
        XCTAssertEqual(pf.mediaSource, "typed", "the typed marker survives ingest (glyph + \"Note\" label)")
        XCTAssertTrue(WayOutRules.needsProcessing(pf), "a rated typed note is ready to process")
        // The body is on disk like any other row's original, so the exporter + the
        // working-folder machinery have a real file to work with.
        XCTAssertEqual(URL(fileURLWithPath: pf.path).lastPathComponent, "original.md")
        XCTAssertEqual(try String(contentsOfFile: pf.path, encoding: .utf8), memo.transcript)
    }

    /// The unrated half of the same shape stays gated — the rating is what pipelines a
    /// note, and this fix must not turn every typed scratch note into queued work.
    func testUnratedTypedNoteStillNeverIngests() throws {
        let memo = try typedMemo(text: "half a thought", significance: 0)
        let ctx = try memoryContext()
        XCTAssertNil(try MemoCloudIngest.ingest(memo: memo, assets: [],
                                                upload: UploadService(outputDir: makeTempDir()), into: ctx),
                     "unrated = no consent: the quiet row is its whole surface")
    }

    /// A typed note with photos: the images land under the row's `images/` so the
    /// `[[img_NNN]]` markers in the body resolve (and reach the vault on export).
    func testTypedNoteWithPhotosMaterializesImages() throws {
        let memo = try typedMemo(text: "Look at this.\n\n[[img_001]]", significance: 0.4)
        memo.metadataData = metadataBlob(["mediaSource": "typed", "tags": [],
                                          "imageManifest": [["filename": "img_001.jpg", "offsetSeconds": 0]]])
        let photo = MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.photo,
                              filename: "img_001.jpg", blob: Data("JPEG".utf8))
        let ctx = try memoryContext()
        let pf = try XCTUnwrap(try MemoCloudIngest.ingest(memo: memo, assets: [photo],
                                                          upload: UploadService(outputDir: makeTempDir()), into: ctx))
        let images = URL(fileURLWithPath: pf.path).deletingLastPathComponent()
            .appendingPathComponent("images")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: images.path), ["img_001.jpg"])
    }

    /// A typed note born on the phone/iPad has the same shape and must ingest identically —
    /// this hole was never Mac-specific.
    private func typedMemo(text: String, significance: Double) throws -> Memo {
        let c = try ModelContainer(for: Memo.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let memo = try Memo.newTyped(into: ModelContext(c))
        memo.transcript = text
        memo.transcriptUserEdited = true
        memo.significance = significance
        return memo
    }
}
