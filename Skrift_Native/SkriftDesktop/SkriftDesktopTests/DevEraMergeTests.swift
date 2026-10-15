import SQLite3
import XCTest
import SwiftData
import Foundation

/// Q398 (D203, ICLOUD_MERGE.md A2): the Dev-era merge engine on synthetic stores only. OLD = the
/// August Mac's Development-era store, PROD = the live Production store. Never a real store,
/// never CloudKit (`isStoredInMemoryOnly` / temp files with `cloudKitDatabase: .none`).
@MainActor
final class DevEraMergeTests: XCTestCase {

    private let mac = "mac-device"
    private let phone = "phone-device"
    private let S = DevEraMerge.splitDate
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("q398_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: scratch)
        super.tearDown()
    }

    // MARK: - Fixtures

    private func store() throws -> ModelContext {
        let container = try ModelContainer(for: DevEraMerge.storeSchema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func day(_ offset: Double) -> Date { S.addingTimeInterval(offset * 86_400) }

    @discardableResult
    private func memo(_ ctx: ModelContext, id: UUID = UUID(), device: String?, recorded: Date,
                      title: String? = nil, transcript: String? = "words", editedAt: Date? = nil,
                      significance: Double = 0, deletedAt: Date? = nil) -> Memo {
        let m = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: recorded, title: title,
                     transcript: transcript, transcriptStatus: .done, significance: significance,
                     deletedAt: deletedAt, createdAt: recorded, editedAt: editedAt, recordingDeviceID: device)
        if deletedAt != nil { m.trashSeenAt = deletedAt }
        ctx.insert(m)
        return m
    }

    /// The same note on both sides, as it stood at S (synced through Development before the split).
    private func shared(_ old: ModelContext, _ prod: ModelContext, title: String? = "Same",
                        significance: Double = 0) -> UUID {
        let id = UUID()
        memo(old, id: id, device: phone, recorded: day(-30), title: title, significance: significance)
        memo(prod, id: id, device: phone, recorded: day(-30), title: title, significance: significance)
        return id
    }

    private func plan(_ old: ModelContext, _ prod: ModelContext) throws -> DevEraMerge.Plan {
        try old.save(); try prod.save()
        return try DevEraMerge.plan(old: old, prod: prod, macDeviceIDs: [mac])
    }

    @discardableResult
    private func merge(_ old: ModelContext, _ prod: ModelContext) throws -> (DevEraMerge.Plan, DevEraMerge.UndoJournal) {
        let p = try plan(old, prod)
        let j = try DevEraMerge.apply(p, from: old, into: prod, firstImportDone: true)
        return (p, j)
    }

    private func prodMemo(_ id: UUID, _ prod: ModelContext) throws -> [Memo] {
        try prod.fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id }))
    }

    // MARK: - Shared notes

    /// Production unchanged since S and no Mac edit after S: a difference has no stamp saying who
    /// made it, so Production is kept and the id is listed as diverged.
    func testSharedNoteWithoutMacEditKeepsProduction() throws {
        let old = try store(), prod = try store()
        let id = shared(old, prod)
        try prodMemo(id, prod).first?.title = "Same"
        let oldRow = try old.fetch(FetchDescriptor<Memo>()).first { $0.id == id }!
        oldRow.title = "Mac setTitle, no stamp"

        let (p, j) = try merge(old, prod)
        XCTAssertEqual(try prodMemo(id, prod).map(\.title), ["Same"])
        XCTAssertTrue(j.fieldChanges.isEmpty)
        XCTAssertEqual(p.diverged[id], [.title])
        XCTAssertTrue(p.conflicts.isEmpty)
    }

    /// Production unchanged since S, Mac edited after S: the Mac's content is copied in place.
    func testSharedNoteMacEditedAfterSplitIsCopied() throws {
        let old = try store(), prod = try store()
        let id = shared(old, prod)
        let oldRow = try old.fetch(FetchDescriptor<Memo>()).first { $0.id == id }!
        oldRow.title = "Mac title"; oldRow.transcript = "Mac body"; oldRow.transcriptUserEdited = true
        oldRow.tags = ["mac"]; oldRow.significance = 0.6
        oldRow.editedAt = day(3); oldRow.keptAt = day(3)

        let (p, _) = try merge(old, prod)
        let rows = try prodMemo(id, prod)
        XCTAssertEqual(rows.count, 1, "updated in place, no second row")
        XCTAssertEqual(rows[0].title, "Mac title")
        XCTAssertEqual(rows[0].transcript, "Mac body")
        XCTAssertTrue(rows[0].transcriptUserEdited)
        XCTAssertEqual(rows[0].tags, ["mac"])
        XCTAssertEqual(rows[0].significance, 0.6, "Production was unrated, so the Mac's rating is taken")
        XCTAssertEqual(rows[0].editedAt, day(3))
        XCTAssertEqual(p.counts.fieldCopies[.title], 1)
    }

    /// A rating Production already has is never overwritten (the phone's rating leaves no stamp).
    func testMacEditNeverOverwritesAProductionRating() throws {
        let old = try store(), prod = try store()
        let id = shared(old, prod, significance: 0.3)
        try prodMemo(id, prod).first?.significance = 0.8
        let oldRow = try old.fetch(FetchDescriptor<Memo>()).first { $0.id == id }!
        oldRow.title = "Mac title"; oldRow.significance = 0.5; oldRow.editedAt = day(2)

        let (p, _) = try merge(old, prod)
        XCTAssertEqual(try prodMemo(id, prod).first?.significance, 0.8)
        XCTAssertEqual(try prodMemo(id, prod).first?.title, "Mac title")
        XCTAssertEqual(p.diverged[id], [.rating])
    }

    /// Edited on both sides after S: Production kept, id listed as a conflict.
    func testEditedOnBothSidesIsAConflict() throws {
        let old = try store(), prod = try store()
        let id = shared(old, prod)
        let oldRow = try old.fetch(FetchDescriptor<Memo>()).first { $0.id == id }!
        oldRow.title = "Mac"; oldRow.editedAt = day(2)
        let prodRow = try prodMemo(id, prod)[0]
        prodRow.title = "Phone"; prodRow.editedAt = day(4)

        let (p, j) = try merge(old, prod)
        XCTAssertEqual(try prodMemo(id, prod).first?.title, "Phone")
        XCTAssertEqual(p.conflicts, [id])
        XCTAssertEqual(j.conflicts, [id])
    }

    /// A Mac trash after S reaches an untouched Production row; a Mac restore of a note trashed
    /// before S does too.
    func testMacTrashAndRestoreAfterSplitAreCopied() throws {
        let old = try store(), prod = try store()
        let trashed = shared(old, prod)
        try old.fetch(FetchDescriptor<Memo>()).first { $0.id == trashed }!.deletedAt = day(5)

        let restored = UUID()
        memo(old, id: restored, device: phone, recorded: day(-40))
        memo(prod, id: restored, device: phone, recorded: day(-40), deletedAt: day(-3))
        try old.fetch(FetchDescriptor<Memo>()).first { $0.id == restored }!.keptAt = day(1)

        try merge(old, prod)
        XCTAssertEqual(try prodMemo(trashed, prod).first?.deletedAt, day(5))
        let back = try prodMemo(restored, prod)[0]
        XCTAssertNil(back.deletedAt)
        XCTAssertNil(back.trashSeenAt)
        XCTAssertEqual(back.keptAt, day(1))
    }

    // MARK: - Old-only notes

    /// A Mac-made note is inserted once, with all its assets and its enhancement.
    func testMacMadeNoteInsertedOnceWithAssets() throws {
        let old = try store(), prod = try store()
        let id = UUID()
        memo(old, id: id, device: mac, recorded: day(-60), title: "Mac recording")
        old.insert(MemoAsset(memoID: id, kind: MemoAsset.Kind.audio, filename: "memo_\(id).m4a", blob: Data(repeating: 1, count: 100)))
        old.insert(MemoAsset(memoID: id, kind: MemoAsset.Kind.photo, filename: "photo_\(id)_001.jpg", blob: Data(repeating: 2, count: 10)))
        old.insert(MemoEnhancement(memoID: id, copyedit: "polished", enhancedByDeviceID: mac, enhancedAt: day(1)))

        let (p, j) = try merge(old, prod)
        XCTAssertEqual(p.counts.oldOnlyMacMade, 1)
        XCTAssertEqual(j.insertedNoteIDs, [id])
        XCTAssertEqual(try prodMemo(id, prod).count, 1)
        XCTAssertEqual(try prodMemo(id, prod).first?.title, "Mac recording")
        let assets = try prod.fetch(FetchDescriptor<MemoAsset>()).filter { $0.memoID == id }
        XCTAssertEqual(Set(assets.map(\.kind)), [MemoAsset.Kind.audio, MemoAsset.Kind.photo])
        XCTAssertEqual(assets.map(\.byteCount).reduce(0, +), 110)
        XCTAssertEqual(try prod.fetch(FetchDescriptor<MemoEnhancement>()).map(\.copyedit), ["polished"])
    }

    /// A phone note recorded after S that reached the Mac but not Production is inserted.
    func testPhoneNoteAfterSplitInserted() throws {
        let old = try store(), prod = try store()
        let id = UUID()
        memo(old, id: id, device: phone, recorded: day(2))
        let (p, j) = try merge(old, prod)
        XCTAssertEqual(p.counts.oldOnlyPhoneAfterSplit, 1)
        XCTAssertEqual(j.insertedNoteIDs, [id])
        XCTAssertEqual(try prodMemo(id, prod).count, 1)
    }

    /// A phone note recorded before S, only in the old store, is never inserted; a trashed old-only
    /// note is skipped.
    func testPhoneNoteBeforeSplitNeverInserted() throws {
        let old = try store(), prod = try store()
        let before = UUID(), trashed = UUID()
        memo(old, id: before, device: phone, recorded: day(-10))
        memo(old, id: trashed, device: mac, recorded: day(-5), deletedAt: day(1))
        let (p, j) = try merge(old, prod)
        XCTAssertEqual(p.counts.oldOnlyPhoneBeforeSplit, 1)
        XCTAssertEqual(p.counts.oldOnlyTrashed, 1)
        XCTAssertTrue(j.insertedNoteIDs.isEmpty)
        XCTAssertEqual(try prod.fetchCount(FetchDescriptor<Memo>()), 0)
        XCTAssertEqual(p.counts.phoneBeforeSplitByMonth, ["2026-09": 1])
    }

    /// More than 20 such notes: Production probably lacks the phone's history. Apply refuses with a
    /// clear error and writes nothing.
    func testMoreThanTwentyPhoneNotesBeforeSplitStops() throws {
        let old = try store(), prod = try store()
        for i in 0..<21 { memo(old, device: phone, recorded: day(-Double(i + 1))) }
        let macNote = memo(old, device: mac, recorded: day(-1))
        let p = try plan(old, prod)
        XCTAssertEqual(p.blocked, .tooManyPhoneNotesBeforeSplit(count: 21, limit: 20))
        XCTAssertThrowsError(try DevEraMerge.apply(p, from: old, into: prod, firstImportDone: true)) { error in
            XCTAssertEqual(error as? DevEraMerge.MergeError, .tooManyPhoneNotesBeforeSplit(count: 21, limit: 20))
            XCTAssertTrue(String(describing: error).contains("Re-plan"))
        }
        XCTAssertEqual(try prod.fetchCount(FetchDescriptor<Memo>()), 0, "nothing written, not even the Mac note")
        XCTAssertEqual(p.inserts, [macNote.id])
    }

    /// Exactly 20 is still allowed.
    func testTwentyPhoneNotesBeforeSplitIsAllowed() throws {
        let old = try store(), prod = try store()
        for i in 0..<20 { memo(old, device: phone, recorded: day(-Double(i + 1))) }
        XCTAssertNil(try plan(old, prod).blocked)
    }

    // MARK: - Guards

    /// The engine refuses to run before the Production store's first import is done (Q397 stamp).
    func testRefusesBeforeFirstImport() throws {
        let old = try store(), prod = try store()
        memo(old, device: mac, recorded: day(-1))
        let p = try plan(old, prod)
        let storeURL = scratch.appendingPathComponent("memo_cloud.store")
        let stamp = scratch.appendingPathComponent("memo_cloud.first-import.json")
        try Data("sqlite".utf8).write(to: storeURL)

        let notDone = DevEraMerge.firstImportDone(prodStoreURL: storeURL, stampURL: stamp)
        XCTAssertFalse(notDone)
        XCTAssertThrowsError(try DevEraMerge.apply(p, from: old, into: prod, firstImportDone: notDone)) {
            XCTAssertEqual($0 as? DevEraMerge.MergeError, .firstImportNotDone)
        }
        XCTAssertEqual(try prod.fetchCount(FetchDescriptor<Memo>()), 0)

        CloudFirstImport.markDone(storeURL: storeURL, stampURL: stamp)
        let done = DevEraMerge.firstImportDone(prodStoreURL: storeURL, stampURL: stamp)
        XCTAssertTrue(done)
        try DevEraMerge.apply(p, from: old, into: prod, firstImportDone: done)
        XCTAssertEqual(try prod.fetchCount(FetchDescriptor<Memo>()), 1)
    }

    // MARK: - Enhancements

    /// Newer `enhancedAt` wins, written into the Production row in place (no second row). Production
    /// newer keeps Production; a tie keeps Production; `processedAt` takes the later value.
    func testEnhancementNewerWinsInPlace() throws {
        let old = try store(), prod = try store()
        let oldNewer = shared(old, prod), prodNewer = shared(old, prod), tie = shared(old, prod)
        old.insert(MemoEnhancement(memoID: oldNewer, copyedit: "old polish", enhancedAt: day(5)))
        prod.insert(MemoEnhancement(memoID: oldNewer, copyedit: "prod polish", enhancedAt: day(-5)))
        old.insert(MemoEnhancement(memoID: prodNewer, copyedit: "old polish", enhancedAt: day(1), processedAt: day(9)))
        prod.insert(MemoEnhancement(memoID: prodNewer, copyedit: "prod polish", enhancedAt: day(2), processedAt: day(2)))
        old.insert(MemoEnhancement(memoID: tie, copyedit: "old polish", enhancedAt: day(3)))
        prod.insert(MemoEnhancement(memoID: tie, copyedit: "prod polish", enhancedAt: day(3)))

        let (p, _) = try merge(old, prod)
        func rows(_ id: UUID) throws -> [MemoEnhancement] {
            try prod.fetch(FetchDescriptor<MemoEnhancement>()).filter { $0.memoID == id }
        }
        XCTAssertEqual(try rows(oldNewer).map(\.copyedit), ["old polish"])
        XCTAssertEqual(try rows(oldNewer).first?.enhancedAt, day(5))
        XCTAssertEqual(try rows(prodNewer).map(\.copyedit), ["prod polish"])
        XCTAssertEqual(try rows(prodNewer).first?.processedAt, day(9), "processedAt takes the later value")
        XCTAssertEqual(try rows(tie).map(\.copyedit), ["prod polish"])
        XCTAssertEqual(p.counts.enhancementsOldNewer, 1)
        XCTAssertEqual(p.counts.enhancementsProdNewer, 1)
        XCTAssertEqual(p.counts.enhancementsTie, 1)
        XCTAssertEqual(try prod.fetchCount(FetchDescriptor<MemoEnhancement>()), 3, "no second row anywhere")
    }

    /// An enhancement for a note that ends up nowhere in Production (phone before S) is not inserted.
    func testEnhancementOfSkippedNoteIsNotInserted() throws {
        let old = try store(), prod = try store()
        let skipped = memo(old, device: phone, recorded: day(-10))
        old.insert(MemoEnhancement(memoID: skipped.id, copyedit: "x", enhancedAt: day(1)))
        try merge(old, prod)
        XCTAssertEqual(try prod.fetchCount(FetchDescriptor<MemoEnhancement>()), 0)
    }

    // MARK: - Report, unmerge, idempotence, batches

    /// `merge-report.txt` lists every inserted note id, and holds no title or body text.
    func testReportListsInsertedIDs() throws {
        let old = try store(), prod = try store()
        let a = memo(old, device: mac, recorded: day(-3), title: "SECRET TITLE", transcript: "SECRET BODY")
        let b = memo(old, device: phone, recorded: day(4))
        let (p, j) = try merge(old, prod)
        let dir = scratch.appendingPathComponent("merged", isDirectory: true)
        try DevEraMerge.writeReport(plan: p, journal: j, to: dir)

        let text = try String(contentsOf: dir.appendingPathComponent(DevEraMerge.reportFileName), encoding: .utf8)
        XCTAssertTrue(text.contains("inserted note ids (2):"))
        XCTAssertTrue(text.contains(a.id.uuidString))
        XCTAssertTrue(text.contains(b.id.uuidString))
        XCTAssertFalse(text.contains("SECRET"), "counts and ids only")
        XCTAssertEqual(try DevEraMerge.readJournal(from: dir), j)
    }

    /// Unmerge trashes the inserted notes, removes inserted enhancements, and restores every changed
    /// field and enhancement, reading the journal back from disk.
    func testUnmergeRestores() throws {
        let old = try store(), prod = try store()
        let inserted = memo(old, device: mac, recorded: day(-2))
        old.insert(MemoEnhancement(memoID: inserted.id, copyedit: "new", enhancedAt: day(1)))
        let edited = shared(old, prod)
        let oldRow = try old.fetch(FetchDescriptor<Memo>()).first { $0.id == edited }!
        oldRow.title = "Mac title"; oldRow.editedAt = day(2)
        let polished = shared(old, prod)
        old.insert(MemoEnhancement(memoID: polished, copyedit: "old newer", enhancedAt: day(6)))
        prod.insert(MemoEnhancement(memoID: polished, copyedit: "prod older", enhancedAt: day(-6)))

        let (p, j) = try merge(old, prod)
        XCTAssertEqual(try prodMemo(edited, prod).first?.title, "Mac title")
        let dir = scratch.appendingPathComponent("merged", isDirectory: true)
        try DevEraMerge.writeReport(plan: p, journal: j, to: dir)

        let out = try DevEraMerge.unmerge(try DevEraMerge.readJournal(from: dir), in: prod)
        try prod.save()
        XCTAssertEqual(out.notesTrashed, 1)
        XCTAssertNotNil(try prodMemo(inserted.id, prod).first?.deletedAt, "inserted note is in the trash")
        XCTAssertEqual(try prodMemo(edited, prod).first?.title, "Same")
        XCTAssertNil(try prodMemo(edited, prod).first?.editedAt)
        let enh = try prod.fetch(FetchDescriptor<MemoEnhancement>())
        XCTAssertFalse(enh.contains { $0.memoID == inserted.id }, "inserted enhancement removed")
        XCTAssertEqual(enh.first { $0.memoID == polished }?.copyedit, "prod older")
        XCTAssertEqual(enh.first { $0.memoID == polished }?.enhancedAt, day(-6))
        XCTAssertTrue(out.skippedChangedSinceMerge.isEmpty)
    }

    /// Unmerge leaves a row alone that was edited again after the merge.
    func testUnmergeSkipsRowsChangedSinceMerge() throws {
        let old = try store(), prod = try store()
        let edited = shared(old, prod)
        let oldRow = try old.fetch(FetchDescriptor<Memo>()).first { $0.id == edited }!
        oldRow.title = "Mac title"; oldRow.editedAt = day(2)
        let (_, j) = try merge(old, prod)
        try prodMemo(edited, prod).first?.title = "Typed after the merge"
        let out = try DevEraMerge.unmerge(j, in: prod)
        XCTAssertEqual(out.skippedChangedSinceMerge, [edited])
        XCTAssertEqual(try prodMemo(edited, prod).first?.title, "Typed after the merge")
    }

    /// A second run inserts nothing and changes nothing.
    func testSecondRunIsANoOp() throws {
        let old = try store(), prod = try store()
        memo(old, device: mac, recorded: day(-2))
        memo(old, device: phone, recorded: day(3))
        let edited = shared(old, prod)
        let oldRow = try old.fetch(FetchDescriptor<Memo>()).first { $0.id == edited }!
        oldRow.title = "Mac"; oldRow.editedAt = day(2); oldRow.keptAt = day(2)
        let polished = shared(old, prod)
        old.insert(MemoEnhancement(memoID: polished, copyedit: "old", enhancedAt: day(6), processedAt: day(6)))
        prod.insert(MemoEnhancement(memoID: polished, copyedit: "prod", enhancedAt: day(-6)))

        let (_, first) = try merge(old, prod)
        XCTAssertEqual(first.insertedNoteIDs.count, 2)
        let memosAfterFirst = try prod.fetchCount(FetchDescriptor<Memo>())

        let (p2, second) = try merge(old, prod)
        XCTAssertTrue(p2.inserts.isEmpty)
        XCTAssertTrue(p2.fieldCopies.isEmpty)
        XCTAssertTrue(p2.enhancementInserts.isEmpty)
        XCTAssertTrue(p2.enhancementUpdates.isEmpty)
        XCTAssertTrue(p2.conflicts.isEmpty)
        XCTAssertTrue(second.insertedNoteIDs.isEmpty)
        XCTAssertEqual(second.saves, 0)
        XCTAssertEqual(try prod.fetchCount(FetchDescriptor<Memo>()), memosAfterFirst)
    }

    /// Inserts go in batches of 25 notes per save; no new duplicate-id group appears.
    func testInsertsSaveInBatchesOf25() throws {
        let old = try store(), prod = try store()
        for i in 0..<60 { memo(old, device: mac, recorded: day(-Double(i) - 1)) }
        let dupID = shared(old, prod)
        memo(prod, id: dupID, device: phone, recorded: day(-30), title: "Same")   // a pre-existing prod twin
        let (p, j) = try merge(old, prod)
        XCTAssertEqual(j.insertedNoteIDs.count, 60)
        XCTAssertEqual(j.saves, 3, "60 notes = batches of 25, 25, 10")
        let all = try prod.fetch(FetchDescriptor<Memo>())
        let groups = Dictionary(grouping: all, by: \.id).values.filter { $0.count > 1 }.count
        XCTAssertEqual(groups, p.counts.prodDuplicateGroups, "no new duplicate group")
    }

    /// Names, words and prompts are never touched, on either side.
    func testNamesUntouched() throws {
        let old = try store(), prod = try store()
        old.insert(NamesRecord(blob: Data("old names".utf8), updatedAt: day(3)))
        prod.insert(NamesRecord(blob: Data("prod names".utf8), updatedAt: day(-3)))
        memo(old, device: mac, recorded: day(-1))
        try merge(old, prod)
        let prodNames = try prod.fetch(FetchDescriptor<NamesRecord>())
        XCTAssertEqual(prodNames.map(\.blob), [Data("prod names".utf8)])
        XCTAssertEqual(prodNames.map(\.updatedAt), [day(-3)])
        XCTAssertEqual(try old.fetch(FetchDescriptor<NamesRecord>()).map(\.blob), [Data("old names".utf8)])
    }

    // MARK: - The old store on disk

    /// The engine reads a COPY of the moved-out store: the files in `merge-from-dev/` stay byte-for-byte
    /// as they were.
    func testOldStoreIsOpenedAsACopyOnly() throws {
        let source = scratch.appendingPathComponent("merge-from-dev", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let id = UUID()
        do {
            let config = ModelConfiguration("Seed", schema: DevEraMerge.storeSchema,
                                            url: source.appendingPathComponent(DevEraMerge.storeFileName),
                                            cloudKitDatabase: .none)
            let container = try ModelContainer(for: DevEraMerge.storeSchema, configurations: config)
            let ctx = ModelContext(container)
            memo(ctx, id: id, device: mac, recorded: day(-1))
            try ctx.save()
        }
        // Fold the seeding connection's WAL into the main file so the source is quiescent before we
        // snapshot it (otherwise the seed container's own shutdown can move -wal/-shm under us).
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(source.appendingPathComponent(DevEraMerge.storeFileName).path, &db), SQLITE_OK)
        sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
        sqlite3_close(db)
        /// Per file: bytes and mtime for the store and its -wal (the data-carrying files). The -shm is
        /// only a memory-mapped index whose size follows checkpoint timing under load, so it counts by
        /// presence, not content. A file appearing or vanishing also fails the comparison.
        struct FileState: Equatable { var bytes: Data?; var mtime: Date? }
        func snapshot() throws -> [String: FileState] {
            var out: [String: FileState] = [:]
            for name in try FileManager.default.contentsOfDirectory(atPath: source.path) {
                let url = source.appendingPathComponent(name)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                    if name.hasSuffix("-shm") {
                        out[name] = FileState(bytes: nil, mtime: nil)
                    } else {
                        let mtime = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
                        out[name] = FileState(bytes: try Data(contentsOf: url), mtime: mtime)
                    }
                }
            }
            return out
        }
        XCTAssertNotNil(try snapshot()[DevEraMerge.storeFileName]?.bytes, "seeded store exists")
        let before = try snapshot()

        let copy = try DevEraMerge.openOldStoreCopy(sourceDir: source,
                                                    scratchDir: scratch.appendingPathComponent("copy", isDirectory: true))
        let old = ModelContext(copy), prod = try store()
        let (_, j) = try merge(old, prod)
        XCTAssertEqual(j.insertedNoteIDs, [id])
        XCTAssertEqual(try snapshot(), before, "source store, -wal and file set unchanged (bytes + mtime)")
    }

    func testMissingOldStoreThrows() {
        XCTAssertThrowsError(try DevEraMerge.openOldStoreCopy(sourceDir: scratch.appendingPathComponent("nope"),
                                                              scratchDir: scratch.appendingPathComponent("c")))
    }

    /// `clone` carries every stored field (a missed one would silently reset on insert).
    func testCloneCopiesEveryField() throws {
        let ctx = try store()
        let m = memo(ctx, device: mac, recorded: day(-1), title: "t", editedAt: day(1), significance: 0.4, deletedAt: day(2))
        m.audioFilename = "a.m4a"; m.duration = 12; m.tags = ["x"]; m.destinationRaw = NoteDestination.portfolio.rawValue
        m.includeAudioInExport = false; m.syncStatus = .synced; m.transcriptConfidence = 0.9
        m.transcriptUserEdited = true; m.transcriptMarkersInjected = true; m.trashSeenAt = day(3)
        m.remindAt = day(4); m.locked = true; m.metadataData = Data("m".utf8); m.sharedContentData = Data("s".utf8)
        m.annotationText = "ann"; m.nameResolutionsData = Data("n".utf8); m.keptAt = day(5)
        m.pendingDiarizationTarget = 2; m.editVectorData = Data("v".utf8); m.editStampHash = "e"
        m.polishStampHash = "p"; m.replacedAt = day(6)
        let c = DevEraMerge.clone(m)
        XCTAssertEqual(c.id, m.id); XCTAssertEqual(c.audioFilename, "a.m4a"); XCTAssertEqual(c.duration, 12)
        XCTAssertEqual(c.recordedAt, m.recordedAt); XCTAssertEqual(c.tags, ["x"])
        XCTAssertEqual(c.destinationRaw, m.destinationRaw); XCTAssertFalse(c.includeAudioInExport)
        XCTAssertEqual(c.syncStatus, .synced); XCTAssertEqual(c.title, "t"); XCTAssertEqual(c.transcript, "words")
        XCTAssertEqual(c.transcriptStatus, .done); XCTAssertEqual(c.transcriptConfidence, 0.9)
        XCTAssertTrue(c.transcriptUserEdited); XCTAssertTrue(c.transcriptMarkersInjected)
        XCTAssertEqual(c.significance, 0.4); XCTAssertEqual(c.deletedAt, day(2)); XCTAssertEqual(c.trashSeenAt, day(3))
        XCTAssertEqual(c.createdAt, m.createdAt); XCTAssertEqual(c.editedAt, day(1)); XCTAssertEqual(c.remindAt, day(4))
        XCTAssertTrue(c.locked); XCTAssertEqual(c.metadataData, m.metadataData)
        XCTAssertEqual(c.sharedContentData, m.sharedContentData); XCTAssertEqual(c.annotationText, "ann")
        XCTAssertEqual(c.nameResolutionsData, m.nameResolutionsData); XCTAssertEqual(c.recordingDeviceID, mac)
        XCTAssertEqual(c.keptAt, day(5)); XCTAssertEqual(c.pendingDiarizationTarget, 2)
        XCTAssertEqual(c.editVectorData, m.editVectorData); XCTAssertEqual(c.editStampHash, "e")
        XCTAssertEqual(c.polishStampHash, "p"); XCTAssertEqual(c.replacedAt, day(6))
    }
}
