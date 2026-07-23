import XCTest
import SwiftData
@testable import SkriftMobile

/// Trash ("Recently Deleted") behaviour: soft-delete hides a memo from every
/// `allMemos()` consumer (list, search), restore brings it back, and the
/// startup purge permanently removes memos past the 14-day retention —
/// including their on-disk audio and sidecars. v3 "no note dies unseen"
/// (2026-07-23): the purge clock is `trashSeenAt` — a deletion that synced in
/// while the app sat closed never purges until the user has had the app open
/// with it for the full window.
final class TrashTests: XCTestCase {

    @MainActor
    func testSoftDeleteHidesFromMainListAndShowsInTrash() {
        let repo = NotesRepository(inMemory: true)
        let memo = Memo(audioFilename: "memo_a.m4a")
        repo.insert(memo)
        repo.insert(Memo(audioFilename: "memo_b.m4a"))

        repo.softDelete(memo)

        XCTAssertNotNil(memo.deletedAt)
        XCTAssertEqual(memo.trashSeenAt, memo.deletedAt,
                       "an in-session delete starts its own purge clock (v3)")
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
        XCTAssertNil(memo.trashSeenAt, "restore clears the purge clock")
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

    // MARK: - v3 "no note dies unseen" (2026-07-23): the purge gate

    /// The scenario that forced the doctrine: note swept to trash by another
    /// device (the Mac) while the phone sat closed for months. The synced-in
    /// `deletedAt` is long past retention — but nobody has had THIS app open
    /// with it, so the purge must not touch it; the at-open stamp starts its
    /// clock instead, and only a full window later does it purge.
    @MainActor
    func testSyncedInDeletionNeverPurgesUnseen() {
        let repo = NotesRepository(inMemory: true)
        let now = Date()
        let memo = Memo(audioFilename: "memo_away.m4a")
        repo.insert(memo)
        memo.deletedAt = now.addingTimeInterval(-30 * 86_400)   // synced in, no sighting

        XCTAssertEqual(repo.purgeExpiredTrash(now: now), 0, "unseen — must survive the open")
        XCTAssertNotNil(repo.memo(id: memo.id))

        // The open stamps it (FadingSweep's pass)…
        MemoLifecycle.stampTrashSightings(repo.deletedMemos(), now: now)
        XCTAssertEqual(memo.trashSeenAt, now)
        // …still safe for the whole fresh window…
        XCTAssertEqual(repo.purgeExpiredTrash(now: now.addingTimeInterval(TrashPolicy.retention - 60)), 0)
        // …and purges only once the SEEN window has fully run.
        XCTAssertEqual(repo.purgeExpiredTrash(now: now.addingTimeInterval(TrashPolicy.retention)), 1)
        XCTAssertNil(repo.memo(id: memo.id))
    }

    /// Restore → re-trash must not inherit the first stay's sighting: the old
    /// stamp is stale (< the new `deletedAt`) and the clock starts unseen.
    @MainActor
    func testRetrashedNoteDoesNotInheritOldSighting() {
        let repo = NotesRepository(inMemory: true)
        let now = Date()
        let memo = Memo(audioFilename: "memo_back.m4a")
        repo.insert(memo)

        repo.softDelete(memo, at: now.addingTimeInterval(-40 * 86_400))
        // Restored elsewhere WITHOUT the stamp clearing (another device's LWW
        // merge can leave it), then re-trashed while this phone was closed.
        memo.deletedAt = now.addingTimeInterval(-20 * 86_400)

        XCTAssertEqual(repo.purgeExpiredTrash(now: now), 0,
                       "a stale stamp from the previous stay must not count")
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

    /// A memo deleted-and-seen `secondsAgo` — the normal in-session case,
    /// where the countdown runs from the deletion itself.
    private func seenTrashed(secondsAgo: TimeInterval, now: Date) -> Memo {
        let m = Memo(deletedAt: now.addingTimeInterval(-secondsAgo))
        m.trashSeenAt = m.deletedAt
        return m
    }

    func testTrashDaysRemainingCeilsAndClamps() {
        let now = Date()

        let notTrashed = Memo()
        XCTAssertNil(notTrashed.trashDaysRemaining(now: now))

        XCTAssertEqual(seenTrashed(secondsAgo: 3600, now: now).trashDaysRemaining(now: now), 14)
        XCTAssertEqual(seenTrashed(secondsAgo: 13.5 * 86_400, now: now).trashDaysRemaining(now: now), 1)
        XCTAssertEqual(seenTrashed(secondsAgo: 20 * 86_400, now: now).trashDaysRemaining(now: now), 0)

        // v3: an UNSEEN synced-in deletion shows the full window — its clock
        // truly hasn't started (matches the purge gate, so the date is honest).
        let unseen = Memo(deletedAt: now.addingTimeInterval(-20 * 86_400))
        XCTAssertEqual(unseen.trashDaysRemaining(now: now), TrashPolicy.retentionDays)
    }

    func testTrashCountdownLabel() {
        let now = Date()
        XCTAssertNil(Memo().trashCountdownLabel(now: now))
        XCTAssertEqual(seenTrashed(secondsAgo: 3600, now: now).trashCountdownLabel(now: now),
                       "14 days left")
        XCTAssertEqual(seenTrashed(secondsAgo: 13.5 * 86_400, now: now).trashCountdownLabel(now: now),
                       "1 day left")
        XCTAssertEqual(seenTrashed(secondsAgo: 15 * 86_400, now: now).trashCountdownLabel(now: now),
                       "Deleting soon")
    }
}
