import XCTest
import SwiftData
@testable import SkriftMobile

/// Q346: a typed note has no audio (`audioFilename == ""`). Both UI doors to "Add recording"
/// reach it: the quick note's plus (`QuickNoteView` after the first keystroke, `Memo.newTyped`) and a
/// typed note's ellipsis Add recording (`MemoDetailView`, hidden only for share captures, whose
/// `sharedContent` is set). `MemoSaver.appendRecordingAsync` used to bail on `memo.audioURL == nil`
/// and DELETE the clip, so a recording made on a typed note vanished without a trace.
/// Now the note's first recording becomes its audio and the clip's words follow the typed body.
@MainActor
final class AppendToTypedNoteTests: XCTestCase {

    private let fm = FileManager.default
    private var cleanup: [URL] = []
    override func tearDown() {
        cleanup.forEach { try? fm.removeItem(at: $0) }
        cleanup = []
        super.tearDown()
    }

    private func saver(_ repo: NotesRepository, transcriber: any Transcribing,
                       timings: WordTimingsStore? = nil) -> MemoSaver {
        MemoSaver(
            repository: repo,
            transcriber: transcriber,
            wordTimings: timings ?? WordTimingsStore(directory: fm.temporaryDirectory
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

    /// A typed note exactly as the quick note and the Mac author leave it.
    private func typedNote(_ repo: NotesRepository, body: String?) throws -> UUID {
        let memo = try Memo.newTyped(into: repo.context)
        memo.transcript = body
        try repo.context.save()
        XCTAssertTrue(memo.audioFilename.isEmpty, "precondition: a typed note has no audio")
        XCTAssertNil(memo.audioURL)
        return memo.id
    }

    private func audioURL(_ id: UUID) -> URL {
        AppPaths.recordingsDirectory.appendingPathComponent("memo_\(id.uuidString).m4a")
    }

    func testClipRecordedOnATypedNoteBecomesItsAudioAndItsWordsFollowTheBody() async throws {
        let repo = NotesRepository(inMemory: true)
        let id = try typedNote(repo, body: "Typed first.")
        cleanup.append(audioURL(id))
        let s = saver(repo, transcriber: SeededTranscriber(text: "spoken words here"))
        let clip = tempFile("clip", "CLIP-AUDIO")

        await s.appendRecordingAsync(to: id, tempURL: clip)

        let memo = try XCTUnwrap(repo.memo(id: id))
        XCTAssertEqual(memo.audioFilename, "memo_\(id.uuidString).m4a", "the first recording becomes the note's audio")
        XCTAssertEqual(try? Data(contentsOf: audioURL(id)), Data("CLIP-AUDIO".utf8), "the clip's bytes are the audio")
        XCTAssertEqual(memo.transcript, "Typed first.\n\nspoken words here")
        XCTAssertTrue(memo.transcriptUserEdited, "the Mac must trust the combined body as-is")
        XCTAssertEqual(memo.transcriptStatus, .done)
        XCTAssertGreaterThan(memo.duration, 0, "the player needs a duration")
        XCTAssertFalse(fm.fileExists(atPath: clip.path), "the temp clip is moved, not copied")
        XCTAssertEqual(SourceKind.of(memo), .typedNote, "it stays a note you wrote")

        // And it syncs: the audio is queued as a MemoAsset (the saver does this in a detached task
        // after the append; run it here so the test does not race that task).
        AssetMaterializer.capture(memoID: id, repository: repo)
        let audio = repo.assets(forMemo: id).filter { $0.kind == MemoAsset.Kind.audio }
        XCTAssertEqual(audio.map(\.filename), [memo.audioFilename])
    }

    func testWordTimingsOfTheFirstClipAreNotShifted() async throws {
        let repo = NotesRepository(inMemory: true)
        let id = try typedNote(repo, body: "Typed first.")
        cleanup.append(audioURL(id))
        let store = WordTimingsStore(directory: fm.temporaryDirectory
            .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true))
        let s = saver(repo, transcriber: SeededTranscriber(text: "one two"), timings: store)

        await s.appendRecordingAsync(to: id, tempURL: tempFile("clip", "CLIP-AUDIO"))

        let timings = try XCTUnwrap(store.load(for: id))
        XCTAssertEqual(timings.map(\.word), ["one", "two"])
        XCTAssertEqual(timings.first?.start ?? -1, 0, accuracy: 0.001, "the clip IS the audio: no prior audio to shift past")
    }

    func testAnEmptyTypedNoteTakesTheClipWordsAlone() async throws {
        let repo = NotesRepository(inMemory: true)
        let id = try typedNote(repo, body: nil)
        cleanup.append(audioURL(id))
        let s = saver(repo, transcriber: SeededTranscriber(text: "just spoken"))

        await s.appendRecordingAsync(to: id, tempURL: tempFile("clip", "CLIP-AUDIO"))

        let memo = try XCTUnwrap(repo.memo(id: id))
        XCTAssertEqual(memo.transcript, "just spoken")
        XCTAssertEqual(memo.audioFilename, "memo_\(id.uuidString).m4a")
    }

    func testAClipThatHeardNothingStillBecomesTheAudioAndTheTypedBodyIsUntouched() async throws {
        let repo = NotesRepository(inMemory: true)
        let id = try typedNote(repo, body: "Typed first.")
        cleanup.append(audioURL(id))
        let s = saver(repo, transcriber: SeededTranscriber(text: ""))

        await s.appendRecordingAsync(to: id, tempURL: tempFile("clip", "CLIP-AUDIO"))

        let memo = try XCTUnwrap(repo.memo(id: id))
        XCTAssertEqual(memo.audioFilename, "memo_\(id.uuidString).m4a", "a recording is never thrown away")
        XCTAssertTrue(fm.fileExists(atPath: audioURL(id).path))
        XCTAssertEqual(memo.transcript, "Typed first.")
        XCTAssertEqual(memo.transcriptStatus, .done)
    }

    func testPhotoTakenWhileRecordingOnATypedNoteLandsAtItsMoment() async throws {
        let repo = NotesRepository(inMemory: true)
        let id = try typedNote(repo, body: "Typed first.")
        cleanup.append(audioURL(id))
        let s = saver(repo, transcriber: SeededTranscriber(text: "look at this thing right here"))
        let photo = tempFile("cap", "JPEG")

        await s.appendRecordingAsync(to: id, tempURL: tempFile("clip", "CLIP-AUDIO"),
                                     photos: [(url: photo, offset: 0.7)])

        let memo = try XCTUnwrap(repo.memo(id: id))
        let manifest = try XCTUnwrap(memo.metadata?.imageManifest)
        XCTAssertEqual(manifest.map(\.filename), ["photo_\(id.uuidString)_001.jpg"])
        cleanup.append(AppPaths.recordingsDirectory.appendingPathComponent(manifest[0].filename))
        XCTAssertEqual(manifest[0].offsetSeconds, 0.7, accuracy: 0.001,
                       "no prior audio, so the stored offset is the clip-local moment")
        let body = try XCTUnwrap(memo.transcript)
        XCTAssertTrue(body.hasPrefix("Typed first."), "the typed body stays on top: \(body)")
        XCTAssertEqual(BodyV2Marker.numbers(in: body), [1])
        XCTAssertEqual(SourceKind.of(memo), .typedNote, "adding audio must not drop the typed marker")
    }

    func testAShareCaptureStillTakesNoRecording() async throws {
        let repo = NotesRepository(inMemory: true)
        let memo = Memo.make(audioFilename: "", title: "Link",
                             sharedContent: SharedContent(type: .url, url: "https://example.com", urlTitle: "Page"))
        repo.insert(memo)
        let s = saver(repo, transcriber: SeededTranscriber(text: "ignored"))
        let clip = tempFile("clip", "CLIP-AUDIO")

        await s.appendRecordingAsync(to: memo.id, tempURL: clip)

        XCTAssertTrue(try XCTUnwrap(repo.memo(id: memo.id)).audioFilename.isEmpty,
                      "captures keep their no-audio discriminator (the UI hides Add recording for them)")
    }
}
