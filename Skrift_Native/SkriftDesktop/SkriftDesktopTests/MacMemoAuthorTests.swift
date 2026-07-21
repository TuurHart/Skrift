import XCTest
import SwiftData
import Foundation

/// Tests for `MacMemoAuthor` — the Mac AUTHORS Memos ⑤ (Q5, 2026-07-21 lock): a locally
/// ingested file (the +Upload button / drag-drop / a future UploadService local caller) becomes
/// a synced `Memo` like any phone capture. Mirrors `MemoCloudReconcilerTests`' two-context style
/// (a cloud-shaped Memo/MemoAsset store, a local PipelineFile store) so these stay
/// host-less/MLX-free. `@MainActor` because the round-trip test below calls the (`@MainActor`)
/// `MemoCloudReconciler.sweep` directly.
@MainActor
final class MacMemoAuthorTests: XCTestCase {

    /// In-memory mirror of the CloudKit Memo store.
    private func cloudContext() throws -> ModelContext {
        let c = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    /// In-memory mirror of the local pipeline store.
    private func localContext() throws -> ModelContext {
        let c = try ModelContainer(for: PipelineFile.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    /// A REAL file on disk (not valid audio, but readable bytes) — enough to exercise
    /// `author`'s "is this URL actually a file I can read" path without an audio fixture.
    private func tempAudioFile(_ bytes: String = "AUDIO BYTES") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mma_\(UUID().uuidString).m4a")
        try? Data(bytes.utf8).write(to: url)
        return url
    }

    // MARK: - author: field mapping

    func testAuthorMapsFields() throws {
        let id = UUID()
        let recordedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let pf = PipelineFile(id: id.uuidString, filename: "Voice Memo.m4a",
                              sourceType: .audio, uploadedAt: recordedAt)
        pf.transcript = "hello from the mac"
        pf.significance = 0.6

        let ctx = try cloudContext()
        let memo = try XCTUnwrap(try MacMemoAuthor.author(for: pf, audioURL: nil, into: ctx))

        XCTAssertEqual(memo.id, id, "id derives from pf.id — the contract spine")
        XCTAssertEqual(memo.audioFilename, "Voice Memo.m4a")
        XCTAssertEqual(memo.recordedAt, recordedAt, "recordedAt maps from pf.uploadedAt (the CONTENT date)")
        XCTAssertEqual(memo.transcript, "hello from the mac")
        XCTAssertEqual(memo.transcriptStatus, .done)
        XCTAssertEqual(memo.transcriptConfidence, 1.0, "the Mac's own completed transcript is honestly confident")
        XCTAssertFalse(memo.transcriptUserEdited, "nobody edited it — that flag would be a lie")
        XCTAssertEqual(memo.significance, 0.6)
        XCTAssertEqual(memo.recordingDeviceID, DeviceID.current())
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Memo>()), 1)
    }

    func testAuthorFloorsUnratedSignificanceToPointOne() throws {
        let unrated = PipelineFile(id: UUID().uuidString, filename: "n.m4a", sourceType: .audio)
        let zero = PipelineFile(id: UUID().uuidString, filename: "n2.m4a", sourceType: .audio)
        zero.significance = 0
        let ctx = try cloudContext()

        let memo1 = try XCTUnwrap(try MacMemoAuthor.author(for: unrated, audioURL: nil, into: ctx))
        let memo2 = try XCTUnwrap(try MacMemoAuthor.author(for: zero, audioURL: nil, into: ctx))

        XCTAssertEqual(memo1.significance, 0.1, "nil significance floors to 0.1")
        XCTAssertEqual(memo2.significance, 0.1, "explicit 0 significance also floors to 0.1 — an unrated " +
                       "Mac capture the Mac silently processed must not lie on the phone's flag-to-process UI")
    }

    func testAuthorPreservesARealSignificanceAboveTheFloor() throws {
        let pf = PipelineFile(id: UUID().uuidString, filename: "n.m4a", sourceType: .audio)
        pf.significance = 0.9
        let ctx = try cloudContext()
        let memo = try XCTUnwrap(try MacMemoAuthor.author(for: pf, audioURL: nil, into: ctx))
        XCTAssertEqual(memo.significance, 0.9, "a real rating above the floor must pass through unchanged")
    }

    func testAuthorLeavesTranscriptPendingWhenPfHasNone() throws {
        let pf = PipelineFile(id: UUID().uuidString, filename: "n.m4a", sourceType: .audio)
        let ctx = try cloudContext()
        let memo = try XCTUnwrap(try MacMemoAuthor.author(for: pf, audioURL: nil, into: ctx))
        XCTAssertNil(memo.transcript)
        XCTAssertEqual(memo.transcriptStatus, .pending)
    }

    /// `PipelineFile` carries no duration field — `author` computes it off a REAL audio file when
    /// possible, but a locally-ingested-yet-unparseable "audio" file (matches this whole test
    /// suite's own fake-bytes-as-.m4a convention, see `UploadTests`/`MemoCloudIngestTests`) must
    /// never crash or block authoring — it just floors to 0, same as no audio at all.
    func testAuthorDurationFallsBackToZeroForUnparseableAudio() throws {
        let audioURL = tempAudioFile("not really audio")
        let pf = PipelineFile(id: UUID().uuidString, filename: "n.m4a", sourceType: .audio)
        let ctx = try cloudContext()
        let memo = try XCTUnwrap(try MacMemoAuthor.author(for: pf, audioURL: audioURL, into: ctx))
        XCTAssertEqual(memo.duration, 0)
    }

    // MARK: - author: idempotency + non-UUID

    func testAuthorIsIdempotent() throws {
        let pf = PipelineFile(id: UUID().uuidString, filename: "n.m4a", sourceType: .audio)
        let ctx = try cloudContext()
        XCTAssertNotNil(try MacMemoAuthor.author(for: pf, audioURL: nil, into: ctx))
        XCTAssertNil(try MacMemoAuthor.author(for: pf, audioURL: nil, into: ctx),
                    "a second author() for the same pf must not re-author")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Memo>()), 1)
    }

    func testAuthorSkipsNonUUIDId() throws {
        let pf = PipelineFile(id: "demo-1", filename: "n.m4a", sourceType: .audio)
        let ctx = try cloudContext()
        XCTAssertNil(try MacMemoAuthor.author(for: pf, audioURL: nil, into: ctx))
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Memo>()), 0)
    }

    // MARK: - author: audio asset attach

    func testAuthorAttachesAudioAssetWhenReadable() throws {
        let audioURL = tempAudioFile("REAL BYTES ON DISK")
        let pf = PipelineFile(id: UUID().uuidString, filename: "clip.m4a",
                              path: audioURL.path, sourceType: .audio)
        let ctx = try cloudContext()
        let memo = try XCTUnwrap(try MacMemoAuthor.author(for: pf, audioURL: audioURL, into: ctx))

        let assets = try ctx.fetch(FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == memo.id }))
        let asset = try XCTUnwrap(assets.first)
        XCTAssertEqual(asset.kind, MemoAsset.Kind.audio, "must match the phone's own constant byte-for-byte")
        XCTAssertEqual(asset.filename, "clip.m4a")
        XCTAssertEqual(asset.blob, Data("REAL BYTES ON DISK".utf8))
    }

    func testAuthorWithoutReadableAudioStillAuthorsTextOnly() throws {
        let pf = PipelineFile(id: UUID().uuidString, filename: "n.md", sourceType: .note)
        pf.transcript = "an apple note, no audio at all"
        let ctx = try cloudContext()
        let memo = try XCTUnwrap(try MacMemoAuthor.author(for: pf, audioURL: nil, into: ctx))
        XCTAssertEqual(memo.transcript, "an apple note, no audio at all")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<MemoAsset>()), 0, "honest text-only note beats no note")
    }

    // MARK: - backfill

    func testBackfillAuthorsOnlyOrphans() throws {
        let cloud = try cloudContext()
        let orphan = PipelineFile(id: UUID().uuidString, filename: "orphan.m4a",
                                  path: tempAudioFile().path, sourceType: .audio)
        let alreadyAuthoredID = UUID()
        let alreadyAuthoredPF = PipelineFile(id: alreadyAuthoredID.uuidString, filename: "already.m4a",
                                             path: tempAudioFile().path, sourceType: .audio)
        let demoRow = PipelineFile(id: "demo-1", filename: "demo.m4a", sourceType: .audio)

        // Pre-seed a memo for `alreadyAuthoredPF` — backfill must skip it (that pairing is
        // `reflectTranscripts`'s concern, not a fresh author).
        cloud.insert(Memo(id: alreadyAuthoredID, audioFilename: "already.m4a"))
        try cloud.save()

        let authored = try MacMemoAuthor.backfill(files: [orphan, alreadyAuthoredPF, demoRow], into: cloud)
        XCTAssertEqual(authored, 1)
        XCTAssertEqual(try cloud.fetchCount(FetchDescriptor<Memo>()), 2, "one pre-seeded + one newly authored")
    }

    /// Regression: `DemoSeed`'s `f7` row is deliberately UUID-shaped ("like a real synced memo",
    /// used to make a memo-link chip resolve in `-snapshot`/`-demo` renders) but sets no `path` —
    /// unlike every genuine local ingest, which always sets one. Caught while writing this test:
    /// gating only on `UUID(pf.id)` let `author`'s own "no audio → author text-only anyway"
    /// fallback leak a demo row's fabricated content into the store.
    func testBackfillSkipsUUIDRowWithNoRealPath() throws {
        let pf = PipelineFile(id: "9E8B7C6D-1111-4222-8333-444455556666",
                              filename: "Voice Memo 22-30.m4a", sourceType: .audio)
        pf.enhancedTitle = "Late-night audiobook capture flow"
        let ctx = try cloudContext()

        let authored = try MacMemoAuthor.backfill(files: [pf], into: ctx)

        XCTAssertEqual(authored, 0, "a pathless row must never leak a demo/synthetic memo into the store")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Memo>()), 0)
    }

    // MARK: - reflectTranscripts

    func testReflectTranscriptsFillsEmptyOnly() throws {
        let cloud = try cloudContext()
        let id = UUID()
        let memo = Memo(id: id, audioFilename: "n.m4a", recordingDeviceID: DeviceID.current())
        cloud.insert(memo)
        try cloud.save()

        let pf = PipelineFile(id: id.uuidString, filename: "n.m4a", sourceType: .audio)
        pf.transcript = "mac-transcribed after the fact"

        let reflected = try MacMemoAuthor.reflectTranscripts(files: [pf], into: cloud)

        XCTAssertEqual(reflected, 1)
        XCTAssertEqual(memo.transcript, "mac-transcribed after the fact")
        XCTAssertEqual(memo.transcriptStatus, .done)
    }

    func testReflectTranscriptsNeverClobbersExistingTranscript() throws {
        let cloud = try cloudContext()
        let id = UUID()
        let memo = Memo(id: id, audioFilename: "n.m4a", transcript: "the phone's own transcript",
                        transcriptStatus: .done, recordingDeviceID: DeviceID.current())
        cloud.insert(memo)
        try cloud.save()

        let pf = PipelineFile(id: id.uuidString, filename: "n.m4a", sourceType: .audio)
        pf.transcript = "a DIFFERENT mac transcript"

        let reflected = try MacMemoAuthor.reflectTranscripts(files: [pf], into: cloud)

        XCTAssertEqual(reflected, 0)
        XCTAssertEqual(memo.transcript, "the phone's own transcript",
                       "an already-filled memo transcript must never be overwritten")
    }

    func testReflectTranscriptsIsScopedToThisDevicesAuthoredMemos() throws {
        let cloud = try cloudContext()
        let id = UUID()
        // A memo recorded by SOME OTHER device (e.g. the phone) — reflecting a Mac re-ASR onto
        // it is the processing coordinator's business, not this sweep's.
        let memo = Memo(id: id, audioFilename: "n.m4a", recordingDeviceID: "some-other-device")
        cloud.insert(memo)
        try cloud.save()

        let pf = PipelineFile(id: id.uuidString, filename: "n.m4a", sourceType: .audio)
        pf.transcript = "the mac re-transcribed this phone memo"

        let reflected = try MacMemoAuthor.reflectTranscripts(files: [pf], into: cloud)

        XCTAssertEqual(reflected, 0)
        XCTAssertNil(memo.transcript, "reflecting onto a phone-originated memo is out of this lane's scope")
    }

    // MARK: - Round trip: author -> reconciler sweep creates NO second PipelineFile

    func testAuthorThenReconcilerSweepCreatesNoSecondPipelineFile() throws {
        let cloud = try cloudContext()
        let local = try localContext()

        let pf = PipelineFile(id: UUID().uuidString, filename: "roundtrip.m4a",
                              path: tempAudioFile().path, sourceType: .audio, uploadedAt: Date())
        pf.transcript = "authored locally, then swept"
        pf.significance = 0.4
        local.insert(pf)
        try local.save()

        XCTAssertEqual(try MacMemoAuthor.backfill(files: [pf], into: cloud), 1)
        XCTAssertEqual(try cloud.fetchCount(FetchDescriptor<Memo>()), 1)
        XCTAssertEqual(try local.fetchCount(FetchDescriptor<PipelineFile>()), 1, "still just the one pf we started with")

        // The EXISTING (untouched) reconciler sweep over the SAME two contexts — the authored
        // memo's id matches the pf's id exactly, so it must hit the REFLECT branch, not create
        // a second row.
        let outcome = MemoCloudReconciler.sweep(from: cloud, into: local, processEverything: false)

        XCTAssertEqual(outcome.created, 0, "the memo we just authored must dedup against the pf it was authored FROM")
        XCTAssertEqual(try local.fetchCount(FetchDescriptor<PipelineFile>()), 1)
    }
}
