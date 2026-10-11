import XCTest
import SwiftData
@testable import SkriftMobile

/// Q343 (Tuur 2026-10-11, feedback 2b8bc952): a photo taken while recording the ramble on an
/// audiobook quote was dropped. The quote's ramble rides `RecordView(appendTo:)` →
/// `MemoSaver.appendRecording`, which never took the camera's photos (only the new-note branch
/// called `camera.takeAll()`), so the note said "and then a picture of a trash can" with no
/// picture. A photo taken mid-append must land in the body as a `[[img_NNN]]` marker (C11/C13
/// timed placement, numbered past the memo's existing pictures) AND as a `MemoAsset`.
@MainActor
final class QuoteCapturePhotoTests: XCTestCase {

    private let fm = FileManager.default
    private var cleanup: [URL] = []
    override func tearDown() {
        cleanup.forEach { try? fm.removeItem(at: $0) }
        cleanup = []
        super.tearDown()
    }

    private func saver(_ repo: NotesRepository, transcriber: any Transcribing) -> MemoSaver {
        MemoSaver(
            repository: repo,
            transcriber: transcriber,
            wordTimings: WordTimingsStore(directory: fm.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
            metadataProvider: MockMetadataService()
        )
    }

    private func tempFile(_ prefix: String, _ bytes: String) -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent("\(prefix)_\(UUID().uuidString)")
        fm.createFile(atPath: url.path, contents: Data(bytes.utf8))
        cleanup.append(url)
        return url
    }

    /// A quote memo the way `saveQuoteCapture` leaves it: blockquote body + the quote audio.
    private func quoteMemo(_ repo: NotesRepository, id: UUID = UUID(), manifest: [ImageManifestEntry]? = nil,
                           transcript: String = "> The first complete Odyssey.") -> UUID {
        let filename = "memo_\(id.uuidString).m4a"
        try? fm.createDirectory(at: AppPaths.recordingsDirectory, withIntermediateDirectories: true)
        let url = AppPaths.recordingsDirectory.appendingPathComponent(filename)
        fm.createFile(atPath: url.path, contents: Data("QUOTE-AUDIO".utf8))
        cleanup.append(url)
        repo.insert(Memo(id: id, audioFilename: filename, duration: 4, recordedAt: Date(),
                         transcript: transcript, transcriptStatus: .done, transcriptConfidence: 1))
        if let manifest {
            repo.memo(id: id)?.metadata = MemoMetadata(imageManifest: manifest)
        }
        return id
    }

    func testPhotoTakenWhileRecordingTheRambleLandsAsMarkerAndAsset() async throws {
        let repo = NotesRepository(inMemory: true)
        let id = quoteMemo(repo)
        // SeededTranscriber: 0.3 s per word.
        let s = saver(repo, transcriber: SeededTranscriber(text: "More blah blah. And then a picture of a trash can."))
        let clip = tempFile("ramble", "MORE")
        let photo = tempFile("cap", "JPEG")

        await s.appendRecordingAsync(to: id, tempURL: clip, photos: [(url: photo, offset: 1.0)])

        let memo = try XCTUnwrap(repo.memo(id: id))
        let manifest = try XCTUnwrap(memo.metadata?.imageManifest)
        XCTAssertEqual(manifest.count, 1, "the photo must be in the memo's manifest")
        cleanup.append(AppPaths.recordingsDirectory.appendingPathComponent(manifest[0].filename))
        XCTAssertEqual(manifest[0].filename, "photo_\(id.uuidString)_001.jpg")
        XCTAssertTrue(fm.fileExists(atPath: AppPaths.recordingsDirectory.appendingPathComponent(manifest[0].filename).path))
        XCTAssertFalse(fm.fileExists(atPath: photo.path), "the camera temp file is moved, not copied")
        let body = try XCTUnwrap(memo.transcript)
        XCTAssertEqual(BodyV2Marker.numbers(in: body), [1], "the photo must be a marker in the body: \(body)")
        XCTAssertTrue(body.hasPrefix("> The first complete Odyssey."), "the quote stays on top")

        // And it syncs: a MemoAsset (kind photo) for the file.
        AssetMaterializer.capture(memoID: id, repository: repo)
        let photos = repo.assets(forMemo: id).filter { $0.kind == MemoAsset.Kind.photo }
        XCTAssertEqual(photos.map(\.filename), [manifest[0].filename])
    }

    func testPhotoNumbersContinuePastExistingPictures() async throws {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let existing = ImageManifestEntry(filename: "photo_\(id.uuidString)_001.jpg", offsetSeconds: 0)
        _ = quoteMemo(repo, id: id, manifest: [existing],
                      transcript: "> quote\n\n[[img_001]]\n\nfirst words.")
        let s = saver(repo, transcriber: SeededTranscriber(text: "second words here and there."))
        let photo = tempFile("cap", "JPEG")

        await s.appendRecordingAsync(to: id, tempURL: tempFile("ramble", "MORE"),
                                     photos: [(url: photo, offset: 0.5)])

        let memo = try XCTUnwrap(repo.memo(id: id))
        let manifest = try XCTUnwrap(memo.metadata?.imageManifest)
        XCTAssertEqual(manifest.map(\.filename), [existing.filename, "photo_\(id.uuidString)_002.jpg"])
        cleanup.append(AppPaths.recordingsDirectory.appendingPathComponent(manifest[1].filename))
        XCTAssertEqual(Set(BodyV2Marker.numbers(in: try XCTUnwrap(memo.transcript))), [1, 2])
    }

    func testPhotoSurvivesAnAppendWhoseTranscriptionHeardNothing() async throws {
        let repo = NotesRepository(inMemory: true)
        let id = quoteMemo(repo)
        // Engine heard nothing → no new text; the picture must still be kept AND placed.
        let s = saver(repo, transcriber: SeededTranscriber(text: ""))
        let photo = tempFile("cap", "JPEG")

        await s.appendRecordingAsync(to: id, tempURL: tempFile("ramble", "MORE"),
                                     photos: [(url: photo, offset: 0.5)])

        let memo = try XCTUnwrap(repo.memo(id: id))
        let manifest = try XCTUnwrap(memo.metadata?.imageManifest)
        XCTAssertEqual(manifest.count, 1)
        cleanup.append(AppPaths.recordingsDirectory.appendingPathComponent(manifest[0].filename))
        XCTAssertEqual(BodyV2Marker.numbers(in: try XCTUnwrap(memo.transcript)), [1])
        XCTAssertEqual(memo.transcriptStatus, .done)
    }
}
