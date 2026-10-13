import Foundation
import SwiftData

/// Q398 (D203, `plan/release/ICLOUD_MERGE.md` A2): the one-time merge of the August Mac's
/// Development-era `memo_cloud.store` into the live Production store, matched by `Memo.id` /
/// `memoID`. Ordinary SwiftData inserts and updates on the Production context, so they sync like
/// any new note. Never touches `NamesRecord` / `VocabularyRecord` / `PolishPromptsRecord` (the
/// normal reconcile merges those from the Mac's local files) and never CloudKit directly.
///
/// Pure + host-less like `MemoCloudReconciler.pass`: every entry point takes its contexts, so the
/// tests run it on synthetic in-memory stores. `plan` reads only; `apply` writes Production in
/// batches of `batchSize` notes per save and refuses to run before the Production store's first
/// CloudKit import is done (`CloudFirstImport`, Q397). `apply` returns an `UndoJournal`; `unmerge`
/// replays it backwards.
///
/// The rules are ICLOUD_MERGE.md "Merge rules (A2)" plus its Q398 section: most Aug Mac writes do
/// not bump `editedAt`, so an un-stamped difference is listed ("diverged"), never guessed.
enum DevEraMerge {

    static let batchSize = 25
    /// More old-only phone notes from before S than this = Production probably lacks the phone's
    /// history (ICLOUD_MERGE risk 2): stop and re-plan.
    static let maxPhoneNotesBeforeSplit = 20

    /// S = 2026-09-25 00:00 Europe/Lisbon (WEST, so 2026-09-24 23:00 UTC).
    static let splitDate: Date = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return cal.date(from: DateComponents(year: 2026, month: 9, day: 25))!
    }()

    /// The Mac cloud store's model list (`MemoCloudStore.schema`, which lives in `App/`).
    static let storeSchema = Schema([Memo.self, MemoAsset.self, MemoEnhancement.self,
                                     NamesRecord.self, VocabularyRecord.self,
                                     PolishPromptsRecord.self, MemoEditHead.self])

    static let storeFileName = "memo_cloud.store"
    static let reportFileName = "merge-report.txt"
    static let undoFileName = "merge-undo.json"

    enum MergeError: Error, Equatable, CustomStringConvertible {
        case firstImportNotDone
        case tooManyPhoneNotesBeforeSplit(count: Int, limit: Int)
        case oldStoreMissing(String)

        var description: String {
            switch self {
            case .firstImportNotDone:
                return "DevEraMerge refused: the Production store has not finished its first CloudKit import yet."
            case .tooManyPhoneNotesBeforeSplit(let count, let limit):
                return "DevEraMerge stopped: \(count) phone notes from before 2026-09-25 exist only in the old store "
                    + "(limit \(limit)). Production probably lacks the phone's history. Re-plan (ICLOUD_MERGE risk 2)."
            case .oldStoreMissing(let path):
                return "DevEraMerge: no old store at \(path)."
            }
        }
    }

    // MARK: - Value types

    /// The `Memo` fields the merge may copy onto a shared Production row.
    enum Field: String, Codable, CaseIterable, Comparable {
        case title, body, tags, rating, trash, keptAt, editedAt
        static func < (a: Field, b: Field) -> Bool { a.rawValue < b.rawValue }
    }

    /// A snapshot of the copyable fields of one row (also the undo journal's "before").
    struct MemoFields: Codable, Equatable {
        var title: String?
        var transcript: String?
        var transcriptUserEdited: Bool
        var annotationText: String?
        var tags: [String]
        var significance: Double
        var deletedAt: Date?
        var trashSeenAt: Date?
        var keptAt: Date?
        var editedAt: Date?

        init(_ m: Memo) {
            title = m.title; transcript = m.transcript; transcriptUserEdited = m.transcriptUserEdited
            annotationText = m.annotationText; tags = m.tags; significance = m.significance
            deletedAt = m.deletedAt; trashSeenAt = m.trashSeenAt; keptAt = m.keptAt; editedAt = m.editedAt
        }

        func write(_ fields: [Field], to m: Memo) {
            for f in fields {
                switch f {
                case .title: m.title = title
                case .body:
                    m.transcript = transcript; m.transcriptUserEdited = transcriptUserEdited
                    m.annotationText = annotationText
                case .tags: m.tags = tags
                case .rating: m.significance = significance
                case .trash: m.deletedAt = deletedAt; m.trashSeenAt = trashSeenAt
                case .keptAt: m.keptAt = keptAt
                case .editedAt: m.editedAt = editedAt
                }
            }
        }

        func equals(_ other: MemoFields, on fields: [Field]) -> Bool {
            fields.allSatisfy { f in
                switch f {
                case .title: return title == other.title
                case .body: return transcript == other.transcript
                    && transcriptUserEdited == other.transcriptUserEdited && annotationText == other.annotationText
                case .tags: return tags == other.tags
                case .rating: return significance == other.significance
                case .trash: return deletedAt == other.deletedAt && trashSeenAt == other.trashSeenAt
                case .keptAt: return keptAt == other.keptAt
                case .editedAt: return editedAt == other.editedAt
                }
            }
        }
    }

    struct FieldCopy: Codable, Equatable {
        var memoID: UUID
        var fields: [Field]
        var values: MemoFields
    }

    struct EnhancementValues: Codable, Equatable {
        var memoID: UUID
        var copyedit: String
        var title: String
        var summary: String
        var enhancedByDeviceID: String
        var enhancedAt: Date
        var processedAt: Date?

        init(_ e: MemoEnhancement) {
            memoID = e.memoID; copyedit = e.copyedit; title = e.title; summary = e.summary
            enhancedByDeviceID = e.enhancedByDeviceID; enhancedAt = e.enhancedAt; processedAt = e.processedAt
        }

        func write(to e: MemoEnhancement) {
            e.copyedit = copyedit; e.title = title; e.summary = summary
            e.enhancedByDeviceID = enhancedByDeviceID; e.enhancedAt = enhancedAt; e.processedAt = processedAt
        }

        func makeRow() -> MemoEnhancement {
            MemoEnhancement(memoID: memoID, copyedit: copyedit, title: title, summary: summary,
                            enhancedByDeviceID: enhancedByDeviceID, enhancedAt: enhancedAt,
                            processedAt: processedAt)
        }
    }

    struct Counts: Equatable {
        var oldTotal = 0, prodTotal = 0
        var inBoth = 0, prodOnly = 0
        var oldOnlyMacMade = 0, oldOnlyPhoneAfterSplit = 0, oldOnlyTrashed = 0, oldOnlyPhoneBeforeSplit = 0
        /// "yyyy-MM" (Lisbon) → count, for the old-only phone notes from before S.
        var phoneBeforeSplitByMonth: [String: Int] = [:]
        var oldDuplicateGroups = 0, prodDuplicateGroups = 0
        var enhancementsInserted = 0, enhancementsOldNewer = 0, enhancementsProdNewer = 0, enhancementsTie = 0
        var fieldCopies: [Field: Int] = [:]
        var assetsToInsert = 0, assetBytesToInsert = 0
    }

    struct Plan {
        var counts = Counts()
        /// Old-only note ids to insert (Mac-made, then phone after S), in a stable order.
        var inserts: [UUID] = []
        var fieldCopies: [FieldCopy] = []
        var enhancementInserts: [EnhancementValues] = []
        var enhancementUpdates: [EnhancementValues] = []
        /// Edited on both sides after S, with a difference: Production kept.
        var conflicts: [UUID] = []
        /// A difference with no stamp saying which side made it: Production kept, listed.
        var diverged: [UUID: [Field]] = [:]
        /// Non-nil = `apply` refuses.
        var blocked: MergeError?
    }

    /// Everything `apply` changed, with the "before" values `unmerge` needs.
    struct UndoJournal: Codable, Equatable {
        struct FieldChange: Codable, Equatable {
            var memoID: UUID
            var fields: [Field]
            var before: MemoFields
            var after: MemoFields
        }
        struct EnhancementChange: Codable, Equatable {
            var before: EnhancementValues
            var after: EnhancementValues
        }
        var mergedAt: Date
        var insertedNoteIDs: [UUID] = []
        var insertedEnhancementMemoIDs: [UUID] = []
        var fieldChanges: [FieldChange] = []
        var enhancementChanges: [EnhancementChange] = []
        var conflicts: [UUID] = []
        var saves = 0
    }

    struct UnmergeOutcome: Equatable {
        var notesTrashed = 0
        var enhancementsRemoved = 0
        var enhancementsRestored = 0
        var fieldsRestored = 0
        /// Rows edited again since the merge: left alone, ids listed.
        var skippedChangedSinceMerge: [UUID] = []
    }

    // MARK: - Guards

    /// The Q397 first-import stamp for the live Production store.
    static func firstImportDone(prodStoreURL: URL, stampURL: URL) -> Bool {
        CloudFirstImport.isDone(storeURL: prodStoreURL, stampURL: stampURL)
    }

    /// Copy the old store family out of `sourceDir` (e.g. `merge-from-dev/`) into `scratchDir` and
    /// open the COPY with CloudKit off. The source files are never opened, so they stay byte-for-byte
    /// as they were (the opened copy may migrate in place).
    static func openOldStoreCopy(sourceDir: URL, scratchDir: URL) throws -> ModelContainer {
        let fm = FileManager.default
        let source = sourceDir.appendingPathComponent(storeFileName)
        guard fm.fileExists(atPath: source.path) else { throw MergeError.oldStoreMissing(source.path) }
        try fm.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        for name in [storeFileName, storeFileName + "-wal", storeFileName + "-shm", ".memo_cloud_SUPPORT"] {
            let from = sourceDir.appendingPathComponent(name)
            let to = scratchDir.appendingPathComponent(name)
            guard fm.fileExists(atPath: from.path) else { continue }
            if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
            try fm.copyItem(at: from, to: to)
        }
        let config = ModelConfiguration("DevEraOld", schema: storeSchema,
                                        url: scratchDir.appendingPathComponent(storeFileName),
                                        cloudKitDatabase: .none)
        return try ModelContainer(for: storeSchema, configurations: config)
    }

    // MARK: - Plan (reads only)

    static func plan(old: ModelContext, prod: ModelContext, splitDate: Date = splitDate,
                     macDeviceIDs: Set<String>) throws -> Plan {
        var plan = Plan()
        let oldMemos = try old.fetch(FetchDescriptor<Memo>())
        let prodMemos = try prod.fetch(FetchDescriptor<Memo>())
        let oldGroups = Dictionary(grouping: oldMemos, by: \.id)
        let prodGroups = Dictionary(grouping: prodMemos, by: \.id)
        plan.counts.oldTotal = oldMemos.count
        plan.counts.prodTotal = prodMemos.count
        plan.counts.oldDuplicateGroups = oldGroups.values.filter { $0.count > 1 }.count
        plan.counts.prodDuplicateGroups = prodGroups.values.filter { $0.count > 1 }.count
        plan.counts.prodOnly = prodGroups.keys.filter { oldGroups[$0] == nil }.count

        var macInserts: [(Date, UUID)] = []
        var phoneInserts: [(Date, UUID)] = []
        for (id, group) in oldGroups {
            guard let oldK = MemoDuplicates.keeper(of: group) else { continue }
            if let prodRows = prodGroups[id], let prodK = MemoDuplicates.keeper(of: prodRows) {
                plan.counts.inBoth += 1
                compareShared(old: oldK, prod: prodK, split: splitDate, into: &plan)
                continue
            }
            if oldK.deletedAt != nil {
                plan.counts.oldOnlyTrashed += 1
            } else if let device = oldK.recordingDeviceID, macDeviceIDs.contains(device) {
                plan.counts.oldOnlyMacMade += 1
                macInserts.append((oldK.addedAt, id))
            } else if oldK.addedAt >= splitDate {
                plan.counts.oldOnlyPhoneAfterSplit += 1
                phoneInserts.append((oldK.addedAt, id))
            } else {
                plan.counts.oldOnlyPhoneBeforeSplit += 1
                plan.counts.phoneBeforeSplitByMonth[monthKey(oldK.addedAt), default: 0] += 1
            }
        }
        func ordered(_ list: [(Date, UUID)]) -> [UUID] {
            list.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.uuidString < $1.1.uuidString }.map(\.1)
        }
        plan.inserts = ordered(macInserts) + ordered(phoneInserts)
        plan.conflicts.sort { $0.uuidString < $1.uuidString }
        plan.fieldCopies.sort { $0.memoID.uuidString < $1.memoID.uuidString }

        let insertSet = Set(plan.inserts)
        let oldAssets = try old.fetch(FetchDescriptor<MemoAsset>())
        for asset in dedupedAssets(oldAssets.filter { insertSet.contains($0.memoID) }) {
            plan.counts.assetsToInsert += 1
            plan.counts.assetBytesToInsert += asset.byteCount
        }

        // Enhancements, per memoID of a note in the merged result.
        let merged = Set(prodGroups.keys).union(insertSet)
        let oldEnh = Dictionary(grouping: try old.fetch(FetchDescriptor<MemoEnhancement>()), by: \.memoID)
        let prodEnh = Dictionary(grouping: try prod.fetch(FetchDescriptor<MemoEnhancement>()), by: \.memoID)
        for memoID in oldEnh.keys.sorted(by: { $0.uuidString < $1.uuidString }) where merged.contains(memoID) {
            guard let o = newest(oldEnh[memoID] ?? []) else { continue }
            guard let p = newest(prodEnh[memoID] ?? []) else {
                plan.enhancementInserts.append(EnhancementValues(o))
                plan.counts.enhancementsInserted += 1
                continue
            }
            var next = EnhancementValues(p)
            if o.enhancedAt > p.enhancedAt {
                next = EnhancementValues(o)
                plan.counts.enhancementsOldNewer += 1
            } else if o.enhancedAt < p.enhancedAt {
                plan.counts.enhancementsProdNewer += 1
            } else {
                plan.counts.enhancementsTie += 1
            }
            next.processedAt = laterNonNil(o.processedAt, p.processedAt)
            if next != EnhancementValues(p) { plan.enhancementUpdates.append(next) }
        }

        if plan.counts.oldOnlyPhoneBeforeSplit > maxPhoneNotesBeforeSplit {
            plan.blocked = .tooManyPhoneNotesBeforeSplit(count: plan.counts.oldOnlyPhoneBeforeSplit,
                                                         limit: maxPhoneNotesBeforeSplit)
        }
        return plan
    }

    /// The per-note rules for an id on both sides (ICLOUD_MERGE.md, Q398 section).
    private static func compareShared(old o: Memo, prod p: Memo, split: Date, into plan: inout Plan) {
        let past = Date.distantPast
        let macEdited = (o.editedAt ?? past) > split
        let prodEdited = (p.editedAt ?? past) > split
        let of = MemoFields(o), pf = MemoFields(p)

        var differing: [Field] = []
        if of.title != pf.title { differing.append(.title) }
        if !of.equals(pf, on: [.body]) { differing.append(.body) }
        if of.tags != pf.tags { differing.append(.tags) }
        if of.significance != pf.significance { differing.append(.rating) }

        // A rating carries no stamp on either side: copied only onto an unrated Production row,
        // and never the reason for a conflict.
        let content = differing.filter { $0 != .rating }
        let ratingDiffers = differing.contains(.rating)
        var copy: [Field] = []
        var diverged: [Field] = []
        if macEdited && prodEdited {
            if !content.isEmpty { plan.conflicts.append(o.id) }
            if ratingDiffers { diverged.append(.rating) }
        } else if macEdited {
            copy.append(contentsOf: content)
            if !content.isEmpty { copy.append(.editedAt) }
            if ratingDiffers { if pf.significance == 0 { copy.append(.rating) } else { diverged.append(.rating) } }
        } else {
            diverged.append(contentsOf: differing)
        }

        // Trash carries its own time.
        if let d = o.deletedAt, d > split, p.deletedAt == nil,
           p.lastEditedAt < d, (p.keptAt ?? past) < d {
            copy.append(.trash)                                  // Mac trashed it after S
        } else if o.deletedAt == nil, let pd = p.deletedAt, pd <= split,
                  let k = o.keptAt, k > split, k > pd {
            copy.append(.trash)                                  // Mac restored it after S
        } else if (o.deletedAt == nil) != (p.deletedAt == nil) {
            diverged.append(.trash)
        }

        // `keptAt` only delays fading: the later one wins.
        if let k = o.keptAt, k > split, k > (p.keptAt ?? past) { copy.append(.keptAt) }

        if !copy.isEmpty {
            var values = of
            if copy.contains(.trash) && o.deletedAt == nil { values.trashSeenAt = nil }
            let fields = Array(Set(copy)).sorted()
            plan.fieldCopies.append(FieldCopy(memoID: o.id, fields: fields, values: values))
            for f in fields { plan.counts.fieldCopies[f, default: 0] += 1 }
        }
        if !diverged.isEmpty { plan.diverged[o.id] = Array(Set(diverged)).sorted() }
    }

    // MARK: - Apply (writes Production)

    @discardableResult
    static func apply(_ plan: Plan, from old: ModelContext, into prod: ModelContext,
                      firstImportDone: Bool, now: Date = Date()) throws -> UndoJournal {
        guard firstImportDone else { throw MergeError.firstImportNotDone }
        if let blocked = plan.blocked { throw blocked }
        var journal = UndoJournal(mergedAt: now)
        journal.conflicts = plan.conflicts

        // Re-check against the live store: an id that reached Production since the plan is skipped.
        let prodIDs = Set(try prod.fetch(FetchDescriptor<Memo>()).map(\.id))
        let inserts = plan.inserts.filter { !prodIDs.contains($0) }
        let enhInsertsByMemo = Dictionary(grouping: plan.enhancementInserts, by: \.memoID)
        let insertSet = Set(inserts)

        for batch in chunks(inserts) {
            for id in batch {
                guard let keeper = MemoDuplicates.keeper(of: try rows(id, in: old)) else { continue }
                prod.insert(clone(keeper))
                let assets = try old.fetch(FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == id }))
                for a in dedupedAssets(assets) {
                    prod.insert(MemoAsset(memoID: a.memoID, kind: a.kind, filename: a.filename,
                                          blob: a.blob, createdAt: a.createdAt))
                }
                for e in enhInsertsByMemo[id] ?? [] {
                    prod.insert(e.makeRow())
                    journal.insertedEnhancementMemoIDs.append(id)
                }
                journal.insertedNoteIDs.append(id)
            }
            try save(prod, &journal)
        }

        for batch in chunks(plan.fieldCopies) {
            for copy in batch {
                guard let keeper = MemoDuplicates.keeper(of: try rows(copy.memoID, in: prod)) else { continue }
                let before = MemoFields(keeper)
                copy.values.write(copy.fields, to: keeper)
                journal.fieldChanges.append(.init(memoID: copy.memoID, fields: copy.fields,
                                                  before: before, after: MemoFields(keeper)))
            }
            try save(prod, &journal)
        }

        // Enhancement rows for notes that were already in Production (inserted notes got theirs above).
        let sharedEnhInserts = plan.enhancementInserts.filter { !insertSet.contains($0.memoID) }
        for batch in chunks(sharedEnhInserts) {
            for e in batch {
                guard try enhancementRows(e.memoID, in: prod).isEmpty else { continue }
                prod.insert(e.makeRow())
                journal.insertedEnhancementMemoIDs.append(e.memoID)
            }
            try save(prod, &journal)
        }
        for batch in chunks(plan.enhancementUpdates) {
            for e in batch {
                guard let row = newest(try enhancementRows(e.memoID, in: prod)) else { continue }
                let before = EnhancementValues(row)
                e.write(to: row)
                journal.enhancementChanges.append(.init(before: before, after: e))
            }
            try save(prod, &journal)
        }
        return journal
    }

    // MARK: - Unmerge

    /// Undo `apply`: trash the inserted notes (soft delete, so it syncs and stays restorable),
    /// remove the enhancement rows it inserted, restore the fields and enhancements it changed.
    /// A row edited again since the merge is left alone and listed.
    @discardableResult
    static func unmerge(_ journal: UndoJournal, in prod: ModelContext, now: Date = Date()) throws -> UnmergeOutcome {
        var out = UnmergeOutcome()
        var scratch = UndoJournal(mergedAt: now)
        for batch in chunks(journal.insertedNoteIDs) {
            for id in batch {
                for m in try rows(id, in: prod) where m.deletedAt == nil {
                    m.deletedAt = now; m.trashSeenAt = now
                    out.notesTrashed += 1
                }
            }
            try save(prod, &scratch)
        }
        let insertedEnh = Set(journal.insertedEnhancementMemoIDs)
        for batch in chunks(Array(insertedEnh).sorted { $0.uuidString < $1.uuidString }) {
            for id in batch {
                for e in try enhancementRows(id, in: prod) { prod.delete(e); out.enhancementsRemoved += 1 }
            }
            try save(prod, &scratch)
        }
        for batch in chunks(journal.enhancementChanges) {
            for change in batch {
                guard let row = newest(try enhancementRows(change.after.memoID, in: prod)) else { continue }
                guard EnhancementValues(row) == change.after else {
                    out.skippedChangedSinceMerge.append(change.after.memoID); continue
                }
                change.before.write(to: row)
                out.enhancementsRestored += 1
            }
            try save(prod, &scratch)
        }
        for batch in chunks(journal.fieldChanges) {
            for change in batch {
                guard let keeper = MemoDuplicates.keeper(of: try rows(change.memoID, in: prod)) else { continue }
                guard MemoFields(keeper).equals(change.after, on: change.fields) else {
                    out.skippedChangedSinceMerge.append(change.memoID); continue
                }
                change.before.write(change.fields, to: keeper)
                out.fieldsRestored += 1
            }
            try save(prod, &scratch)
        }
        return out
    }

    // MARK: - Report + journal files

    /// `merge-report.txt`: counts and ids only, never a title or any text.
    static func reportText(plan: Plan, journal: UndoJournal) -> String {
        let c = plan.counts
        var lines = ["Skrift DevEraMerge report", "merged at: \(ISO8601DateFormatter().string(from: journal.mergedAt))",
                     "split date S: \(ISO8601DateFormatter().string(from: splitDate))", "",
                     "notes before: old \(c.oldTotal), prod \(c.prodTotal), in both \(c.inBoth), prod only \(c.prodOnly)",
                     "old only: mac-made \(c.oldOnlyMacMade), phone after S \(c.oldOnlyPhoneAfterSplit), "
                        + "trashed (skipped) \(c.oldOnlyTrashed), phone before S (skipped) \(c.oldOnlyPhoneBeforeSplit)",
                     "duplicate id groups: old \(c.oldDuplicateGroups), prod \(c.prodDuplicateGroups)",
                     "assets inserted: \(c.assetsToInsert) (\(c.assetBytesToInsert) bytes)",
                     "enhancements: inserted \(c.enhancementsInserted), old newer \(c.enhancementsOldNewer), "
                        + "prod newer \(c.enhancementsProdNewer), tie \(c.enhancementsTie)",
                     "fields copied: " + Field.allCases.map { "\($0.rawValue) \(c.fieldCopies[$0] ?? 0)" }.joined(separator: ", "),
                     "saves: \(journal.saves)"]
        if !c.phoneBeforeSplitByMonth.isEmpty {
            lines.append("phone before S by month: " + c.phoneBeforeSplitByMonth.keys.sorted()
                .map { "\($0) \(c.phoneBeforeSplitByMonth[$0] ?? 0)" }.joined(separator: ", "))
        }
        func section(_ title: String, _ ids: [UUID]) {
            lines.append(""); lines.append("\(title) (\(ids.count)):")
            lines.append(contentsOf: ids.map(\.uuidString))
        }
        section("inserted note ids", journal.insertedNoteIDs)
        section("inserted enhancement memo ids", journal.insertedEnhancementMemoIDs)
        section("changed enhancement memo ids", journal.enhancementChanges.map(\.after.memoID))
        section("field-copied note ids", journal.fieldChanges.map(\.memoID))
        section("conflict ids (edited on both sides after S, Production kept)", journal.conflicts)
        lines.append(""); lines.append("diverged, Production kept (\(plan.diverged.count)):")
        for id in plan.diverged.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            lines.append("\(id.uuidString) " + (plan.diverged[id] ?? []).map(\.rawValue).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Write `merge-report.txt` and `merge-undo.json` into `dir`.
    static func writeReport(plan: Plan, journal: UndoJournal, to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(reportText(plan: plan, journal: journal).utf8)
            .write(to: dir.appendingPathComponent(reportFileName), options: .atomic)
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        try enc.encode(journal).write(to: dir.appendingPathComponent(undoFileName), options: .atomic)
    }

    static func readJournal(from dir: URL) throws -> UndoJournal {
        try JSONDecoder().decode(UndoJournal.self, from: Data(contentsOf: dir.appendingPathComponent(undoFileName)))
    }

    // MARK: - Helpers

    /// A full copy of every stored `Memo` property (a fresh row in the target context).
    static func clone(_ m: Memo) -> Memo {
        let c = Memo(id: m.id, audioFilename: m.audioFilename, duration: m.duration, recordedAt: m.recordedAt,
                     tags: m.tags, syncStatus: m.syncStatus, title: m.title, transcript: m.transcript,
                     transcriptStatus: m.transcriptStatus, transcriptConfidence: m.transcriptConfidence,
                     transcriptUserEdited: m.transcriptUserEdited,
                     transcriptMarkersInjected: m.transcriptMarkersInjected, significance: m.significance,
                     deletedAt: m.deletedAt, createdAt: m.createdAt, editedAt: m.editedAt,
                     metadataData: m.metadataData, sharedContentData: m.sharedContentData,
                     annotationText: m.annotationText, nameResolutionsData: m.nameResolutionsData,
                     recordingDeviceID: m.recordingDeviceID)
        c.destinationRaw = m.destinationRaw
        c.includeAudioInExport = m.includeAudioInExport
        c.trashSeenAt = m.trashSeenAt
        c.remindAt = m.remindAt
        c.locked = m.locked
        c.keptAt = m.keptAt
        c.pendingDiarizationTarget = m.pendingDiarizationTarget
        c.editVectorData = m.editVectorData
        c.editStampHash = m.editStampHash
        c.polishStampHash = m.polishStampHash
        c.replacedAt = m.replacedAt
        return c
    }

    private static func rows(_ id: UUID, in ctx: ModelContext) throws -> [Memo] {
        try ctx.fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id }))
    }

    private static func enhancementRows(_ id: UUID, in ctx: ModelContext) throws -> [MemoEnhancement] {
        try ctx.fetch(FetchDescriptor<MemoEnhancement>(predicate: #Predicate { $0.memoID == id }))
    }

    private static func newest(_ rows: [MemoEnhancement]) -> MemoEnhancement? {
        rows.max { $0.enhancedAt < $1.enhancedAt }
    }

    /// One asset per (kind, filename); the largest wins (a stale shorter copy loses).
    private static func dedupedAssets(_ assets: [MemoAsset]) -> [MemoAsset] {
        var best: [String: MemoAsset] = [:]
        for a in assets {
            let key = "\(a.memoID.uuidString)|\(a.kind)|\(a.filename)"
            if let cur = best[key], cur.byteCount >= a.byteCount { continue }
            best[key] = a
        }
        return best.keys.sorted().compactMap { best[$0] }
    }

    private static func laterNonNil(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case let (a?, b?): return max(a, b)
        default: return a ?? b
        }
    }

    private static func monthKey(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        let c = cal.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    private static func chunks<T>(_ items: [T]) -> [[T]] {
        stride(from: 0, to: items.count, by: batchSize).map { Array(items[$0..<min($0 + batchSize, items.count)]) }
    }

    private static func save(_ ctx: ModelContext, _ journal: inout UndoJournal) throws {
        guard ctx.hasChanges else { return }
        try ctx.save()
        journal.saves += 1
    }
}
