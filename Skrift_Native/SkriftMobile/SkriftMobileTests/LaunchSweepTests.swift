import XCTest
import SwiftData
@testable import SkriftMobile

/// Q316 — the launch / return-to-app sweeps leave the main thread and run once.
/// `LaunchWorkTests` keeps its original cases; the Q316 cases live in this file as an
/// extension of that class (a protected test file is never edited, only grown).
///
/// Fixtures put the audio files on disk (the perf seed gave ~1,540 notes an `audioFilename`
/// with no file, which hides the stat and blob cost) AND leave some missing.
@MainActor
extension LaunchWorkTests {

    // MARK: - Helpers

    private static var tracked: [URL] = []

    /// A voice note whose audio is (or is not) really on disk. `daysOld` backdates every
    /// date the checkpoint looks at, so an "unchanged store" really is unchanged.
    fileprivate func makeVoiceNote(_ repo: NotesRepository, daysOld: Double, fileOnDisk: Bool,
                                   bytes: Int = 2048, manifest: [ImageManifestEntry]? = nil) -> Memo {
        let id = UUID()
        let audio = "memo_q316_\(id.uuidString).m4a"
        let when = Date().addingTimeInterval(-daysOld * 86_400)
        if fileOnDisk {
            let url = AppPaths.recordingsDirectory.appendingPathComponent(audio)
            FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 0x42, count: bytes))
            Self.tracked.append(url)
        }
        let memo = Memo(id: id, audioFilename: audio, duration: 5, recordedAt: when,
                        transcript: "words", transcriptStatus: .done, createdAt: when)
        if let manifest {
            var meta = MemoMetadata()
            meta.imageManifest = manifest
            memo.metadata = meta
        }
        repo.insert(memo)
        return memo
    }

    fileprivate func freshCheckpoint() -> AssetCaptureCheckpoint {
        let suite = "q316.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return AssetCaptureCheckpoint(defaults: defaults, key: "cp")
    }

    fileprivate func assetCount(_ repo: NotesRepository) -> Int {
        (try? ModelContext(repo.container).fetchCount(FetchDescriptor<MemoAsset>())) ?? -1
    }

    fileprivate func cleanTracked() {
        for url in Self.tracked { try? FileManager.default.removeItem(at: url) }
        Self.tracked.removeAll()
    }

    // MARK: - Launch, then the first foreground: each sweep once

    func testLaunchThenFirstForegroundRunsEachGatedSweepOnce() async throws {
        defer { cleanTracked() }
        let originalRecognizer = PhotoTextIndexer.recognizer
        addTeardownBlock { await MainActor.run { PhotoTextIndexer.recognizer = originalRecognizer } }
        PhotoTextIndexer.recognizer = { _ in "OCR" }

        let repo = NotesRepository(inMemory: true)
        let photo = "photo_q316_\(UUID().uuidString).jpg"
        let photoURL = AppPaths.recordingsDirectory.appendingPathComponent(photo)
        FileManager.default.createFile(atPath: photoURL.path, contents: Data("jpg".utf8))
        Self.tracked.append(photoURL)
        for i in 0..<6 { _ = makeVoiceNote(repo, daysOld: 10, fileOnDisk: i % 3 != 0) }
        let withPhoto = makeVoiceNote(repo, daysOld: 10, fileOnDisk: true,
                                      manifest: [ImageManifestEntry(filename: photo, offsetSeconds: 1)])
        let cp = freshCheckpoint()
        SweepProbe.reset()

        let launch = LaunchSweeps.launch(repo, checkpoint: cp)
        XCTAssertTrue(SweepProbe.events.isEmpty, "launch() returns before any sweep body has run")
        await launch.value

        let foreground = LaunchSweeps.foreground(repo, checkpoint: cp)
        XCTAssertFalse(foreground.gated,
                       "LaunchWorkGate was marked at launch: the first foreground sees an unchanged corpus")
        await foreground.task.value

        func count(_ name: String) -> Int { SweepProbe.events.filter { $0.name == name }.count }
        XCTAssertEqual(count("dedupe"), 1, "dedupe ran once across launch + first foreground")
        XCTAssertEqual(count("assets"), 1, "asset sync ran once")
        XCTAssertEqual(count("photoText"), 1, "photo discovery ran once")
        XCTAssertEqual(count("fading"), 2, "FadingSweep is time-gated by contract: it runs on every open")
        XCTAssertEqual(assetCount(repo), 4 + 2,
                       "audio of the 4 plain notes with a file, plus audio + photo of the photo note")

        // the OCR the discovery found still lands on the main context
        var text: String?
        for _ in 0..<50 {
            text = repo.memo(id: withPhoto.id)?.metadata?.imageManifest?.first?.text
            if text != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(text, "OCR")
    }

    /// A foreground after the corpus really moved runs the gated sweeps again.
    func testForegroundAfterANewNoteRunsTheGatedSweepsAgain() async {
        defer { cleanTracked() }
        let repo = NotesRepository(inMemory: true)
        _ = makeVoiceNote(repo, daysOld: 10, fileOnDisk: true)
        let cp = freshCheckpoint()
        await LaunchSweeps.launch(repo, checkpoint: cp).value
        SweepProbe.reset()

        _ = makeVoiceNote(repo, daysOld: 0, fileOnDisk: true)   // a capture landed
        let foreground = LaunchSweeps.foreground(repo, checkpoint: cp)
        XCTAssertTrue(foreground.gated)
        await foreground.task.value

        XCTAssertEqual(SweepProbe.events.filter { $0.name == "assets" }.count, 1)
        XCTAssertEqual(assetCount(repo), 2, "the new note's audio was captured")
    }

    // MARK: - captureMissing checkpoint

    func testCaptureMissingWithAnUnchangedStoreStatsNoFiles() async throws {
        defer { cleanTracked() }
        let repo = NotesRepository(inMemory: true)
        var notes: [Memo] = []
        for i in 0..<8 { notes.append(makeVoiceNote(repo, daysOld: 10, fileOnDisk: i % 4 != 0)) }   // 6 present, 2 missing
        let sweeps = SweepActor(container: repo.container)
        let cp = freshCheckpoint()
        let t0 = Date()

        AssetMaterializer.resetFileStatCount()
        _ = await sweeps.syncAssets(checkpoint: cp, now: t0)
        XCTAssertGreaterThan(AssetMaterializer.fileStatCount, 0, "the first pass is a full pass")
        XCTAssertEqual(assetCount(repo), 6, "an asset for every audio file that is on disk")

        AssetMaterializer.resetFileStatCount()
        let wrote = await sweeps.syncAssets(checkpoint: cp, now: t0.addingTimeInterval(60))
        XCTAssertFalse(wrote)
        XCTAssertEqual(AssetMaterializer.fileStatCount, 0, "an unchanged store: zero file stats")
        XCTAssertEqual(assetCount(repo), 6)

        // an append grew one file and the note was edited: only that note is examined
        let edited = notes[1]
        let editedID = edited.id
        let url = AppPaths.recordingsDirectory.appendingPathComponent(edited.audioFilename)
        try Data(repeating: 0x43, count: 4096).write(to: url)
        edited.markEdited(t0.addingTimeInterval(90))
        repo.save()
        AssetMaterializer.resetFileStatCount()
        let wroteAfterEdit = await sweeps.syncAssets(checkpoint: cp, now: t0.addingTimeInterval(120))
        XCTAssertTrue(wroteAfterEdit)
        XCTAssertLessThanOrEqual(AssetMaterializer.fileStatCount, 8, "one note's files (<= 7 candidates), not the library's")
        let asset = try XCTUnwrap(ModelContext(repo.container).fetch(FetchDescriptor<MemoAsset>(
            predicate: #Predicate { $0.memoID == editedID })).first(where: { $0.kind == MemoAsset.Kind.audio }))
        XCTAssertEqual(asset.byteCount, 4096, "the refreshed blob is the grown file")
    }

    func testFullCaptureRunsAgainOnceTheWeeklyBackstopIsDue() async {
        defer { cleanTracked() }
        let repo = NotesRepository(inMemory: true)
        _ = makeVoiceNote(repo, daysOld: 30, fileOnDisk: true)
        let sweeps = SweepActor(container: repo.container)
        let cp = freshCheckpoint()
        let t0 = Date()
        _ = await sweeps.syncAssets(checkpoint: cp, now: t0)

        AssetMaterializer.resetFileStatCount()
        _ = await sweeps.syncAssets(checkpoint: cp, now: t0.addingTimeInterval(AssetMaterializer.fullSweepInterval + 60))
        XCTAssertGreaterThan(AssetMaterializer.fileStatCount, 0,
                             "a sidecar written long after its note was last touched is caught by the weekly full pass")
    }

    // MARK: - Correctness of the moved sweeps

    func testOffMainFadingSweepMovesAnOldUntouchedNoteToTheTrash() async {
        let repo = NotesRepository(inMemory: true)
        let old = makeVoiceNote(repo, daysOld: 90, fileOnDisk: false)
        let fresh = makeVoiceNote(repo, daysOld: 1, fileOnDisk: false)
        let swept = await SweepActor(container: repo.container).fade()
        XCTAssertEqual(swept, 1)
        let context = ModelContext(repo.container)
        let all = (try? context.fetch(FetchDescriptor<Memo>())) ?? []
        XCTAssertNotNil(all.first { $0.id == old.id }?.deletedAt, "the 90-day-old untouched note is in Recently Deleted")
        XCTAssertNil(all.first { $0.id == fresh.id }?.deletedAt)
    }

    func testOffMainDedupeTrashesTheCloneAndKeepsTheKeeper() async {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let when = Date(timeIntervalSince1970: 1_000_000)
        for _ in 0..<2 {
            repo.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", duration: 5,
                             recordedAt: when, transcript: "same words", createdAt: when))
        }
        let trashed = await SweepActor(container: repo.container).dedupe()
        XCTAssertTrue(trashed)
        let rows = (try? ModelContext(repo.container).fetch(FetchDescriptor<Memo>())) ?? []
        XCTAssertEqual(rows.filter { $0.id == id && $0.deletedAt == nil }.count, 1, "one keeper stays live")
        XCTAssertEqual(rows.filter { $0.id == id && $0.deletedAt != nil }.count, 1, "the clone went to the trash")
    }
}

/// Q316 — the sweeps run OFF the main actor, and recovery stays correct.
@MainActor
final class LaunchOffMainTests: XCTestCase {

    override func setUp() {
        LaunchWorkGate.resetForTesting()
        SweepProbe.reset()
    }

    override func tearDown() {
        LaunchWorkGate.resetForTesting()
    }

    private func checkpoint() -> AssetCaptureCheckpoint {
        let suite = "q316off.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return AssetCaptureCheckpoint(defaults: defaults, key: "cp")
    }

    func testEverySweepBodyRunsOffTheMainThread() async {
        let repo = NotesRepository(inMemory: true)
        repo.insert(Memo(audioFilename: "", recordedAt: Date(), transcript: "a note"))
        let cp = checkpoint()

        await LaunchSweeps.launch(repo, checkpoint: cp).value
        await LaunchSweeps.foreground(repo, checkpoint: cp).task.value
        await LaunchSweeps.importBurst(repo, checkpoint: cp).value

        let names = Set(SweepProbe.events.map(\.name))
        XCTAssertTrue(names.isSuperset(of: ["dedupe", "assets", "photoText", "fading"]), "ran: \(names)")
        XCTAssertTrue(SweepProbe.events.allSatisfy { !$0.onMainThread },
                      "a sweep body ran on the main thread: \(SweepProbe.events.filter(\.onMainThread))")
    }

    func testStuckTranscriptionDiscoveryRunsOffMainAndStillRecovers() async throws {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"
        let url = AppPaths.recordingsDirectory.appendingPathComponent(filename)
        FileManager.default.createFile(atPath: url.path, contents: Data("AUDIO".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        repo.insert(Memo(id: id, audioFilename: filename, duration: 13, recordedAt: Date(),
                         transcript: nil, transcriptStatus: .transcribing))
        // a user-edited stuck memo is released from the spinner, never re-transcribed (C263)
        let editedID = UUID()
        repo.insert(Memo(id: editedID, audioFilename: "memo_\(editedID.uuidString).m4a", duration: 5,
                         recordedAt: Date(), transcript: "my words", transcriptStatus: .transcribing,
                         transcriptUserEdited: true))

        let saver = MemoSaver(repository: repo, transcriber: SeededTranscriber(text: "recovered"),
                              wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                                  .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
                              metadataProvider: MockMetadataService())
        await saver.recoverStuckTranscriptions(sweeps: LaunchSweeps.sweepActor(for: repo))

        XCTAssertEqual(repo.memo(id: id)?.transcript, "recovered")
        XCTAssertEqual(repo.memo(id: id)?.transcriptStatus, .done)
        XCTAssertEqual(repo.memo(id: editedID)?.transcript, "my words", "the user's words are untouched")
        XCTAssertEqual(repo.memo(id: editedID)?.transcriptStatus, .done)
        let events = SweepProbe.events.filter { $0.name == "stuckTranscriptions" }
        XCTAssertEqual(events.count, 1)
        XCTAssertFalse(events.first?.onMainThread ?? true, "the discovery ran off the main thread")
    }

    /// C99: the launch pass starts only after the recording-recovery sweep (the app awaits it
    /// first), so a take it rebuilt is in the store when the asset sweep looks. A rebuilt note
    /// is `.transcribing` with a merged `.m4a` on disk; the launch pass must capture its audio.
    func testALaunchPassAfterRecoveryCapturesTheRebuiltTake() async {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"
        let url = AppPaths.recordingsDirectory.appendingPathComponent(filename)
        FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 1, count: 512))
        defer { try? FileManager.default.removeItem(at: url) }
        repo.insert(Memo.make(id: id, audioFilename: filename, duration: 3, recordedAt: Date(),
                              syncStatus: .waiting, title: "Recovered recording",
                              transcriptStatus: .transcribing))

        await LaunchSweeps.launch(repo, checkpoint: checkpoint()).value

        let assets = (try? ModelContext(repo.container).fetch(FetchDescriptor<MemoAsset>(
            predicate: #Predicate { $0.memoID == id }))) ?? []
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(repo.memo(id: id)?.transcriptStatus, .transcribing, "the sweeps never touch recovery's state")
    }
}
