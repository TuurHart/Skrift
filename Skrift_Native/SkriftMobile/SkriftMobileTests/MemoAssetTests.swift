import XCTest
import SwiftData
@testable import SkriftMobile

/// Phase 1c: media (`.m4a` + photos) syncs across the user's own devices as
/// CloudKit-mirrored `MemoAsset` blobs. These cover the `AssetMaterializer` —
/// capture (disk → asset, the export/migration half) and materialize (asset → disk,
/// the receiving-device half) — plus asset cleanup on permanent delete. The store is
/// in-memory (CloudKit forced `.none`); files use memo-UUID names in the real
/// recordings dir and are cleaned up per test.
@MainActor
final class MemoAssetTests: XCTestCase {

    private let fm = FileManager.default
    private func url(_ name: String) -> URL { AppPaths.recordingsDirectory.appendingPathComponent(name) }
    private func write(_ name: String, _ contents: Data) { fm.createFile(atPath: url(name).path, contents: contents) }
    private func cleanup(_ names: [String]) { names.forEach { try? fm.removeItem(at: url($0)) } }

    // MARK: - Capture (disk → asset)

    func testCaptureCreatesAssetsForAudioAndPhotos() {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let audio = "memo_\(id.uuidString).m4a"
        let photo = "photo_\(id.uuidString)_001.jpg"
        defer { cleanup([audio, photo]) }
        write(audio, Data("AUDIO-BYTES".utf8))
        write(photo, Data("JPG".utf8))
        let memo = Memo(id: id, audioFilename: audio,
                        metadata: MemoMetadata(imageManifest: [ImageManifestEntry(filename: photo, offsetSeconds: 0)]))
        repo.insert(memo)

        AssetMaterializer.captureMissing(repo)

        let assets = repo.assets(forMemo: id).sorted { $0.kind < $1.kind }
        XCTAssertEqual(assets.map(\.kind), [MemoAsset.Kind.audio, MemoAsset.Kind.photo])
        XCTAssertEqual(assets.first { $0.kind == MemoAsset.Kind.audio }?.blob, Data("AUDIO-BYTES".utf8))
        XCTAssertEqual(assets.first { $0.kind == MemoAsset.Kind.audio }?.byteCount, Data("AUDIO-BYTES".utf8).count)
        XCTAssertEqual(assets.first { $0.kind == MemoAsset.Kind.photo }?.filename, photo)
    }

    func testCaptureSkipsMemoWhoseFileIsNotOnDisk() {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        // audioFilename set, but no file written → nothing to capture (e.g. a memo
        // whose media hasn't materialized yet, or a capture item with empty audio).
        repo.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a"))
        repo.insert(Memo(audioFilename: ""))   // capture item, no audio

        AssetMaterializer.captureMissing(repo)

        XCTAssertTrue(repo.allAssets().isEmpty)
    }

    func testCaptureIsIdempotent() {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let audio = "memo_\(id.uuidString).m4a"
        defer { cleanup([audio]) }
        write(audio, Data("X".utf8))
        repo.insert(Memo(id: id, audioFilename: audio))

        AssetMaterializer.captureMissing(repo)
        AssetMaterializer.captureMissing(repo)   // second pass must not duplicate

        XCTAssertEqual(repo.allAssets().count, 1)
    }

    func testCaptureRefreshesStaleAssetWhenFileGrows() {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let audio = "memo_\(id.uuidString).m4a"
        defer { cleanup([audio]) }
        write(audio, Data("SHORT".utf8))
        repo.insert(Memo(id: id, audioFilename: audio))
        AssetMaterializer.captureMissing(repo)
        XCTAssertEqual(repo.assets(forMemo: id).first?.byteCount, 5)

        // Simulate an append growing the audio file.
        write(audio, Data("MUCH-LONGER-AUDIO".utf8))
        AssetMaterializer.captureMissing(repo)

        let asset = repo.assets(forMemo: id).first
        XCTAssertEqual(repo.allAssets().count, 1, "refresh must update in place, not duplicate")
        XCTAssertEqual(asset?.blob, Data("MUCH-LONGER-AUDIO".utf8))
        XCTAssertEqual(asset?.byteCount, Data("MUCH-LONGER-AUDIO".utf8).count)
    }

    func testCapturePerMemoOnlyTouchesThatMemo() {
        let repo = NotesRepository(inMemory: true)
        let a = UUID(), b = UUID()
        let audioA = "memo_\(a.uuidString).m4a", audioB = "memo_\(b.uuidString).m4a"
        defer { cleanup([audioA, audioB]) }
        write(audioA, Data("A".utf8))
        write(audioB, Data("B".utf8))
        repo.insert(Memo(id: a, audioFilename: audioA))
        repo.insert(Memo(id: b, audioFilename: audioB))

        AssetMaterializer.capture(memoID: a, repository: repo)

        XCTAssertEqual(repo.assets(forMemo: a).count, 1)
        XCTAssertTrue(repo.assets(forMemo: b).isEmpty, "per-memo capture must not touch other memos")
    }

    // MARK: - Materialize (asset → disk)

    func testMaterializeWritesMissingFileFromBlob() {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let audio = "memo_\(id.uuidString).m4a"
        defer { cleanup([audio]) }
        let payload = Data("SYNCED-FROM-IPAD".utf8)
        repo.context.insert(MemoAsset(memoID: id, kind: MemoAsset.Kind.audio, filename: audio, blob: payload))
        repo.save()
        try? fm.removeItem(at: url(audio))
        XCTAssertFalse(fm.fileExists(atPath: url(audio).path))

        AssetMaterializer.materializeMissing(repo)

        XCTAssertEqual(try? Data(contentsOf: url(audio)), payload)
    }

    func testMaterializeNeverOverwritesAnExistingFile() {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let audio = "memo_\(id.uuidString).m4a"
        defer { cleanup([audio]) }
        write(audio, Data("LOCAL-GOOD".utf8))   // a good local file already on disk
        repo.context.insert(MemoAsset(memoID: id, kind: MemoAsset.Kind.audio, filename: audio,
                                      blob: Data("DIFFERENT".utf8)))
        repo.save()

        AssetMaterializer.materializeMissing(repo)

        XCTAssertEqual(try? Data(contentsOf: url(audio)), Data("LOCAL-GOOD".utf8),
                       "materialize must never clobber an existing file")
    }

    /// The cross-device round trip: device A captures files → assets; device B has the
    /// synced assets but no files → materialize restores them byte-identically.
    func testRoundTripCaptureThenMaterializeRestoresFiles() {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let audio = "memo_\(id.uuidString).m4a"
        let photo = "photo_\(id.uuidString)_001.jpg"
        defer { cleanup([audio, photo]) }
        let audioBytes = Data("THE-RECORDING".utf8)
        let photoBytes = Data("THE-PHOTO".utf8)
        write(audio, audioBytes)
        write(photo, photoBytes)
        repo.insert(Memo(id: id, audioFilename: audio,
                         metadata: MemoMetadata(imageManifest: [ImageManifestEntry(filename: photo, offsetSeconds: 0)])))
        AssetMaterializer.captureMissing(repo)        // device A
        XCTAssertEqual(repo.allAssets().count, 2)

        // Device B: assets present, files gone.
        try? fm.removeItem(at: url(audio))
        try? fm.removeItem(at: url(photo))

        AssetMaterializer.materializeMissing(repo)    // device B

        XCTAssertEqual(try? Data(contentsOf: url(audio)), audioBytes)
        XCTAssertEqual(try? Data(contentsOf: url(photo)), photoBytes)
    }

    // MARK: - Cleanup

    func testPermanentDeleteRemovesAssetRows() {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let audio = "memo_\(id.uuidString).m4a"
        defer { cleanup([audio]) }
        write(audio, Data("A".utf8))
        let memo = Memo(id: id, audioFilename: audio)
        repo.insert(memo)
        AssetMaterializer.captureMissing(repo)
        XCTAssertEqual(repo.allAssets().count, 1)

        repo.permanentlyDelete(memo)

        XCTAssertTrue(repo.assets(forMemo: id).isEmpty)
        XCTAssertTrue(repo.allAssets().isEmpty)
    }

    // MARK: - Sidecars (word-timings + diarization — Phase 1d)

    func testCaptureIncludesWordTimingsAndDiarizationSidecars() {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let audio = "memo_\(id.uuidString).m4a"
        let wt = WordTimingsStore.filename(for: id)
        let diar = DiarizationStore.filename(for: id)
        defer { cleanup([audio, wt, diar]) }
        write(audio, Data("AUDIO".utf8))
        WordTimingsStore().write([WordTiming(word: "hi", start: 0, end: 0.4)], for: id)
        DiarizationStore().write(DiarizationData(segments: [], slotNames: ["0": "Tiuri"]), for: id)
        repo.insert(Memo(id: id, audioFilename: audio))

        AssetMaterializer.captureMissing(repo)

        let kinds = Set(repo.assets(forMemo: id).map(\.kind))
        XCTAssertEqual(kinds, [MemoAsset.Kind.audio, MemoAsset.Kind.wordTimings, MemoAsset.Kind.diarization])
    }

    /// Device A captures the sidecars; device B (files gone) materializes them, and the
    /// real stores read the data back — proving karaoke + speaker labels survive the trip.
    func testRoundTripSidecarsRestoreThroughTheirStores() {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let audio = "memo_\(id.uuidString).m4a"
        let wt = WordTimingsStore.filename(for: id)
        let diar = DiarizationStore.filename(for: id)
        defer { cleanup([audio, wt, diar]) }
        write(audio, Data("AUDIO".utf8))
        let timings = [WordTiming(word: "harbor", start: 0.1, end: 0.6),
                       WordTiming(word: "dawn", start: 0.6, end: 1.0)]
        WordTimingsStore().write(timings, for: id)
        DiarizationStore().write(DiarizationData(segments: [], slotNames: ["0": "Tiuri", "1": "Jack"]), for: id)
        repo.insert(Memo(id: id, audioFilename: audio))
        AssetMaterializer.captureMissing(repo)        // device A

        // Device B: assets synced, sidecar files absent.
        cleanup([wt, diar])
        XCTAssertNil(WordTimingsStore().load(for: id))

        AssetMaterializer.materializeMissing(repo)    // device B

        XCTAssertEqual(WordTimingsStore().load(for: id)?.map(\.word), ["harbor", "dawn"])
        XCTAssertEqual(DiarizationStore().load(for: id)?.slotNames["1"], "Jack")
    }

    // MARK: - Sync visibility (Phase 1 — "Downloading from iCloud…")

    func testMediaSyncStateThreeWay() {
        XCTAssertEqual(MediaSyncState.of(filePresent: true,  hasAsset: true),  .present)
        XCTAssertEqual(MediaSyncState.of(filePresent: true,  hasAsset: false), .present)
        XCTAssertEqual(MediaSyncState.of(filePresent: false, hasAsset: true),  .downloading)
        XCTAssertEqual(MediaSyncState.of(filePresent: false, hasAsset: false), .missing)
    }

    func testHasAssetReflectsCarrierPresence() {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let photo = "photo_\(id.uuidString)_001.jpg"
        XCTAssertFalse(repo.hasAsset(filename: photo))
        XCTAssertFalse(repo.hasAsset(filename: ""))
        repo.context.insert(MemoAsset(memoID: id, kind: MemoAsset.Kind.photo, filename: photo, blob: Data("X".utf8)))
        repo.save()
        XCTAssertTrue(repo.hasAsset(filename: photo), "a synced asset with no local file yet → downloading state")
    }
}
