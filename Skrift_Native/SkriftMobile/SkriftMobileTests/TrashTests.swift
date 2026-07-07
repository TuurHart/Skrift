import XCTest
import SwiftData
@testable import SkriftMobile

/// Trash ("Recently Deleted") behaviour: soft-delete hides a memo from every
/// `allMemos()` consumer (list, search), restore brings it back, and the
/// startup purge permanently removes memos past the 14-day retention —
/// including their on-disk audio and sidecars.
final class TrashTests: XCTestCase {

    @MainActor
    func testSoftDeleteHidesFromMainListAndShowsInTrash() {
        let repo = NotesRepository(inMemory: true)
        let memo = Memo(audioFilename: "memo_a.m4a")
        repo.insert(memo)
        repo.insert(Memo(audioFilename: "memo_b.m4a"))

        repo.softDelete(memo)

        XCTAssertNotNil(memo.deletedAt)
        // Hidden from the main list (and so from every allMemos() consumer).
        XCTAssertEqual(repo.allMemos().map(\.audioFilename), ["memo_b.m4a"])
        XCTAssertEqual(repo.deletedMemos().map(\.audioFilename), ["memo_a.m4a"])
        // Lookup by id still finds it — Restore and purge depend on that.
        XCTAssertNotNil(repo.memo(id: memo.id))
    }

    @MainActor
    func testRestoreReturnsMemoToMainListUntouched() {
        let repo = NotesRepository(inMemory: true)
        let memo = Memo(audioFilename: "memo_a.m4a", transcript: "hello", significance: 0.5)
        repo.insert(memo)

        repo.softDelete(memo)
        repo.restore(memo)

        XCTAssertNil(memo.deletedAt)
        XCTAssertEqual(repo.allMemos().count, 1)
        XCTAssertTrue(repo.deletedMemos().isEmpty)
        // Restore changes nothing else.
        XCTAssertEqual(memo.transcript, "hello")
        XCTAssertEqual(memo.significance, 0.5)
    }

    @MainActor
    func testPurgeRemovesOnlyMemosPastRetention() {
        let repo = NotesRepository(inMemory: true)
        let now = Date()
        let old = Memo(audioFilename: "memo_old.m4a")
        let recent = Memo(audioFilename: "memo_recent.m4a")
        let kept = Memo(audioFilename: "memo_kept.m4a")
        let oldID = old.id
        let recentID = recent.id
        [old, recent, kept].forEach { repo.insert($0) }
        repo.softDelete(old, at: now.addingTimeInterval(-15 * 86_400))
        repo.softDelete(recent, at: now.addingTimeInterval(-13 * 86_400))

        let purged = repo.purgeExpiredTrash(now: now)

        XCTAssertEqual(purged, 1)
        XCTAssertNil(repo.memo(id: oldID))          // gone for good
        XCTAssertNotNil(repo.memo(id: recentID))    // still in the trash
        XCTAssertEqual(repo.deletedMemos().map(\.audioFilename), ["memo_recent.m4a"])
        XCTAssertEqual(repo.allMemos().map(\.audioFilename), ["memo_kept.m4a"])
    }

    @MainActor
    func testPurgeThresholdIsInclusiveAtExactlyRetention() {
        let repo = NotesRepository(inMemory: true)
        let now = Date()
        let memo = Memo(audioFilename: "memo_edge.m4a")
        let id = memo.id
        repo.insert(memo)
        repo.softDelete(memo, at: now.addingTimeInterval(-TrashPolicy.retention))

        XCTAssertEqual(repo.purgeExpiredTrash(now: now), 1)
        XCTAssertNil(repo.memo(id: id))
    }

    /// The purge reuses the full-delete path: audio + photo + word-timings +
    /// diarization sidecars all leave the disk with the row.
    @MainActor
    func testPurgeRemovesAudioPhotosAndSidecars() {
        let repo = NotesRepository(inMemory: true)
        let memo = Memo()
        let id = memo.id
        let fm = FileManager.default

        let audioName = "memo_\(id.uuidString).m4a"
        memo.audioFilename = audioName
        let audioURL = AppPaths.recordingsDirectory.appendingPathComponent(audioName)
        fm.createFile(atPath: audioURL.path, contents: Data("AUDIO".utf8))

        let photoName = "photo_\(id.uuidString)_001.jpg"
        let photoURL = AppPaths.recordingsDirectory.appendingPathComponent(photoName)
        fm.createFile(atPath: photoURL.path, contents: Data("JPG".utf8))
        memo.metadata = MemoMetadata(imageManifest: [ImageManifestEntry(filename: photoName, offsetSeconds: 1)])

        WordTimingsStore().write([WordTiming(word: "hi", start: 0, end: 0.4)], for: id)
        DiarizationStore().write(DiarizationData(segments: [], slotNames: [:]), for: id)

        repo.insert(memo)
        repo.softDelete(memo, at: .distantPast)
        repo.purgeExpiredTrash()

        XCTAssertNil(repo.memo(id: id))
        XCTAssertFalse(fm.fileExists(atPath: audioURL.path))
        XCTAssertFalse(fm.fileExists(atPath: photoURL.path))
        XCTAssertNil(WordTimingsStore().load(for: id))
        XCTAssertNil(DiarizationStore().load(for: id))
    }

    /// Soft-delete itself must NOT touch the files — Restore is lossless.
    @MainActor
    func testSoftDeleteKeepsAudioOnDisk() {
        let repo = NotesRepository(inMemory: true)
        let memo = Memo()
        let audioName = "memo_\(memo.id.uuidString).m4a"
        memo.audioFilename = audioName
        let audioURL = AppPaths.recordingsDirectory.appendingPathComponent(audioName)
        FileManager.default.createFile(atPath: audioURL.path, contents: Data("AUDIO".utf8))
        repo.insert(memo)

        repo.softDelete(memo)

        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
        try? FileManager.default.removeItem(at: audioURL)   // tidy up
    }

    // MARK: - Countdown labels

    func testTrashDaysRemainingCeilsAndClamps() {
        let now = Date()

        let notTrashed = Memo()
        XCTAssertNil(notTrashed.trashDaysRemaining(now: now))

        let justDeleted = Memo(deletedAt: now.addingTimeInterval(-3600))      // 1h ago
        XCTAssertEqual(justDeleted.trashDaysRemaining(now: now), 14)

        let halfDayLeft = Memo(deletedAt: now.addingTimeInterval(-13.5 * 86_400))
        XCTAssertEqual(halfDayLeft.trashDaysRemaining(now: now), 1)

        let expired = Memo(deletedAt: now.addingTimeInterval(-20 * 86_400))
        XCTAssertEqual(expired.trashDaysRemaining(now: now), 0)
    }

    func testTrashCountdownLabel() {
        let now = Date()
        XCTAssertNil(Memo().trashCountdownLabel(now: now))
        XCTAssertEqual(Memo(deletedAt: now.addingTimeInterval(-3600)).trashCountdownLabel(now: now),
                       "14 days left")
        XCTAssertEqual(Memo(deletedAt: now.addingTimeInterval(-13.5 * 86_400)).trashCountdownLabel(now: now),
                       "1 day left")
        XCTAssertEqual(Memo(deletedAt: now.addingTimeInterval(-15 * 86_400)).trashCountdownLabel(now: now),
                       "Deleting soon")
    }
}
