import XCTest
import Foundation

/// Q418 (C254/R62): same full name = same person. Adding a person whose full name matches an
/// existing one, case-insensitively, merges into that row (aliases and voiceprints unioned) on
/// every add path — Settings (`upsert(_:replacing:)`), the assign sheet (`createIfNeeded`,
/// `upsert(canonical:…)`), the names sync (`NamesSyncCore` / `NamesMerge`) — and raises the
/// "Merged into John Smith" notice. Fixture: test-fixtures/corpus/rosters/roster-duplicate-canonical.json.
final class RosterDuplicateMergeTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Expect: Decodable {
            let canonical: String
            let aliasesContain: [String]
            let voiceprints: Int
            let notice: String
        }
        let existing: NamesData
        let add: Person
        let remote: NamesData
        let expect: Expect
    }

    private func fixture() throws -> Fixture {
        let url = CorpusSeed.fixtureRoot(file: #filePath)
            .appendingPathComponent("rosters/roster-duplicate-canonical.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private func seededStore(_ f: Fixture) -> NamesStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("names_q418_\(UUID().uuidString).json")
        let store = NamesStore(fileURL: url)
        _ = store.save(f.existing)
        return store
    }

    /// Collect every merge notice posted while `body` runs.
    private func notices(center: NotificationCenter = .default, _ body: () -> Void) -> [String] {
        var out: [String] = []
        let token = center.addObserver(forName: .namesMergedDuplicate, object: nil, queue: nil) { note in
            if let line = RosterMergeNotice.message(from: note) { out.append(line) }
        }
        defer { center.removeObserver(token) }
        body()
        return out
    }

    private func assertOneMergedRow(_ people: [Person], _ f: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        let live = people.filter { !$0.isDeleted }
        let rows = live.filter { NamesMerge.matchKey($0.canonical) == NamesMerge.matchKey(f.expect.canonical) }
        XCTAssertEqual(rows.count, 1, "one row per full name", file: file, line: line)
        XCTAssertEqual(rows.first?.canonical, f.expect.canonical, "the existing spelling survives", file: file, line: line)
        for a in f.expect.aliasesContain {
            XCTAssertTrue(rows.first?.aliases.contains(a) ?? false, "alias \(a) unioned", file: file, line: line)
        }
        XCTAssertEqual(rows.first?.voiceEmbeddings?.count, f.expect.voiceprints, "voiceprints unioned", file: file, line: line)
        XCTAssertEqual(live.count, f.existing.people.count, "no person added", file: file, line: line)
    }

    // Settings add (both apps' person editor → `upsert(_:replacing: nil)`).
    func testSettingsAddCaseVariantMergesAndSaysSo() throws {
        let f = try fixture()
        let store = seededStore(f)
        var result: String?
        let posted = notices { result = store.upsert(f.add, replacing: nil) }
        XCTAssertEqual(result, f.expect.canonical)
        XCTAssertEqual(posted, [f.expect.notice])
        assertOneMergedRow(store.load().people, f)
        XCTAssertEqual(store.livePeople().first { $0.canonical == f.expect.canonical }?.short, "John", "short kept")
    }

    // A rename onto another person's full name folds the renamed row into that person.
    func testRenameOntoExistingFullNameMerges() throws {
        let f = try fixture()
        let store = seededStore(f)
        store.upsert(Person(canonical: "[[Jon Smit]]", aliases: ["Smithy"], short: nil,
                            voiceEmbeddings: f.add.voiceEmbeddings, lastModifiedAt: ""), replacing: nil)
        let posted = notices {
            store.upsert(Person(canonical: "[[john smith]]", aliases: ["Smithy"], short: nil,
                                voiceEmbeddings: f.add.voiceEmbeddings, lastModifiedAt: ""),
                         replacing: "[[Jon Smit]]")
        }
        XCTAssertEqual(posted, [f.expect.notice])
        assertOneMergedRow(store.load().people, f)
        XCTAssertEqual(store.load().people.first { $0.canonical == "[[Jon Smit]]" }?.isDeleted, true)
    }

    // Assign sheet (phone "New person" field → `createIfNeeded`; Mac popover → `upsert(canonical:…)`).
    func testAssignSheetCaseVariantMergesAndSaysSo() throws {
        let f = try fixture()
        let store = seededStore(f)
        var person: Person?
        let posted = notices { person = PersonEditCore.createIfNeeded(fullName: "JOHN SMITH", in: store) }
        XCTAssertEqual(person?.canonical, f.expect.canonical)
        XCTAssertEqual(posted, [f.expect.notice])
        XCTAssertEqual(store.livePeople().count, f.existing.people.count)

        // Picking the person from the list is not an add: nothing announced.
        XCTAssertEqual(notices { _ = PersonEditCore.createIfNeeded(fullName: "John Smith", announceMerge: false, in: store) }, [])

        var merged: String?
        let quick = notices { merged = store.upsert(canonical: "john smith", aliases: ["Smithy"], short: "J") }
        XCTAssertEqual(merged, f.expect.canonical)
        XCTAssertEqual(quick, [f.expect.notice])
        let row = store.livePeople().first { $0.canonical == f.expect.canonical }
        XCTAssertEqual(row?.short, "John", "a live person's short is never overwritten")
        XCTAssertTrue(row?.aliases.contains("Smithy") ?? false)
        XCTAssertEqual(store.livePeople().count, f.existing.people.count)

        // The voiceprint learned for the typed spelling lands on the same row.
        store.addVoiceEmbedding(canonical: "john smith", embedding: f.add.voiceEmbeddings![0])
        XCTAssertEqual(store.livePeople().first { $0.canonical == f.expect.canonical }?.voiceEmbeddings?.count, 2)
        XCTAssertEqual(store.livePeople().count, f.existing.people.count)
    }

    // The sync merge: a carrier holding a case variant folds into the local row and says so.
    func testSyncCaseVariantMergesAndSaysSo() throws {
        let f = try fixture()
        let blob = try JSONEncoder().encode(f.remote)
        var inserted: [NamesRecord] = []
        let outcome = try XCTUnwrap(NamesSyncCore.reconcile(
            localPeople: f.existing.people, records: [NamesRecord(blob: blob)],
            insert: { inserted.append($0) }, delete: { _ in }))
        assertOneMergedRow(outcome.merged.people, f)
        XCTAssertEqual(outcome.mergedInto, [f.expect.canonical])
        XCTAssertTrue(outcome.localChanged)

        let center = NotificationCenter()
        XCTAssertEqual(notices(center: center) { NamesSyncCore.notifyIfChanged(outcome, center: center) },
                       [f.expect.notice])
    }

    // The fold is symmetric (every device picks the same row) and leaves tombstones alone.
    func testFoldIsOrderIndependentAndSparesTombstones() throws {
        let f = try fixture()
        let a = NamesMerge.mergeByCanonical(local: f.existing.people, remote: f.remote.people)
        let b = NamesMerge.mergeByCanonical(local: f.remote.people, remote: f.existing.people)
        XCTAssertEqual(NamesMerge.sortPeople(a).map(\.canonical), NamesMerge.sortPeople(b).map(\.canonical))

        let tomb = Person(canonical: "[[JOHN SMITH]]", aliases: ["JS"], short: nil,
                          lastModifiedAt: "2026-09-05T00:00:00Z", deleted: true)
        let r = NamesMerge.mergeReporting(local: f.existing.people, remote: [tomb])
        XCTAssertEqual(r.mergedInto, [], "a tombstone of another spelling is not a merge")
        XCTAssertEqual(r.people.filter { !$0.isDeleted }.count, f.existing.people.count, "the live row survives")
    }
}
