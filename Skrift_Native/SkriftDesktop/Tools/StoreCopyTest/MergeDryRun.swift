import Foundation
import SwiftData

// Q399 (D203, plan/release/ICLOUD_MERGE.md A3): the merge dry run. Driven by
// `plan/release/mac-store-copytest.sh --merge <old store dir>`, which copies the moved Dev-era
// store (OLD) and the downloaded Production store (PROD) into a fresh temp dir first. This runs
// `DevEraMerge.plan` and `DevEraMerge.apply` on those COPIES (CloudKit off) and checks the result.
//
// Prints counts only: never a title, a transcript, a name or a note id. Exit 0 = every check
// passed; 1 = a check failed, a count dropped, or the plan says stop (more than 20 old-only phone
// notes from before S); 2 = usage or open error; 3 = refused path (the Q367 guard).

// MARK: - A store's countable shape

struct MergeSnapshot {
    var memoRows = 0, assetRows = 0, enhancementRows = 0
    var namesRecords = 0, vocabularyRecords = 0, promptRecords = 0
    var distinctIDs = 0, liveIDs = 0, trashedIDs = 0, duplicateGroups = 0
    var rowsPerID: [UUID: Int] = [:]
    var enhancementRowsPerMemo: [UUID: Int] = [:]
    /// "kind|filename" per note id (one entry per key, like the engine's asset dedupe).
    var assetKeysPerMemo: [UUID: Set<String>] = [:]
    var assetRowsPerMemo: [UUID: Int] = [:]
    var newestEnhancedAt: [UUID: Date] = [:]
    /// Keeper per id (`MemoDuplicates.keeper`), so a duplicate group counts once.
    var keepers: [UUID: Memo] = [:]

    init(_ ctx: ModelContext) throws {
        let memos = try ctx.fetch(FetchDescriptor<Memo>())
        let groups = Dictionary(grouping: memos, by: \.id)
        memoRows = memos.count
        distinctIDs = groups.count
        duplicateGroups = groups.values.filter { $0.count > 1 }.count
        for (id, rows) in groups {
            rowsPerID[id] = rows.count
            guard let k = MemoDuplicates.keeper(of: rows) else { continue }
            keepers[id] = k
            if k.deletedAt == nil { liveIDs += 1 } else { trashedIDs += 1 }
        }
        let assets = try ctx.fetch(FetchDescriptor<MemoAsset>())
        assetRows = assets.count
        for a in assets {
            assetKeysPerMemo[a.memoID, default: []].insert("\(a.kind)|\(a.filename)")
            assetRowsPerMemo[a.memoID, default: 0] += 1
        }
        let enhancements = try ctx.fetch(FetchDescriptor<MemoEnhancement>())
        enhancementRows = enhancements.count
        for e in enhancements {
            enhancementRowsPerMemo[e.memoID, default: 0] += 1
            if e.enhancedAt > (newestEnhancedAt[e.memoID] ?? .distantPast) { newestEnhancedAt[e.memoID] = e.enhancedAt }
        }
        namesRecords = try ctx.fetchCount(FetchDescriptor<NamesRecord>())
        vocabularyRecords = try ctx.fetchCount(FetchDescriptor<VocabularyRecord>())
        promptRecords = try ctx.fetchCount(FetchDescriptor<PolishPromptsRecord>())
    }
}

// MARK: - The dry run

enum MergeDryRun {

    static func line(_ label: String, _ value: Int) { print("\(label): \(value)") }

    static func describe(_ name: String, _ s: MergeSnapshot) {
        line("\(name) note rows", s.memoRows)
        line("\(name) distinct note ids", s.distinctIDs)
        line("\(name) live notes", s.liveIDs)
        line("\(name) trashed notes", s.trashedIDs)
        line("\(name) duplicate id groups", s.duplicateGroups)
        line("\(name) asset rows", s.assetRows)
        line("\(name) enhancement rows", s.enhancementRows)
    }

    static func run(old: URL, prod: URL, macDeviceIDs: Set<String>, simulateDrop: Bool) -> Never {
        CopyTestGuard.check(old)
        CopyTestGuard.check(prod)
        for url in [old, prod] where !FileManager.default.fileExists(atPath: url.path) {
            copyTestFail(2, "missing \(url.lastPathComponent) in the copy")
        }
        if macDeviceIDs.isEmpty { copyTestFail(2, "--merge-dry-run needs at least one --mac-device-id") }

        // OLD goes through the engine's own opener (a second copy, CloudKit off), as the app's
        // merge alert will. PROD is already the script's temp copy: opened in place, CloudKit off.
        let oldContainer: ModelContainer
        let prodContainer: ModelContainer
        let scratch = old.deletingLastPathComponent().appendingPathComponent("engine-copy", isDirectory: true)
        do {
            oldContainer = try DevEraMerge.openOldStoreCopy(sourceDir: old.deletingLastPathComponent(), scratchDir: scratch)
        } catch { copyTestFail(2, "OPEN FAILED (old store copy): \(error)") }
        do { prodContainer = try cloudContainer(prod) } catch { copyTestFail(2, "OPEN FAILED (prod store copy): \(error)") }
        let oldCtx = ModelContext(oldContainer)
        let prodCtx = ModelContext(prodContainer)

        let oldBefore: MergeSnapshot, prodBefore: MergeSnapshot, plan: DevEraMerge.Plan
        do {
            oldBefore = try MergeSnapshot(oldCtx)
            prodBefore = try MergeSnapshot(prodCtx)
            plan = try DevEraMerge.plan(old: oldCtx, prod: prodCtx, macDeviceIDs: macDeviceIDs)
        } catch { copyTestFail(2, "plan failed: \(error)") }
        let c = plan.counts

        print("== merge dry run on copies (counts only; CloudKit off)")
        line("mac device ids given", macDeviceIDs.count)
        print("-- notes before")
        describe("OLD", oldBefore)
        describe("PROD", prodBefore)
        line("ids in both", c.inBoth)
        line("PROD only", c.prodOnly)
        line("OLD only, Mac-made", c.oldOnlyMacMade)
        line("OLD only, phone after S", c.oldOnlyPhoneAfterSplit)
        line("OLD only, trashed (skipped)", c.oldOnlyTrashed)
        line("OLD only, phone before S (skipped, limit \(DevEraMerge.maxPhoneNotesBeforeSplit))", c.oldOnlyPhoneBeforeSplit)
        for month in c.phoneBeforeSplitByMonth.keys.sorted() {
            line("  phone before S, \(month)", c.phoneBeforeSplitByMonth[month] ?? 0)
        }
        print("-- plan")
        line("notes to insert", plan.inserts.count)
        line("assets to insert", c.assetsToInsert)
        line("asset bytes to insert", c.assetBytesToInsert)
        line("enhancements OLD only (insert)", c.enhancementsInserted)
        line("enhancements OLD newer (OLD wins)", c.enhancementsOldNewer)
        line("enhancements PROD newer (PROD kept)", c.enhancementsProdNewer)
        line("enhancements tie (PROD kept)", c.enhancementsTie)
        for f in DevEraMerge.Field.allCases { line("fields copied, \(f.rawValue)", c.fieldCopies[f] ?? 0) }
        line("conflicts (edited on both sides after S, PROD kept)", plan.conflicts.count)
        line("diverged (no stamp, PROD kept)", plan.diverged.count)
        for f in DevEraMerge.Field.allCases {
            let n = plan.diverged.values.filter { $0.contains(f) }.count
            if n > 0 { line("  diverged, \(f.rawValue)", n) }
        }

        if let blocked = plan.blocked {
            print("RESULT: STOP (\(blocked.description))")
            exit(1)
        }

        let journal: DevEraMerge.UndoJournal
        do {
            journal = try DevEraMerge.apply(plan, from: oldCtx, into: prodCtx, firstImportDone: true)
        } catch { copyTestFail(2, "apply failed on the copy: \(error)") }

        let inserted = Set(journal.insertedNoteIDs)
        if simulateDrop {   // self-test only: proves a dropped note exits 1
            let victim = (try? prodCtx.fetch(FetchDescriptor<Memo>()))?.first { !inserted.contains($0.id) }
            if let victim { prodCtx.delete(victim); try? prodCtx.save() }
        }

        let after: MergeSnapshot
        do { after = try MergeSnapshot(ModelContext(prodContainer)) } catch { copyTestFail(2, "re-read failed: \(error)") }

        var trashings = 0, restores = 0
        for change in journal.fieldChanges where change.fields.contains(.trash) {
            if change.before.deletedAt == nil && change.after.deletedAt != nil { trashings += 1 }
            if change.before.deletedAt != nil && change.after.deletedAt == nil { restores += 1 }
        }

        print("-- after (PROD copy)")
        line("notes inserted", journal.insertedNoteIDs.count)
        line("enhancement rows inserted", journal.insertedEnhancementMemoIDs.count)
        line("enhancement rows updated", journal.enhancementChanges.count)
        line("notes with fields copied", journal.fieldChanges.count)
        line("  of which trashed", trashings)
        line("  of which restored", restores)
        line("saves", journal.saves)
        describe("PROD after", after)

        // MARK: checks
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            print("\(ok ? "PASS" : "FAIL") \(name)\(detail.isEmpty ? "" : " (\(detail))")")
            if !ok { failures += 1 }
        }
        print("-- checks")
        check("note rows after = before + inserted", after.memoRows == prodBefore.memoRows + inserted.count,
              "\(prodBefore.memoRows) + \(inserted.count) vs \(after.memoRows)")
        check("every planned insert was inserted", inserted.count == plan.inserts.count,
              "\(inserted.count) of \(plan.inserts.count)")
        check("no new duplicate id group", after.duplicateGroups == prodBefore.duplicateGroups,
              "\(prodBefore.duplicateGroups) -> \(after.duplicateGroups)")

        // Every live Mac-made OLD note is in PROD once (or as many times as it already was).
        var macLive = 0, macOnce = 0
        for (id, k) in oldBefore.keepers where k.deletedAt == nil {
            guard let device = k.recordingDeviceID, macDeviceIDs.contains(device) else { continue }
            macLive += 1
            let n = after.rowsPerID[id] ?? 0, was = prodBefore.rowsPerID[id] ?? 0
            if n == 1 || (was > 1 && n == was) { macOnce += 1 }
        }
        check("every live Mac-made OLD note present once in PROD", macOnce == macLive, "\(macOnce) of \(macLive)")

        // Inserted notes carry the same assets (kind + filename) as OLD, one row per key.
        var assetsMatch = 0, insertedAssetRows = 0
        for id in inserted {
            let want = oldBefore.assetKeysPerMemo[id] ?? []
            let got = after.assetKeysPerMemo[id] ?? []
            let rows = after.assetRowsPerMemo[id] ?? 0
            insertedAssetRows += rows
            if want == got && rows == got.count { assetsMatch += 1 }
        }
        check("inserted notes have OLD's asset count and kinds", assetsMatch == inserted.count,
              "\(assetsMatch) of \(inserted.count)")
        check("asset rows after = before + inserted assets", after.assetRows == prodBefore.assetRows + insertedAssetRows,
              "\(prodBefore.assetRows) + \(insertedAssetRows) vs \(after.assetRows)")

        // Enhancements: no memo gains a second row; every OLD-only / OLD-newer one is present
        // with OLD's enhancedAt.
        let extraRows = after.enhancementRowsPerMemo.filter { id, n in n > max(1, prodBefore.enhancementRowsPerMemo[id] ?? 0) }.count
        check("no memo gained a duplicate enhancement row", extraRows == 0, "\(extraRows) memos")
        let wanted = plan.enhancementInserts.map { ($0.memoID, $0.enhancedAt) } + plan.enhancementUpdates.map { ($0.memoID, $0.enhancedAt) }
        let present = wanted.filter { after.newestEnhancedAt[$0.0] == $0.1 }.count
        check("OLD-only and OLD-newer enhancements present with OLD's time", present == wanted.count,
              "\(present) of \(wanted.count)")
        check("enhancement rows after = before + inserted",
              after.enhancementRows == prodBefore.enhancementRows + journal.insertedEnhancementMemoIDs.count,
              "\(prodBefore.enhancementRows) + \(journal.insertedEnhancementMemoIDs.count) vs \(after.enhancementRows)")

        // Nothing dropped: no PROD count goes down, trashed notes included (only the planned
        // trash/restore copies move a note between live and trashed).
        check("live notes = before + inserted + restored - trashed",
              after.liveIDs == prodBefore.liveIDs + inserted.count + restores - trashings,
              "\(prodBefore.liveIDs) -> \(after.liveIDs)")
        check("trashed notes = before + trashed - restored",
              after.trashedIDs == prodBefore.trashedIDs + trashings - restores,
              "\(prodBefore.trashedIDs) -> \(after.trashedIDs)")
        let drops = [("note rows", prodBefore.memoRows, after.memoRows),
                     ("distinct note ids", prodBefore.distinctIDs, after.distinctIDs),
                     ("asset rows", prodBefore.assetRows, after.assetRows),
                     ("enhancement rows", prodBefore.enhancementRows, after.enhancementRows),
                     ("names records", prodBefore.namesRecords, after.namesRecords),
                     ("vocabulary records", prodBefore.vocabularyRecords, after.vocabularyRecords),
                     ("polish prompt records", prodBefore.promptRecords, after.promptRecords)]
            .filter { $0.2 < $0.1 }
        check("no PROD count went down", drops.isEmpty, drops.map(\.0).joined(separator: ", "))
        check("names, words, prompts untouched",
              after.namesRecords == prodBefore.namesRecords && after.vocabularyRecords == prodBefore.vocabularyRecords
                && after.promptRecords == prodBefore.promptRecords)

        try? FileManager.default.removeItem(at: scratch)
        if failures > 0 { print("RESULT: FAIL (\(failures) checks failed)"); exit(1) }
        if !plan.conflicts.isEmpty || !plan.diverged.isEmpty {
            print("RESULT: OK (review: \(plan.conflicts.count) conflicts, \(plan.diverged.count) diverged; PROD kept for both)")
        } else {
            print("RESULT: OK")
        }
        exit(0)
    }
}

// MARK: - Synthetic OLD + PROD pair (self-test only)

/// Writes `<dir>/old/memo_cloud.store` and `<dir>/prod/memo_cloud.store` with every merge class:
/// shared notes (unchanged, Mac-edited after S, edited on both sides, diverged title, Mac trash,
/// diverged rating), OLD-only (Mac-made with assets, phone after S, trashed, phone before S),
/// PROD-only, a PROD duplicate id group, and the four enhancement outcomes. Every text field holds
/// the token `SYNTHETIC-PRIVATE`, so the self-test can prove none of it reaches the output.
enum MergeSynthetic {
    static let macDevice = "synthetic-mac"
    static let phoneDevice = "synthetic-phone"
    static let token = "SYNTHETIC-PRIVATE"

    static func make(in dir: URL, phoneBeforeSplit: Int) {
        CopyTestGuard.check(dir.appendingPathComponent("x"), needsMarker: false)
        let fm = FileManager.default
        do {
            let oldDir = dir.appendingPathComponent("old", isDirectory: true)
            let prodDir = dir.appendingPathComponent("prod", isDirectory: true)
            try fm.createDirectory(at: oldDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: prodDir, withIntermediateDirectories: true)
            let old = ModelContext(try cloudContainer(oldDir.appendingPathComponent("memo_cloud.store")))
            let prod = ModelContext(try cloudContainer(prodDir.appendingPathComponent("memo_cloud.store")))
            let S = DevEraMerge.splitDate
            func day(_ n: Double) -> Date { S.addingTimeInterval(n * 86_400) }

            @discardableResult
            func memo(_ ctx: ModelContext, _ id: UUID, device: String, recorded: Date, title: String,
                      editedAt: Date? = nil, significance: Double = 0, deletedAt: Date? = nil) -> Memo {
                let m = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: recorded,
                             title: "\(token) \(title)", transcript: "\(token) words of \(title)",
                             transcriptStatus: .done, significance: significance, deletedAt: deletedAt,
                             createdAt: recorded, editedAt: editedAt, recordingDeviceID: device)
                if deletedAt != nil { m.trashSeenAt = deletedAt }
                ctx.insert(m)
                return m
            }
            func audio(_ ctx: ModelContext, _ id: UUID, bytes: Int = 64) {
                ctx.insert(MemoAsset(memoID: id, kind: MemoAsset.Kind.audio, filename: "memo_\(id.uuidString).m4a",
                                     blob: Data(repeating: 7, count: bytes)))
            }
            func enhancement(_ ctx: ModelContext, _ id: UUID, at: Date) {
                ctx.insert(MemoEnhancement(memoID: id, copyedit: "\(token) polish", enhancedByDeviceID: macDevice, enhancedAt: at))
            }
            func shared(_ title: String, significance: Double = 0) -> UUID {
                let id = UUID()
                memo(old, id, device: phoneDevice, recorded: day(-30), title: title, significance: significance)
                memo(prod, id, device: phoneDevice, recorded: day(-30), title: title, significance: significance)
                audio(old, id); audio(prod, id)
                return id
            }

            // Shared, unchanged since S; the first four carry the enhancement outcomes.
            let unchanged = (0..<5).map { shared("unchanged \($0)") }
            enhancement(old, unchanged[0], at: day(4)); enhancement(prod, unchanged[0], at: day(1))   // OLD newer
            enhancement(old, unchanged[1], at: day(1)); enhancement(prod, unchanged[1], at: day(4))   // PROD newer
            enhancement(old, unchanged[2], at: day(2)); enhancement(prod, unchanged[2], at: day(2))   // tie
            enhancement(old, unchanged[3], at: day(3))                                                 // OLD only

            // Mac edited after S, PROD untouched: title copied.
            let macEdited = UUID()
            memo(old, macEdited, device: phoneDevice, recorded: day(-20), title: "mac edited", editedAt: day(3))
            memo(prod, macEdited, device: phoneDevice, recorded: day(-20), title: "as at S")
            // Edited on both sides after S: conflict.
            let both = UUID()
            memo(old, both, device: phoneDevice, recorded: day(-20), title: "mac side", editedAt: day(2))
            memo(prod, both, device: phoneDevice, recorded: day(-20), title: "phone side", editedAt: day(5))
            // Different title, no stamp: diverged.
            let unstamped = UUID()
            memo(old, unstamped, device: phoneDevice, recorded: day(-20), title: "mac setTitle")
            memo(prod, unstamped, device: phoneDevice, recorded: day(-20), title: "as at S")
            // Mac trashed after S, PROD alive and untouched: trash copied.
            let trashed = UUID()
            memo(old, trashed, device: phoneDevice, recorded: day(-20), title: "trashed on mac", deletedAt: day(2))
            memo(prod, trashed, device: phoneDevice, recorded: day(-20), title: "trashed on mac")
            // Rating differs, PROD rated: diverged rating.
            let rated = UUID()
            memo(old, rated, device: phoneDevice, recorded: day(-20), title: "rated", significance: 0.5)
            memo(prod, rated, device: phoneDevice, recorded: day(-20), title: "rated", significance: 0.8)

            // OLD only.
            for i in 0..<2 {
                let id = UUID()
                memo(old, id, device: macDevice, recorded: day(5 + Double(i)), title: "mac made \(i)")
                audio(old, id, bytes: 100)
                old.insert(MemoAsset(memoID: id, kind: MemoAsset.Kind.photo, filename: "photo_\(id.uuidString)_001.jpg",
                                     blob: Data(repeating: 9, count: 10)))
                if i == 1 { enhancement(old, id, at: day(6)) }
            }
            let phoneAfter = UUID()
            memo(old, phoneAfter, device: phoneDevice, recorded: day(4), title: "phone after S")
            audio(old, phoneAfter)
            memo(old, UUID(), device: phoneDevice, recorded: day(6), title: "trashed old only", deletedAt: day(7))
            for i in 0..<phoneBeforeSplit {
                memo(old, UUID(), device: phoneDevice, recorded: day(-40 - Double(i)), title: "phone before S \(i)")
            }

            // PROD only, plus a duplicate id group PROD already had.
            for i in 0..<3 { memo(prod, UUID(), device: phoneDevice, recorded: day(10 + Double(i)), title: "prod only \(i)") }
            let dup = UUID()
            memo(prod, dup, device: phoneDevice, recorded: day(8), title: "dup a")
            memo(prod, dup, device: phoneDevice, recorded: day(8), title: "dup b")
            // One trashed PROD note, so "trashed notes" starts non-zero.
            memo(prod, UUID(), device: phoneDevice, recorded: day(9), title: "prod trashed", deletedAt: day(9))

            try old.save()
            try prod.save()
            print("synthetic merge pair written (old + prod)")
        } catch {
            copyTestFail(2, "synthetic merge pair failed: \(error)")
        }
    }
}
