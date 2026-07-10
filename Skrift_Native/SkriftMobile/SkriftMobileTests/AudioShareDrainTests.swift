import AVFoundation
import XCTest
@testable import SkriftMobile

/// Drain-side coverage for the `"audio"` inbox entries the share extension writes
/// (Wave-1 A7 + B1 — the i4 "WhatsApp voice note became a LINK" fix and the
/// 1-or-N chooser, mock `share-ingest-wave1.html` signed 2026-07-10). The loader
/// half (audio branch BEFORE url in `SharePayloadLoader`) lives in the extension
/// target and isn't linkable here — the device round covers it with a real
/// WhatsApp share.
final class AudioShareDrainTests: XCTestCase {

    @MainActor
    private func cleanInbox() throws -> URL {
        guard let inbox = CaptureInbox.inboxURL else {
            throw XCTSkip("no App Group container in this test host")
        }
        try? FileManager.default.removeItem(at: inbox)
        return inbox
    }

    private func makeClipFile() -> URL {
        let src = FileManager.default.temporaryDirectory
            .appendingPathComponent("src_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: src.path, contents: Data("AAC-ish".utf8))
        return src
    }

    /// A single-clip "audio" entry drains into a normal transcribed memo
    /// (audioFilename set — NOT a capture item), carries the sheet's
    /// significance, consumes the inbox entry, and requests the jump-to-note.
    @MainActor
    func testDrainImportsSharedAudioAsTranscribedMemo() throws {
        _ = try cleanInbox()
        let repo = NotesRepository(inMemory: true)

        let id = UUID()
        let entry = CaptureInboxEntry(
            id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0.4, sharedAt: ISO8601.string(from: Date()),
            audioFileNames: ["audio_\(id.uuidString)_0.m4a"])
        let src = makeClipFile()
        XCTAssertTrue(CaptureInbox.write(entry, audioFileURLs: [src]))

        CaptureInboxDrainer.drain(into: repo)

        XCTAssertTrue(CaptureInbox.pendingEntries().isEmpty, "entry consumed")
        // importAudioClips mints its own memo UUID — find it by the audio-memo shape.
        let imported = repo.allMemos().first { $0.audioFilename.hasPrefix("memo_") }
        XCTAssertNotNil(imported, "audio share becomes a normal memo, not a capture card")
        XCTAssertEqual(imported?.significance ?? 0, 0.4, accuracy: 0.001,
                       "sheet significance lands on the imported memo")
        XCTAssertEqual(MemoOpenBridge.shared.consume(), imported?.id,
                       "share requests the jump-to-note")

        if let f = imported?.audioURL { try? FileManager.default.removeItem(at: f) }
        try? FileManager.default.removeItem(at: src)
    }

    /// COMBINE (B1 default): one entry carrying N clip names drains into exactly
    /// ONE memo (the placeholder appears synchronously; the merge finishes async).
    @MainActor
    func testCombinedEntryMakesOneMemo() throws {
        _ = try cleanInbox()
        let repo = NotesRepository(inMemory: true)

        let id = UUID()
        let entry = CaptureInboxEntry(
            id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0.2, sharedAt: ISO8601.string(from: Date()),
            audioFileNames: ["audio_\(id.uuidString)_0.m4a", "audio_\(id.uuidString)_1.m4a"])
        let srcs = [makeClipFile(), makeClipFile()]
        XCTAssertTrue(CaptureInbox.write(entry, audioFileURLs: srcs))

        CaptureInboxDrainer.drain(into: repo)

        XCTAssertTrue(CaptureInbox.pendingEntries().isEmpty, "entry consumed")
        let memos = repo.allMemos()
        XCTAssertEqual(memos.count, 1, "2 clips + combine = ONE memo")
        XCTAssertEqual(memos.first?.significance ?? 0, 0.2, accuracy: 0.001)
        for s in srcs { try? FileManager.default.removeItem(at: s) }
        _ = MemoOpenBridge.shared.consume()   // drain the bridge for the next test
    }

    /// SPLIT (B1 alternative): the sheet writes N single-clip entries → N memos.
    @MainActor
    func testSplitEntriesMakeSeparateMemos() throws {
        _ = try cleanInbox()
        let repo = NotesRepository(inMemory: true)

        var srcs: [URL] = []
        for _ in 0..<2 {
            let id = UUID()
            let entry = CaptureInboxEntry(
                id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
                imageFileName: nil, mimeType: nil, annotationText: nil,
                significance: 0, sharedAt: ISO8601.string(from: Date()),
                audioFileNames: ["audio_\(id.uuidString)_0.m4a"])
            let src = makeClipFile()
            srcs.append(src)
            XCTAssertTrue(CaptureInbox.write(entry, audioFileURLs: [src]))
        }

        CaptureInboxDrainer.drain(into: repo)

        XCTAssertTrue(CaptureInbox.pendingEntries().isEmpty, "both entries consumed")
        XCTAssertEqual(repo.allMemos().count, 2, "split = one memo per voice note")
        for s in srcs { try? FileManager.default.removeItem(at: s) }
        _ = MemoOpenBridge.shared.consume()
    }

    /// An audio entry whose payload files vanished (failed inbox copy) is
    /// discarded rather than looping forever — and creates no memo.
    @MainActor
    func testAudioEntryWithoutFileIsDiscarded() throws {
        _ = try cleanInbox()
        let repo = NotesRepository(inMemory: true)

        let id = UUID()
        let entry = CaptureInboxEntry(
            id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0, sharedAt: ISO8601.string(from: Date()),
            audioFileNames: ["audio_\(id.uuidString)_0.m4a"])
        XCTAssertTrue(CaptureInbox.write(entry))   // no audioFileURLs → no payload files

        CaptureInboxDrainer.drain(into: repo)

        XCTAssertTrue(CaptureInbox.pendingEntries().isEmpty, "husk entry discarded")
        XCTAssertTrue(repo.allMemos().isEmpty, "no memo minted for a lost payload")
    }

    /// The signed jump-on-open rule covers plain captures too: a url capture's
    /// drain requests opening the new capture memo.
    @MainActor
    func testCaptureDrainAlsoRequestsJumpToNote() throws {
        _ = try cleanInbox()
        let repo = NotesRepository(inMemory: true)

        let entry = CaptureInboxEntry(
            id: UUID(), type: "url", url: "https://example.com", urlTitle: "Example",
            text: nil, imageFileName: nil, mimeType: nil,
            annotationText: nil, significance: 0,
            sharedAt: ISO8601.string(from: Date()))
        XCTAssertTrue(CaptureInbox.write(entry))

        CaptureInboxDrainer.drain(into: repo)

        XCTAssertEqual(MemoOpenBridge.shared.consume(), entry.id,
                       "every share type jumps to its note on next open")
    }

    /// Multi-photo capture (B2 — always ONE note): an entry with N image names +
    /// datas drains into one memo with an N-entry image manifest, in order.
    @MainActor
    func testMultiImageEntryBuildsManifestInOrder() throws {
        _ = try cleanInbox()
        let repo = NotesRepository(inMemory: true)

        let id = UUID()
        let names = ["capture_a.jpg", "capture_b.jpg"]
        let entry = CaptureInboxEntry(
            id: id, type: "image", url: nil, urlTitle: nil, text: nil,
            imageFileName: names[0], mimeType: "image/jpeg",
            annotationText: "two shots", significance: 0,
            sharedAt: ISO8601.string(from: Date()),
            imageFileNames: names)
        let datas = [Data("IMG-A".utf8), Data("IMG-B".utf8)]
        XCTAssertTrue(CaptureInbox.write(entry, imageDatas: datas))

        CaptureInboxDrainer.drain(into: repo)

        let memo = repo.memo(id: id)
        let manifest = memo?.metadata?.imageManifest ?? []
        XCTAssertEqual(manifest.count, 2, "one note, both photos in the manifest")
        XCTAssertEqual(manifest.map(\.filename),
                       ["photo_\(id.uuidString)_001.jpg", "photo_\(id.uuidString)_002.jpg"],
                       "manifest keeps share order")
        XCTAssertEqual(memo?.annotationText, "two shots\n\n[[img_001]]\n\n[[img_002]]",
                       "photos live IN the text as markers — the inline-note spec")
        for m in manifest {
            let url = AppPaths.recordingsDirectory.appendingPathComponent(m.filename)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            try? FileManager.default.removeItem(at: url)
        }
        _ = MemoOpenBridge.shared.consume()
    }

    /// Round-1 device bug: WhatsApp materializes all temp copies at share time →
    /// near-identical dates, and an unstable sort scrambled the chat order.
    func testStableClipOrder() {
        let d = Date()
        // Near-identical dates (< 2 s spread) → keep provider order.
        XCTAssertEqual(CaptureInbox.stableClipOrder(dates: [d, d.addingTimeInterval(0.5), d, d.addingTimeInterval(1)]),
                       [0, 1, 2, 3])
        // Any missing date → keep provider order.
        XCTAssertEqual(CaptureInbox.stableClipOrder(dates: [d, nil, d]), [0, 1, 2])
        // Genuinely distinct dates → oldest first; equal dates keep index order.
        let a = Date(timeIntervalSince1970: 100), b = Date(timeIntervalSince1970: 200)
        XCTAssertEqual(CaptureInbox.stableClipOrder(dates: [b, a, b]), [1, 0, 2])
        XCTAssertEqual(CaptureInbox.stableClipOrder(dates: []), [])
    }

    /// Round-1 device bug: an imported voice note was dated to the SHARE moment.
    /// The entry now carries the clip's original date and the memo adopts it.
    @MainActor
    func testDrainDatesAudioMemoToClipDate() throws {
        _ = try cleanInbox()
        let repo = NotesRepository(inMemory: true)

        let clipDate = "2026-07-01T10:00:00.000Z"
        let id = UUID()
        let entry = CaptureInboxEntry(
            id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0, sharedAt: ISO8601.string(from: Date()),
            audioFileNames: ["audio_\(id.uuidString)_0.m4a"],
            audioRecordedAts: [clipDate])
        let src = makeClipFile()
        XCTAssertTrue(CaptureInbox.write(entry, audioFileURLs: [src]))

        CaptureInboxDrainer.drain(into: repo)

        let imported = repo.allMemos().first { $0.audioFilename.hasPrefix("memo_") }
        let expected = try XCTUnwrap(ISO8601.date(from: clipDate))
        XCTAssertEqual(imported?.recordedAt.timeIntervalSince1970 ?? 0,
                       expected.timeIntervalSince1970, accuracy: 1.0,
                       "memo dated to the voice note, not the share moment")
        if let f = imported?.audioURL { try? FileManager.default.removeItem(at: f) }
        try? FileManager.default.removeItem(at: src)
        _ = MemoOpenBridge.shared.consume()
    }

    /// Old inbox entries (written before audio/multi-image shares existed) decode.
    func testEntryWithoutNewFieldsDecodes() throws {
        let legacyJSON = """
        {"id":"6E1AD320-DC78-4B28-8DF7-52BDB461A324","type":"url","url":"https://a.com",
        "urlTitle":"A","text":null,"imageFileName":null,"mimeType":null,
        "annotationText":"x","significance":0.3,"sharedAt":"2026-06-12T10:00:00.000Z"}
        """
        let entry = try JSONDecoder().decode(CaptureInboxEntry.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(entry.audioFileNames)
        XCTAssertNil(entry.imageFileNames)
        XCTAssertEqual(entry.type, "url")
    }

    // MARK: - Merge core (real audio)

    /// End-to-end combine on REAL audio: two half-second silence files merge into
    /// one memo whose duration is their sum and whose transcript comes from one
    /// transcription pass over the merged file.
    @MainActor
    func testImportAudioClipsMergesRealClips() async throws {
        let repo = NotesRepository(inMemory: true)
        let saver = MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: "merged story"),
            wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
            metadataProvider: MockMetadataService()
        )

        let clips = [try Self.writeSilence(seconds: 0.5), try Self.writeSilence(seconds: 0.5)]
        let id = UUID()
        repo.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a",
                         duration: 0, syncStatus: .waiting, transcriptStatus: .transcribing))

        let ok = await saver.importAudioClipsAsync(id: id, sources: clips)

        XCTAssertTrue(ok, "merge of two readable clips succeeds")
        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.duration ?? 0, 1.0, accuracy: 0.3, "duration ≈ clips summed")
        XCTAssertEqual(memo?.transcript, "merged story", "one transcription over the merged file")
        XCTAssertEqual(memo?.transcriptStatus, .done)
        if let f = memo?.audioURL { try? FileManager.default.removeItem(at: f) }
    }

    /// Merge with NOTHING readable fails honestly: memo → .failed with a reason
    /// title, never a silent husk.
    @MainActor
    func testImportAudioClipsFailsHonestlyOnGarbage() async {
        let repo = NotesRepository(inMemory: true)
        let saver = MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: "unused"),
            wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
            metadataProvider: MockMetadataService()
        )
        let garbage = FileManager.default.temporaryDirectory
            .appendingPathComponent("garbage_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: garbage.path, contents: Data([0x00, 0x01]))
        let id = UUID()
        repo.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a",
                         duration: 0, syncStatus: .waiting, transcriptStatus: .transcribing))

        let ok = await saver.importAudioClipsAsync(id: id, sources: [garbage, garbage])

        XCTAssertFalse(ok)
        XCTAssertEqual(repo.memo(id: id)?.transcriptStatus, .failed)
        XCTAssertEqual(repo.memo(id: id)?.title, "Couldn't read the shared audio")
        try? FileManager.default.removeItem(at: garbage)
    }

    /// Half a second of silence as a real, AVFoundation-readable audio file.
    private static func writeSilence(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip_\(UUID().uuidString).caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let frames = AVAudioFrameCount(16000 * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw NSError(domain: "AudioShareDrainTests", code: 1)
        }
        buffer.frameLength = frames
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}
