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

    // MARK: Release guard

    private var nativeRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: nativeRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    func testTheSeederFilesAreEntirelyDebugOnly() throws {
        for file in ["Shared/Corpus/TestLibrarySync.swift", "Shared/Corpus/PerfLibrarySeeder.swift",
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
