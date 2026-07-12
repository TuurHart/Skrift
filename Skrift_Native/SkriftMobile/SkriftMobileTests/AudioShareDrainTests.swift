import AVFoundation
import UIKit
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
    func testDrainImportsSharedAudioAsTranscribedMemo() async throws {
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

        await CaptureInboxDrainer.drain(into: repo)

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
    func testCombinedEntryMakesOneMemo() async throws {
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

        await CaptureInboxDrainer.drain(into: repo)

        XCTAssertTrue(CaptureInbox.pendingEntries().isEmpty, "entry consumed")
        let memos = repo.allMemos()
        XCTAssertEqual(memos.count, 1, "2 clips + combine = ONE memo")
        XCTAssertEqual(memos.first?.significance ?? 0, 0.2, accuracy: 0.001)
        for s in srcs { try? FileManager.default.removeItem(at: s) }
        _ = MemoOpenBridge.shared.consume()   // drain the bridge for the next test
    }

    /// SPLIT (B1 alternative): the sheet writes N single-clip entries → N memos.
    @MainActor
    func testSplitEntriesMakeSeparateMemos() async throws {
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

        await CaptureInboxDrainer.drain(into: repo)

        XCTAssertTrue(CaptureInbox.pendingEntries().isEmpty, "both entries consumed")
        XCTAssertEqual(repo.allMemos().count, 2, "split = one memo per voice note")
        for s in srcs { try? FileManager.default.removeItem(at: s) }
        _ = MemoOpenBridge.shared.consume()
    }

    /// An audio entry whose payload files vanished (failed inbox copy) is
    /// discarded rather than looping forever — and creates no memo.
    @MainActor
    func testAudioEntryWithoutFileIsDiscarded() async throws {
        _ = try cleanInbox()
        let repo = NotesRepository(inMemory: true)

        let id = UUID()
        let entry = CaptureInboxEntry(
            id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0, sharedAt: ISO8601.string(from: Date()),
            audioFileNames: ["audio_\(id.uuidString)_0.m4a"])
        XCTAssertTrue(CaptureInbox.write(entry))   // no audioFileURLs → no payload files

        await CaptureInboxDrainer.drain(into: repo)

        XCTAssertTrue(CaptureInbox.pendingEntries().isEmpty, "husk entry discarded")
        XCTAssertTrue(repo.allMemos().isEmpty, "no memo minted for a lost payload")
    }

    /// The signed jump-on-open rule covers plain captures too: a url capture's
    /// drain requests opening the new capture memo.
    @MainActor
    func testCaptureDrainAlsoRequestsJumpToNote() async throws {
        _ = try cleanInbox()
        let repo = NotesRepository(inMemory: true)

        let entry = CaptureInboxEntry(
            id: UUID(), type: "url", url: "https://example.com", urlTitle: "Example",
            text: nil, imageFileName: nil, mimeType: nil,
            annotationText: nil, significance: 0,
            sharedAt: ISO8601.string(from: Date()))
        XCTAssertTrue(CaptureInbox.write(entry))

        await CaptureInboxDrainer.drain(into: repo)

        XCTAssertEqual(MemoOpenBridge.shared.consume(), entry.id,
                       "every share type jumps to its note on next open")
    }

    /// C5: a url capture whose URL points at a PDF downloads it on drain and lands
    /// as a normal FILE capture (file:// exercises the exact URLSession path the
    /// https share takes, minus the network).
    @MainActor
    func testPdfUrlCaptureBecomesFileCapture() async throws {
        _ = try cleanInbox()
        let repo = NotesRepository(inMemory: true)

        let src = FileManager.default.temporaryDirectory.appendingPathComponent("Remote Doc.pdf")
        FileManager.default.createFile(atPath: src.path, contents: Data("%PDF-1.4 fake".utf8))
        defer { try? FileManager.default.removeItem(at: src) }

        let entry = CaptureInboxEntry(
            id: UUID(), type: "url", url: src.absoluteString, urlTitle: nil,
            text: nil, imageFileName: nil, mimeType: nil,
            annotationText: "the spec pdf", significance: 0,
            sharedAt: ISO8601.string(from: Date()))
        XCTAssertTrue(CaptureInbox.write(entry))

        await CaptureInboxDrainer.drain(into: repo)

        let memo = repo.memo(id: entry.id)
        XCTAssertEqual(memo?.sharedContent?.type, .file, "pdf link → file capture")
        XCTAssertEqual(memo?.sharedContent?.fileName, "Remote Doc.pdf")
        XCTAssertEqual(memo?.sharedContent?.mimeType, "application/pdf")
        let fileURL = try XCTUnwrap(memo?.sharedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "the PDF is persisted")
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// C5 content-type gate (device round 2: arxiv's `/pdf/2406.19741` links are
    /// EXTENSIONLESS — the HEAD sniff catches what the extension check can't).
    func testPdfContentTypeGate() {
        XCTAssertTrue(CaptureInboxDrainer.isPDFContentType("application/pdf"))
        XCTAssertTrue(CaptureInboxDrainer.isPDFContentType("application/pdf; qs=0.001"), "arxiv's actual header")
        XCTAssertTrue(CaptureInboxDrainer.isPDFContentType("APPLICATION/PDF; charset=binary"))
        XCTAssertFalse(CaptureInboxDrainer.isPDFContentType("text/html; charset=utf-8"))
        XCTAssertFalse(CaptureInboxDrainer.isPDFContentType("application/pdf-ish"))
        XCTAssertFalse(CaptureInboxDrainer.isPDFContentType(nil))
    }

    /// C5 fallback: a .pdf link whose payload ISN'T a PDF (or fails to fetch)
    /// stays a plain url capture — the link is never lost.
    @MainActor
    func testPdfUrlSniffFailureKeepsLinkCard() async throws {
        _ = try cleanInbox()
        let repo = NotesRepository(inMemory: true)

        let src = FileManager.default.temporaryDirectory.appendingPathComponent("not-really.pdf")
        FileManager.default.createFile(atPath: src.path, contents: Data("<html>nope</html>".utf8))
        defer { try? FileManager.default.removeItem(at: src) }

        let entry = CaptureInboxEntry(
            id: UUID(), type: "url", url: src.absoluteString, urlTitle: "Nope",
            text: nil, imageFileName: nil, mimeType: nil,
            annotationText: nil, significance: 0,
            sharedAt: ISO8601.string(from: Date()))
        XCTAssertTrue(CaptureInbox.write(entry))

        await CaptureInboxDrainer.drain(into: repo)

        let memo = repo.memo(id: entry.id)
        XCTAssertEqual(memo?.sharedContent?.type, .url, "non-PDF payload keeps the link card")
        XCTAssertEqual(memo?.sharedContent?.url, src.absoluteString)
    }

    /// D4: a shared .md/.txt file becomes the note CONTENT (body below the typed
    /// ramble), not a file card — no document blob kept.
    @MainActor
    func testTextFileBecomesNoteBody() async throws {
        _ = try cleanInbox()
        let repo = NotesRepository(inMemory: true)

        let id = UUID()
        let entry = CaptureInboxEntry(
            id: id, type: "file", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: "text/markdown",
            annotationText: "my ramble about this", significance: 0,
            sharedAt: ISO8601.string(from: Date()),
            fileName: "file_\(id.uuidString).md",
            fileDisplayName: "Meeting Notes.md")
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("src_\(UUID().uuidString).md")
        FileManager.default.createFile(atPath: src.path, contents: Data("# Standup\n\n- decided X".utf8))
        defer { try? FileManager.default.removeItem(at: src) }
        XCTAssertTrue(CaptureInbox.write(entry, fileSourceURL: src))

        await CaptureInboxDrainer.drain(into: repo)

        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.sharedContent?.type, .text, "text file → text capture, not a file card")
        XCTAssertEqual(memo?.sharedContent?.fileName, "Meeting Notes.md", "provenance kept")
        XCTAssertNil(memo?.sharedContent?.text, "no pinned quote block — the text IS the body")
        XCTAssertEqual(memo?.annotationText, "my ramble about this\n\n# Standup\n\n- decided X",
                       "ramble first, file content as the body")
    }

    /// D4 guard: a text file that isn't UTF-8 stays a document card.
    @MainActor
    func testBinaryTxtStaysFileCard() async throws {
        _ = try cleanInbox()
        let repo = NotesRepository(inMemory: true)

        let id = UUID()
        let entry = CaptureInboxEntry(
            id: id, type: "file", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: "text/plain",
            annotationText: nil, significance: 0,
            sharedAt: ISO8601.string(from: Date()),
            fileName: "file_\(id.uuidString).txt",
            fileDisplayName: "weird.txt")
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("src_\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: src.path, contents: Data([0xFF, 0xFE, 0x00, 0xD8]))
        defer { try? FileManager.default.removeItem(at: src) }
        XCTAssertTrue(CaptureInbox.write(entry, fileSourceURL: src))

        await CaptureInboxDrainer.drain(into: repo)

        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.sharedContent?.type, .file, "undecodable text stays a document")
        if let fileURL = memo?.sharedFileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    /// A6: a shared PDF's embedded text is extracted on drain into
    /// sharedContent.text — the memo becomes full-text searchable (MemoDisplay
    /// .matches already reads that field).
    @MainActor
    func testSharedPdfTextExtractedAndSearchable() async throws {
        _ = try cleanInbox()
        let repo = NotesRepository(inMemory: true)

        // A real PDF with real text (CoreText-drawn → embedded, not rasterized).
        let pdfURL = FileManager.default.temporaryDirectory.appendingPathComponent("pdf_\(UUID().uuidString).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            ("Quarterly synergy flamingo report" as NSString)
                .draw(at: CGPoint(x: 72, y: 72), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
        }
        try data.write(to: pdfURL)
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let id = UUID()
        let entry = CaptureInboxEntry(
            id: id, type: "file", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: "application/pdf",
            annotationText: nil, significance: 0,
            sharedAt: ISO8601.string(from: Date()),
            fileName: "file_\(id.uuidString).pdf",
            fileDisplayName: "report.pdf")
        XCTAssertTrue(CaptureInbox.write(entry, fileSourceURL: pdfURL))

        await CaptureInboxDrainer.drain(into: repo)

        let memo = try XCTUnwrap(repo.memo(id: id))
        XCTAssertEqual(memo.sharedContent?.type, .file)
        XCTAssertTrue(memo.sharedContent?.text?.contains("flamingo") == true,
                      "PDF text extracted into sharedContent.text")
        XCTAssertTrue(memo.matches(query: "flamingo"), "shared PDF is now searchable")
        if let f = memo.sharedFileURL { try? FileManager.default.removeItem(at: f) }
    }

    /// A4: an image capture dates to the photos' EARLIEST EXIF taken-date, not
    /// the share moment ("" entries = no metadata, ignored).
    @MainActor
    func testImageCaptureDatesToEarliestExif() async throws {
        _ = try cleanInbox()
        let repo = NotesRepository(inMemory: true)

        let id = UUID()
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])   // enough for the copy path
        let entry = CaptureInboxEntry(
            id: id, type: "image", url: nil, urlTitle: nil, text: nil,
            imageFileName: "a.jpg", mimeType: "image/jpeg",
            annotationText: nil, significance: 0,
            sharedAt: ISO8601.string(from: Date()),
            imageFileNames: ["a.jpg", "b.jpg", "c.jpg"],
            imageRecordedAts: ["2026-07-04T10:00:00.000Z", "2026-07-03T09:30:00.000Z", ""])
        XCTAssertTrue(CaptureInbox.write(entry, imageDatas: [jpeg, jpeg, jpeg]))

        await CaptureInboxDrainer.drain(into: repo)

        let memo = try XCTUnwrap(repo.memo(id: id))
        let expected = try XCTUnwrap(ISO8601.date(from: "2026-07-03T09:30:00.000Z"))
        XCTAssertEqual(memo.recordedAt.timeIntervalSince1970, expected.timeIntervalSince1970,
                       accuracy: 1.0, "memo dated to the earliest photo, not the share time")
        for name in memo.metadata?.imageManifest?.map(\.filename) ?? [] {
            try? FileManager.default.removeItem(at: AppPaths.recordingsDirectory.appendingPathComponent(name))
        }
    }

    /// D6: a Maps share drains into a place-anchored url capture — location chip
    /// metadata set, place-searchable, card title falls back to the place name.
    @MainActor
    func testMapsShareBecomesPlaceNote() async throws {
        _ = try cleanInbox()
        let repo = NotesRepository(inMemory: true)

        let entry = CaptureInboxEntry(
            id: UUID(), type: "url",
            url: "https://maps.apple.com/?ll=38.7223,-9.1393&q=Hotel%20Du%20Vin",
            urlTitle: nil, text: nil, imageFileName: nil, mimeType: nil,
            annotationText: "dinner spot for Friday", significance: 0,
            sharedAt: ISO8601.string(from: Date()))
        XCTAssertTrue(CaptureInbox.write(entry))

        await CaptureInboxDrainer.drain(into: repo)

        let memo = try XCTUnwrap(repo.memo(id: entry.id))
        XCTAssertEqual(memo.sharedContent?.type, .url, "still a link card — it opens Maps")
        XCTAssertEqual(memo.metadata?.location?.placeName, "Hotel Du Vin")
        XCTAssertEqual(memo.metadata?.location?.latitude ?? 0, 38.7223, accuracy: 0.001)
        XCTAssertEqual(memo.sharedContent?.urlTitle, "Hotel Du Vin", "place name titles the card")
        XCTAssertTrue(memo.matches(query: "hotel du vin"), "place-searchable")
    }

    /// E2: an audio entry the sheet routed to Books imports as an AUDIOBOOK in
    /// the library — no memo. (The sheet's 1-hour threshold is extension-target
    /// code — the device round covers it; this proves the drain routing.)
    @MainActor
    func testBooksRoutedAudioImportsAsAudiobook() async throws {
        _ = try cleanInbox()
        let repo = NotesRepository(inMemory: true)
        let store = AudiobookLibraryStore.shared
        let preexisting = Set(store.books.map(\.id))

        let id = UUID()
        let entry = CaptureInboxEntry(
            id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0, sharedAt: ISO8601.string(from: Date()),
            audioFileNames: ["audio_\(id.uuidString)_0.m4a"],
            audioRecordedAts: [""],
            routeToBooks: true)
        let clip = try Self.writeSilence(seconds: 0.5)
        XCTAssertTrue(CaptureInbox.write(entry, audioFileURLs: [clip]))

        await CaptureInboxDrainer.drain(into: repo)

        let newBooks = store.books.filter { !preexisting.contains($0.id) }
        XCTAssertEqual(newBooks.count, 1, "the share landed in the audiobook library")
        XCTAssertTrue(repo.allMemos().isEmpty, "no memo for a Books-routed share")
        for b in newBooks { store.remove(b) }
        try? FileManager.default.removeItem(at: clip)
    }

    /// E2 fallback: when the Books import can't read the clip, the share falls
    /// through to the normal memo import — the audio is never lost.
    @MainActor
    func testBooksRouteFallsBackToMemoOnUnreadableClip() async throws {
        _ = try cleanInbox()
        let repo = NotesRepository(inMemory: true)
        let store = AudiobookLibraryStore.shared
        let preexisting = Set(store.books.map(\.id))

        let id = UUID()
        let entry = CaptureInboxEntry(
            id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0, sharedAt: ISO8601.string(from: Date()),
            audioFileNames: ["audio_\(id.uuidString)_0.m4a"],
            audioRecordedAts: [""],
            routeToBooks: true)
        let garbage = makeClipFile()   // "AAC-ish" bytes — unreadable as a book
        XCTAssertTrue(CaptureInbox.write(entry, audioFileURLs: [garbage]))

        await CaptureInboxDrainer.drain(into: repo)

        XCTAssertTrue(store.books.allSatisfy { preexisting.contains($0.id) }, "no book added")
        let imported = repo.allMemos().first { $0.audioFilename.hasPrefix("memo_") }
        XCTAssertNotNil(imported, "fell back to the memo import — audio never lost")
        _ = MemoOpenBridge.shared.consume()
        try? FileManager.default.removeItem(at: garbage)
    }

    /// Poison-pill guard (device round 2026-07-11): an entry whose dir can't be
    /// DELETED must be tombstoned and never drain again — video/audio entries
    /// mint fresh memo UUIDs, so before this an undeletable entry spawned a new
    /// failed memo + duplicate audiobook on EVERY app open.
    @MainActor
    func testUndeletableEntryIsTombstonedAndSkipped() throws {
        let inbox = try cleanInbox()
        UserDefaults.standard.removeObject(forKey: "skrift.captureInbox.tombstones")
        defer { UserDefaults.standard.removeObject(forKey: "skrift.captureInbox.tombstones") }

        let entry = CaptureInboxEntry(
            id: UUID(), type: "text", url: nil, urlTitle: nil, text: "x",
            imageFileName: nil, mimeType: nil, annotationText: "y", significance: 0,
            sharedAt: ISO8601.string(from: Date()))
        XCTAssertTrue(CaptureInbox.write(entry))
        let entryDir = inbox.appendingPathComponent(entry.id.uuidString, isDirectory: true)

        // A read-only PARENT makes the dir removal fail — the permission edge.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: inbox.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: inbox.path) }

        CaptureInbox.delete(entryDir: entryDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: entryDir.path),
                      "precondition: the delete really failed")
        XCTAssertTrue(CaptureInbox.tombstonedIDs().contains(entry.id.uuidString))
        XCTAssertTrue(CaptureInbox.pendingEntries().isEmpty, "tombstoned entry never drains again")
    }

    /// A14 pending indicator: after a drain the published count is back to zero
    /// (the pill must never stick), and the entry landed as a memo.
    @MainActor
    func testDrainStateReturnsToZero() async throws {
        _ = try cleanInbox()
        let repo = NotesRepository(inMemory: true)

        let entry = CaptureInboxEntry(
            id: UUID(), type: "text", url: nil, urlTitle: nil, text: "hello",
            imageFileName: nil, mimeType: nil, annotationText: "a note",
            significance: 0, sharedAt: ISO8601.string(from: Date()))
        XCTAssertTrue(CaptureInbox.write(entry))

        await CaptureInboxDrainer.drain(into: repo)

        XCTAssertEqual(CaptureDrainState.shared.pendingCount, 0, "pill state cleared")
        XCTAssertNotNil(repo.memo(id: entry.id), "entry drained into a memo")
    }

    /// Multi-photo capture (B2 — always ONE note): an entry with N image names +
    /// datas drains into one memo with an N-entry image manifest, in order.
    @MainActor
    func testMultiImageEntryBuildsManifestInOrder() async throws {
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

        await CaptureInboxDrainer.drain(into: repo)

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
    func testDrainDatesAudioMemoToClipDate() async throws {
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

        await CaptureInboxDrainer.drain(into: repo)

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
