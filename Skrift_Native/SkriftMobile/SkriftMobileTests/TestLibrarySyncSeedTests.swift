import XCTest
import SwiftData
@testable import SkriftMobile

/// Q336: the DEBUG "Fill with test notes" / "Remove test notes" actions. Fill seeds the deterministic
/// perf library into the NORMAL store (the one that syncs), every note marked `testLibrary: true`;
/// seeding twice never duplicates; remove deletes exactly the marked notes (soft-delete first, then
/// purge) plus the fake people; none of it exists in a Release build.
final class TestLibrarySyncSeedTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let small = PerfLibrarySeeder.Plan(total: 200)

    private func tempNames() -> NamesStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("names-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return NamesStore(fileURL: url)
    }

    @MainActor private func allMemos(_ repo: NotesRepository) -> [Memo] { repo.allMemosIncludingTrashed() }
    @MainActor private func allAssets(_ repo: NotesRepository) -> [MemoAsset] {
        (try? repo.context.fetch(FetchDescriptor<MemoAsset>())) ?? []
    }

    @MainActor
    func testFillSeedsMarkedNotesIntoTheGivenStoreAndTheFakePeopleIntoNames() throws {
        let repo = NotesRepository(inMemory: true)
        let names = tempNames()
        let summary = try TestLibrary.fill(into: repo.context, names: names, recordingsDirectory: nil,
                                           now: now, plan: small)
        let memos = allMemos(repo)
        XCTAssertEqual(memos.count, 200)
        XCTAssertEqual(summary.memosAdded, 200)
        XCTAssertTrue(memos.allSatisfy { TestLibrary.isMarked($0) }, "every seeded note carries the marker")
        XCTAssertEqual(memos.compactMap { $0.metadata?.testLibrary }.count, 200)
        XCTAssertFalse(allAssets(repo).isEmpty)
        XCTAssertEqual(summary.peopleAdded, 150)
        XCTAssertEqual(names.livePeople().count, 150)
    }

    @MainActor
    func testFillTwiceNeverDuplicates() throws {
        let repo = NotesRepository(inMemory: true)
        let names = tempNames()
        try TestLibrary.fill(into: repo.context, names: names, recordingsDirectory: nil, now: now, plan: small)
        let memoCount = allMemos(repo).count, assetCount = allAssets(repo).count
        // A later `now` shifts every date; the ids are the same, so nothing may be added.
        let again = try TestLibrary.fill(into: repo.context, names: names, recordingsDirectory: nil,
                                         now: now.addingTimeInterval(86_400 * 3), plan: small)
        XCTAssertEqual(again.memosAdded, 0)
        XCTAssertEqual(again.peopleAdded, 0)
        XCTAssertEqual(allMemos(repo).count, memoCount)
        XCTAssertEqual(allAssets(repo).count, assetCount)
        XCTAssertEqual(Set(allMemos(repo).map(\.id)).count, memoCount, "no id twice")
        XCTAssertEqual(names.livePeople().count, 150)
    }

    @MainActor
    func testRemoveDeletesOnlyMarkedNotesAndFakePeople() throws {
        let repo = NotesRepository(inMemory: true)
        let names = tempNames()
        // Real data that must survive: a note with an asset, a real person, and a real person who
        // happens to share a fake name but has a voiceprint (never touched).
        let mine = Memo(transcript: "my real note")
        repo.insert(mine)
        repo.context.insert(MemoAsset(memoID: mine.id, kind: MemoAsset.Kind.photo, filename: "photo_mine.jpg",
                                      blob: Data([1, 2, 3])))
        repo.save()
        var enrolled = PerfLibrarySeeder.makePeople(count: 150, now: now)[0]
        enrolled.voiceEmbeddings = [VoiceEmbedding(vector: [0.1, 0.2])]
        names.save(NamesData(lastModifiedAt: ISO8601.now(), people: [
            Person(canonical: "[[Zed Realperson]]", aliases: ["Zed"], short: "Zed", lastModifiedAt: ISO8601.now()),
            enrolled,
        ]))

        try TestLibrary.fill(into: repo.context, names: names, recordingsDirectory: nil, now: now, plan: small)
        XCTAssertEqual(allMemos(repo).count, 201)

        let removed = try TestLibrary.remove(from: repo.context, names: names)
        XCTAssertEqual(removed.memos, 200)
        XCTAssertGreaterThan(removed.assets, 0)
        XCTAssertEqual(removed.people, 149, "the fake people, minus the one that has a voiceprint")

        XCTAssertEqual(allMemos(repo).map(\.id), [mine.id], "only the real note is left")
        XCTAssertEqual(allAssets(repo).map(\.filename), ["photo_mine.jpg"], "the real note's asset stays, every test asset is gone")
        XCTAssertEqual(Set(names.livePeople().map(\.canonical)), ["[[Zed Realperson]]", enrolled.canonical])
        XCTAssertEqual(names.load().people.filter(\.isDeleted).count, 149,
                       "removed people are tombstones, so the removal syncs")
    }

    @MainActor
    func testRemoveSoftDeletesBeforeItPurges() throws {
        let repo = NotesRepository(inMemory: true)
        let names = tempNames()
        try TestLibrary.fill(into: repo.context, names: names, recordingsDirectory: nil, now: now, plan: small)
        var sawSoftDeleted = false
        try TestLibrary.remove(from: repo.context, names: names, afterSoftDelete: {
            let memos = repo.allMemosIncludingTrashed()
            XCTAssertEqual(memos.count, 200, "still there between the two steps")
            XCTAssertTrue(memos.allSatisfy { $0.deletedAt != nil && $0.trashSeenAt != nil }, "trashed first")
            sawSoftDeleted = true
        })
        XCTAssertTrue(sawSoftDeleted)
        XCTAssertTrue(allMemos(repo).isEmpty)
    }

    @MainActor
    func testRemoveRunsTheLocalFileCleanupForEachNote() throws {
        let repo = NotesRepository(inMemory: true)
        let names = tempNames()
        try TestLibrary.fill(into: repo.context, names: names, recordingsDirectory: nil, now: now, plan: small)
        var ids = Set<UUID>()
        try TestLibrary.remove(from: repo.context, names: names, deleteLocalFiles: { ids.insert($0.id) })
        XCTAssertEqual(ids.count, 200)
    }

    @MainActor
    func testFillAfterRemoveBringsTheLibraryBack() throws {
        let repo = NotesRepository(inMemory: true)
        let names = tempNames()
        try TestLibrary.fill(into: repo.context, names: names, recordingsDirectory: nil, now: now, plan: small)
        try TestLibrary.remove(from: repo.context, names: names)
        let again = try TestLibrary.fill(into: repo.context, names: names, recordingsDirectory: nil, now: now, plan: small)
        XCTAssertEqual(again.memosAdded, 200)
        XCTAssertEqual(again.peopleAdded, 150)
        XCTAssertEqual(names.livePeople().count, 150, "a tombstoned fake person comes back live")
    }

    @MainActor
    func testPlainPerfSeedHasNoMarker() throws {
        let repo = NotesRepository(inMemory: true)
        try PerfLibrarySeeder.seed(into: repo.context, recordingsDirectory: nil, now: now, plan: small)
        XCTAssertTrue(allMemos(repo).allSatisfy { !TestLibrary.isMarked($0) }, "-perfLibrary output is unchanged")
    }

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

    // MARK: Release guard

    private var nativeRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: nativeRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    func testTheSeederFilesAreEntirelyDebugOnly() throws {
        for file in ["Shared/Corpus/TestLibrarySync.swift", "Shared/Corpus/TestLibraryRunner.swift",
                     "Shared/Corpus/PerfLibrarySeeder.swift",
                     "SkriftMobile/Features/Settings/TestLibrarySettingsSection.swift",
                     "SkriftDesktop/Features/Settings/TestLibraryMacSection.swift"] {
            let text = try source(file).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertTrue(text.hasPrefix("#if DEBUG"), "\(file) must open with #if DEBUG")
            XCTAssertTrue(text.hasSuffix("#endif"), "\(file) must close with #endif")
        }
    }

    func testEverySettingsMentionOfTheTestLibraryIsInsideADebugBlock() throws {
        for file in ["SkriftMobile/Features/Settings/SettingsView.swift",
                     "SkriftDesktop/Features/Settings/SettingsView.swift"] {
            var stack: [Bool] = []   // true = a `#if DEBUG` block (an `#else` of it is not debug)
            var mentions = 0
            for line in try source(file).split(separator: "\n", omittingEmptySubsequences: false) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("#if") { stack.append(t == "#if DEBUG") }
                else if t.hasPrefix("#else"), !stack.isEmpty { stack[stack.count - 1] = false }
                else if t.hasPrefix("#endif"), !stack.isEmpty { stack.removeLast() }
                else if t.contains("TestLibrary") {
                    mentions += 1
                    XCTAssertTrue(stack.contains(true), "\(file): `\(t)` is outside #if DEBUG")
                }
            }
            XCTAssertGreaterThan(mentions, 0, "\(file) must show the rows")
        }
    }
}
