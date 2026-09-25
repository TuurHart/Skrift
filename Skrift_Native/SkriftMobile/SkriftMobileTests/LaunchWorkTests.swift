import XCTest
import SwiftData
@testable import SkriftMobile

/// R91/R93/R94 (C278/C280/C281) — the phone's launch/foreground sweeps must do
/// only what changed: `LaunchWorkGate`'s high-water mark (memo count + latest
/// edit), `AppPaths.recordingsDirectory` created once, `AssetMaterializer
/// .captureMissing`'s scoped fetch. The recording-recovery sweep (C99) is
/// covered separately by `RecoverySweepTests` and is never gated by any of this.
@MainActor
final class LaunchWorkTests: XCTestCase {

    override func setUp() {
        LaunchWorkGate.resetForTesting()
    }

    override func tearDown() {
        LaunchWorkGate.resetForTesting()
    }

    // MARK: - R94: high-water mark gating

    func testFirstCheckAlwaysRunsThenNoopsUntilSomethingChanges() {
        let repo = NotesRepository(inMemory: true)
        repo.insert(Memo(audioFilename: ""))

        XCTAssertTrue(LaunchWorkGate.shouldRunSweeps(repository: repo),
                      "first check ever (or first foreground after launch) always runs the full batch")
        XCTAssertFalse(LaunchWorkGate.shouldRunSweeps(repository: repo),
                       "a foreground with 0 new/changed memos runs 0 sweep bodies")
        XCTAssertFalse(LaunchWorkGate.shouldRunSweeps(repository: repo),
                       "still no-op — nothing changed since the last check either")
    }

    func testNewMemoTripsTheGate() {
        let repo = NotesRepository(inMemory: true)
        repo.insert(Memo(audioFilename: ""))
        _ = LaunchWorkGate.shouldRunSweeps(repository: repo)
        XCTAssertFalse(LaunchWorkGate.shouldRunSweeps(repository: repo))

        repo.insert(Memo(audioFilename: ""))   // a new capture landed
        XCTAssertTrue(LaunchWorkGate.shouldRunSweeps(repository: repo),
                      "the memo count moved — the batch must run again")
    }

    func testEditingAnExistingMemoTripsTheGate() {
        let repo = NotesRepository(inMemory: true)
        let memo = Memo(audioFilename: "")
        repo.insert(memo)
        _ = LaunchWorkGate.shouldRunSweeps(repository: repo)
        XCTAssertFalse(LaunchWorkGate.shouldRunSweeps(repository: repo))

        memo.markEdited()   // same count, but content changed
        repo.save()
        XCTAssertTrue(LaunchWorkGate.shouldRunSweeps(repository: repo),
                      "editedAt moved with no new memo — the batch must still run again")
    }

    /// A `MemoAsset` synced in from ANOTHER device touches no `Memo` field on this
    /// one — no new memo, no local edit — so the memo count/editedAt alone would
    /// never notice it, and AssetMaterializer/PhotoTextIndexer would stall until an
    /// unrelated local change happened to run next.
    func testSyncedAssetWithNoLocalMemoChangeTripsTheGate() {
        let repo = NotesRepository(inMemory: true)
        let memo = Memo(audioFilename: "")
        repo.insert(memo)
        _ = LaunchWorkGate.shouldRunSweeps(repository: repo)
        XCTAssertFalse(LaunchWorkGate.shouldRunSweeps(repository: repo))

        // The memo itself is untouched — only a new asset row lands (as CloudKit
        // materializing another device's audio would do).
        repo.context.insert(MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.audio,
                                      filename: "memo_synced.m4a", blob: Data("x".utf8)))
        repo.save()

        XCTAssertTrue(LaunchWorkGate.shouldRunSweeps(repository: repo),
                      "asset count moved with memo count/editedAt unchanged — the asset sweeps must still run")
    }

    // MARK: - C99: recovery is never behind the gate

    func testRecoveryRunsRegardlessOfGateState() async throws {
        let repo = NotesRepository(inMemory: true)
        let audio = "memo_launchwork_\(UUID().uuidString).m4a"
        let url = AppPaths.recordingsDirectory.appendingPathComponent(audio)
        FileManager.default.createFile(atPath: url.path, contents: Data("audio".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let edited = Memo(audioFilename: audio)
        edited.transcriptStatus = .transcribing
        repo.insert(edited)

        // Prime the gate to its "nothing changed" state — recovery must not
        // consult it at all, so this must have zero effect on the outcome.
        _ = LaunchWorkGate.shouldRunSweeps(repository: repo)
        XCTAssertFalse(LaunchWorkGate.shouldRunSweeps(repository: repo))

        let saver = MemoSaver(repository: repo, transcriber: SeededTranscriber(text: "recovered words"),
                              wordTimings: WordTimingsStore(), metadataProvider: MockMetadataService())
        await saver.recoverStuckTranscriptions()

        XCTAssertEqual(repo.memo(id: edited.id)?.transcript, "recovered words",
                       "the recovery sweep ran even though the corpus gate says nothing changed")
    }

    // MARK: - R93: recordingsDirectory created once

    func testRecordingsDirectoryIsCreatedAtMostOnce() throws {
        // A `static let` runs its initializer exactly once for the process —
        // first touch it so it's definitely initialized, then delete the
        // directory from disk: if later reads still call `createDirectory`
        // they'd recreate it, which is exactly what R93 forbids.
        let dir = AppPaths.recordingsDirectory
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
        try FileManager.default.removeItem(at: dir)
        defer { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }

        for _ in 0..<5 { _ = AppPaths.recordingsDirectory }

        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path),
                       "N reads after the first produced 0 more createDirectory calls")
    }

    // MARK: - R91: captureMissing's scoped fetch

    func testCaptureMissingTouchesNothingWhenAllAssetsAreAlreadyCurrent() throws {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let audio = "memo_launchwork_capture_\(UUID().uuidString).m4a"
        let bytes = Data(repeating: 0x41, count: 4096)
        let url = AppPaths.recordingsDirectory.appendingPathComponent(audio)
        FileManager.default.createFile(atPath: url.path, contents: bytes)
        defer { try? FileManager.default.removeItem(at: url) }
        repo.insert(Memo(id: id, audioFilename: audio))
        AssetMaterializer.captureMissing(repo)   // creates the one asset
        let before = try XCTUnwrap(repo.assets(forMemo: id).first)
        XCTAssertEqual(before.byteCount, bytes.count)

        AssetMaterializer.captureMissing(repo)   // nothing changed on disk — must no-op

        let assets = repo.assets(forMemo: id)
        XCTAssertEqual(assets.count, 1, "no duplicate asset created")
        XCTAssertEqual(assets.first?.byteCount, bytes.count, "the up-to-date asset was left alone, not rewritten")
        XCTAssertEqual(assets.first?.blob, bytes, "content correct — R91 scopes the READ fetch, not the write path")
    }
}
