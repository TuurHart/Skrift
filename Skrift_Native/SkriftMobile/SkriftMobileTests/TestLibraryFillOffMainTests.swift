import XCTest
import SwiftData
@testable import SkriftMobile

/// Q340: "Fill with test notes" keeps the main actor free: the seeder runs off main, saves in batches,
/// moves no repository version while it works, and the marked count and index snapshots are cheap.
final class TestLibraryFillOffMainTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let small = PerfLibrarySeeder.Plan(total: 200)

    private func tempNames() -> NamesStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("names-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return NamesStore(fileURL: url)
    }

    @MainActor private func allMemos(_ repo: NotesRepository) -> [Memo] { repo.allMemosIncludingTrashed() }

    // MARK: Q340 - Fill stays off the main actor and saves in batches

    private final class SaveCounter: @unchecked Sendable {
        private let lock = NSLock(); private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    /// Thread-safe recorder for the progress callback (runs on the worker thread).
    private final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var _phases: [String] = [], _mainHits = 0
        func note(_ phase: String) {
            lock.lock(); _phases.append(phase); if Thread.isMainThread { _mainHits += 1 }; lock.unlock()
        }
        var phases: [String] { lock.lock(); defer { lock.unlock() }; return _phases }
        var mainHits: Int { lock.lock(); defer { lock.unlock() }; return _mainHits }
    }

    @MainActor
    func testFillWorkRunsTheSeederOffTheMainThread() async throws {
        let repo = NotesRepository(inMemory: true)
        let seen = Seen()
        let summary = try await TestLibraryRunner.fillWork(
            container: repo.container, recordingsDirectory: nil, names: tempNames(), now: now, plan: small
        ) { phase, _, _ in seen.note(phase) }
        XCTAssertEqual(summary.memosAdded, 200)
        XCTAssertFalse(seen.phases.isEmpty, "progress was reported")
        XCTAssertEqual(seen.mainHits, 0, "seeding must never run on the main thread")
        XCTAssertEqual(allMemos(repo).count, 200, "the main context sees what the worker saved")
    }

    @MainActor
    func testFillWorkDoesNotBumpTheRepositoryVersionsPerBatch() async throws {
        let repo = NotesRepository(inMemory: true)
        let set0 = repo.memoSetVersion, structure0 = repo.memoStructureVersion
        _ = try await TestLibraryRunner.fillWork(container: repo.container, recordingsDirectory: nil,
                                                 names: tempNames(), now: now, plan: PerfLibrarySeeder.Plan(total: 600))
        XCTAssertEqual(repo.memoSetVersion, set0, "no list-base / backlink rebuild while the worker saves")
        XCTAssertEqual(repo.memoStructureVersion, structure0)
    }

    @MainActor
    func testSeederSavesInBatchesNotPerNote() throws {
        let repo = NotesRepository(inMemory: true)
        let total = PerfLibrarySeeder.saveBatch * 2 + 40
        let counter = SaveCounter()
        let token = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { _ in counter.bump() }
        defer { NotificationCenter.default.removeObserver(token) }
        let context = ModelContext(repo.container)
        context.autosaveEnabled = false
        let summary = try PerfLibrarySeeder.seed(into: context, recordingsDirectory: nil, now: now,
                                                 plan: PerfLibrarySeeder.Plan(total: total))
        XCTAssertEqual(summary.memos, total)
        XCTAssertGreaterThanOrEqual(PerfLibrarySeeder.saveBatch, 100, "a batch is many notes")
        let saves = counter.value
        XCTAssertLessThanOrEqual(saves, total / PerfLibrarySeeder.saveBatch + 1,
                                 "one save per batch plus the tail, not one per note (\(saves) saves for \(total) notes)")
        XCTAssertGreaterThan(saves, 1, "and it does save along the way")
    }

    @MainActor
    func testSkippedNotesDoNotCountTowardsABatch() throws {
        let repo = NotesRepository(inMemory: true)
        let total = 120
        let names = tempNames()
        _ = try TestLibrary.fill(into: ModelContext(repo.container), names: names, recordingsDirectory: nil,
                                 now: now, plan: PerfLibrarySeeder.Plan(total: total))
        let counter = SaveCounter()
        let token = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { _ in counter.bump() }
        defer { NotificationCenter.default.removeObserver(token) }
        let again = try TestLibrary.fill(into: ModelContext(repo.container), names: names, recordingsDirectory: nil,
                                         now: now, plan: PerfLibrarySeeder.Plan(total: total))
        XCTAssertEqual(again.memosAdded, 0)
        XCTAssertEqual(counter.value, 0, "a fill that adds nothing writes nothing")
    }

    @MainActor
    func testMarkedCountIsReadOffTheMainActorAndMatches() async throws {
        let repo = NotesRepository(inMemory: true)
        repo.insert(Memo(transcript: "mine")); repo.save()
        _ = try TestLibrary.fill(into: ModelContext(repo.container), names: tempNames(), recordingsDirectory: nil,
                                 now: now, plan: small)
        let count = await TestLibraryRunner.markedCount(in: repo.container)
        XCTAssertEqual(count, 200, "the real note is not counted")
    }

    @MainActor
    func testIndexSnapshotsUseTheNewestPolishPerNote() throws {
        let repo = NotesRepository(inMemory: true)
        let m = Memo(transcript: "raw words here"); m.significance = 0.9
        repo.insert(m)
        let old = MemoEnhancement(memoID: m.id, copyedit: "older polish", title: "Old", summary: "S")
        old.enhancedAt = now.addingTimeInterval(-100)
        let new = MemoEnhancement(memoID: m.id, copyedit: "newer polish", title: "New", summary: "S")
        new.enhancedAt = now
        repo.context.insert(old); repo.context.insert(new)
        repo.save()
        let snaps = JournalIndexService.snapshots(from: repo)
        XCTAssertEqual(snaps.count, 1)
        XCTAssertTrue(snaps[0].body.contains("newer polish"))
        XCTAssertFalse(snaps[0].body.contains("older polish"))
    }
}
