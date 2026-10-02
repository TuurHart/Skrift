import Foundation

/// The Mac sidebar's adapter onto the shared list rules (`NotesListModel`, Q104 / C115 /
/// D148): which chip each Mac row kind belongs to and which date the range reads, then the
/// SAME three rules the phone applies — filter sheet, list rows (fading hits only while
/// searching), Related rows. Lives in Pipeline/ (no SwiftUI, no `LockGate`) so the host-less
/// `SkriftDesktopTests` bundle drives it; `AppModel` and `SidebarView` call it.
struct MacListFilter {
    var chip: QueueFilter = .all
    var query: String = ""
    var from: Date?
    var to: Date?
    /// Q105: which date the range reads — the phone's Recorded / Added picker (C115).
    var dateField: MemoDateField = .recorded
    /// `Memo.addedAt` per note id. A `PipelineFile` carries only the recorded date
    /// (`uploadedAt`), so the day a note entered Skrift comes from its `Memo` (a synced memo's
    /// pipeline row shares its UUID). A row with no memo falls back to its recorded date.
    var addedAtByID: [String: Date] = [:]
    /// Per-session unlock (`LockGate.shared.isUnlocked`) — injected so tests need no LocalAuthentication.
    var isUnlocked: (String) -> Bool = { _ in false }

    /// A row whose four pipeline steps are done.
    static func isComplete(_ f: PipelineFile) -> Bool {
        let s = f.steps
        return s.transcribe == .done && s.sanitise == .done && s.enhance == .done && s.export == .done
    }

    // MARK: - chip membership per row kind

    /// A pipeline row's chip. No `PipelineFile` is unrated by definition (the gate rates on
    /// entry), so Not rated holds only memo rows.
    func inChip(_ f: PipelineFile) -> Bool {
        switch chip {
        case .all:       return true
        case .needsWork: return !Self.isComplete(f)
        case .done:      return Self.isComplete(f)
        case .notRated:  return false
        }
    }

    /// A memo row's chip. Unrated rows (quiet, locked-quiet, fading) sit under All and Not
    /// rated. A rated memo row is STRANDED (no pipeline row): it rides every chip except Not
    /// rated, because it cannot answer "needs work" or "done" and being unfindable is the
    /// bug it exists to prevent.
    func inChip(_ m: Memo) -> Bool {
        if NoteConsent.isRated(m) { return chip != .notRated }
        return chip == .all || chip == .notRated
    }

    // MARK: - dates (Q105, C70/C115)

    /// The day a pipeline row entered Skrift (`Memo.addedAt` via its shared id).
    func addedAt(_ f: PipelineFile) -> Date { addedAtByID[f.id] ?? f.uploadedAt }

    /// `addedAt` per note id, from the one-row-per-id memo list the sidebar shows.
    static func addedDates(memos: [Memo]) -> [String: Date] {
        Dictionary(memos.map { ($0.id.uuidString, $0.addedAt) }, uniquingKeysWith: { a, _ in a })
    }

    /// The date the range filter reads for a pipeline row under the picked field.
    func filterDate(_ f: PipelineFile) -> Date {
        NotesListModel.filterDate(field: dateField, recordedAt: f.uploadedAt, addedAt: addedAt(f))
    }

    /// The date the range filter reads for a memo row under the picked field.
    func filterDate(_ m: Memo) -> Date {
        NotesListModel.filterDate(field: dateField, recordedAt: m.recordedAt, addedAt: m.addedAt)
    }

    // MARK: - the shared rules

    /// Chip + date range for a pipeline row (the Recorded / Added field the strip picked).
    func passesFilter(_ f: PipelineFile) -> Bool {
        NotesListModel.passesFilter(inChip: inChip(f), date: filterDate(f), from: from, to: to)
    }

    /// Chip + date range for a memo row (the Recorded / Added field the strip picked).
    func passesFilter(_ m: Memo) -> Bool {
        NotesListModel.passesFilter(inChip: inChip(m), date: filterDate(m), from: from, to: to)
    }

    // MARK: - order (Q105)

    /// What the list sorts on. Newest = the note's ADDED date (C70 "Recently added", the
    /// phone's `.added`); Oldest = the recorded date (the phone's `.oldest`).
    func sortDate(_ f: PipelineFile, sort: SidebarSort) -> Date {
        sort == .newest ? addedAt(f) : f.uploadedAt
    }

    func sort(_ files: [PipelineFile], by sort: SidebarSort, title: (PipelineFile) -> String) -> [PipelineFile] {
        files.sorted { a, b in
            switch sort {
            case .newest: return sortDate(a, sort: sort) > sortDate(b, sort: sort)
            case .oldest: return sortDate(a, sort: sort) < sortDate(b, sort: sort)
            case .title:  return title(a).localizedCaseInsensitiveCompare(title(b)) == .orderedAscending
            }
        }
    }

    /// The two row kinds interleaved by the active sort.
    func sort(_ entries: [SidebarEntry], by sort: SidebarSort, title: (SidebarEntry) -> String) -> [SidebarEntry] {
        func key(_ e: SidebarEntry) -> Date {
            switch e {
            case .file(let f): return sortDate(f, sort: sort)
            case .memo(let m): return sort == .newest ? m.addedAt : m.recordedAt
            }
        }
        switch sort {
        case .newest: return entries.sorted { key($0) > key($1) }
        case .oldest: return entries.sorted { key($0) < key($1) }
        case .title:  return entries.sorted { title($0).localizedCaseInsensitiveCompare(title($1)) == .orderedAscending }
        }
    }

    func matchesSearch(_ f: PipelineFile) -> Bool {
        // Q101 (C91/C161): a locked, not-yet-unlocked note matches on its set title only.
        f.matchesNoteSearch(query: query, unlockedThisSession: isUnlocked(f.id))
    }

    func matchesSearch(_ m: Memo) -> Bool {
        WayOutRules.matchesSearch(m, query: query, unlockedThisSession: isUnlocked(m.id.uuidString))
    }

    /// The pipeline rows as filtered (unsorted; `AppModel.visible` sorts).
    func fileRows(_ files: [PipelineFile]) -> [PipelineFile] {
        files.filter { matchesSearch($0) && passesFilter($0) }
    }

    /// The memo rows: stranded, quiet, locked-quiet and — while searching — fading notes
    /// without a pipeline row, every kind through the same search + chip + date rule.
    func memoRows(memos: [Memo], files: [PipelineFile], now: Date = Date()) -> [Memo] {
        let live = WayOutRules.stranded(memos: memos, files: files)
            + WayOutRules.unpipelined(memos: memos, files: files, now: now)
            // A locked quiet note stays in the list as title + 🔒 (Q100, C91).
            + WayOutRules.lockedQuiet(memos: memos, files: files, now: now)
        let searching = NotesListModel.isSearching(query)
        var fading: [Memo] = []
        if searching {
            let ingested = Set(files.compactMap { UUID(uuidString: $0.id) })
            fading = MemoLifecycle.partition(memos, now: now).fading.filter {
                !NoteConsent.isRated($0) && !ingested.contains($0.id)
            }
        }
        return NotesListModel.listRows(live: live, fading: fading, searching: searching,
                                       matchesSearch: { matchesSearch($0) },
                                       passesFilter: { passesFilter($0) })
    }

    /// One Related row: a pipeline row or a memo row.
    enum RelatedRow {
        case file(PipelineFile)
        case memo(Memo)
        var key: String {
            switch self {
            case .file(let f): return f.id
            case .memo(let m): return m.id.uuidString
            }
        }
    }

    /// The Related rows: semantic hits (best first) resolved to their row kind, minus rows
    /// already shown, minus hidden locked notes, through the same chip + date rule as the list.
    /// `shown` holds row keys (`PipelineFile.id` / memo UUID string).
    func relatedRows(hits: [UUID], files: [PipelineFile], memos: [Memo], shown: Set<String>,
                     isLockedFile: (PipelineFile) -> Bool, isLockedMemo: (Memo) -> Bool) -> [RelatedRow] {
        guard !hits.isEmpty else { return [] }
        let fileByID = Dictionary(files.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let memoByID = Dictionary(memos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let resolved: [RelatedRow] = hits.compactMap { id in
            if let f = fileByID[id.uuidString] { return .file(f) }
            guard let m = memoByID[id], m.deletedAt == nil else { return nil }
            return .memo(m)
        }
        return NotesListModel.relatedRows(
            resolved, shown: shown, id: \.key,
            hidden: { row in
                switch row {
                case .file(let f): return isLockedFile(f)
                case .memo(let m): return isLockedMemo(m)
                }
            },
            passesFilter: { row in
                switch row {
                case .file(let f): return passesFilter(f)
                case .memo(let m): return passesFilter(m)
                }
            })
    }
}

/// Sidebar queue ordering. Desktop-appropriate subset of the phone's `MemoSort`
/// (the Mac queue has no "edited" notion and durations are strings, so the useful
/// axes are recency + alphabetical).
enum SidebarSort: CaseIterable {
    case newest, oldest, title
    /// Compact label for the inline sort control.
    var short: String {
        switch self {
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        case .title:  return "Title"
        }
    }
    /// The next sort in the cycle (the inline control advances on tap).
    var next: SidebarSort {
        let all = Self.allCases
        return all[(all.firstIndex(of: self).map { $0 + 1 } ?? 0) % all.count]
    }
}

/// One list, two row kinds (rated pipeline rows + quiet unrated memos).
enum SidebarEntry: Identifiable {
    case file(PipelineFile)
    case memo(Memo)

    var id: String {
        switch self {
        case .file(let f): return "pf-" + f.id
        case .memo(let m): return "memo-" + m.id.uuidString
        }
    }
    /// The date a day header keys on — the shared rule (`NotesListModel.groupDate`, Q97 / Q105),
    /// the note's recorded date. The Mac has no "Recently edited" sort, so never the edit day.
    var groupDate: Date {
        switch self {
        case .file(let f):
            return NotesListModel.groupDate(recordedAt: f.uploadedAt, lastEditedAt: f.uploadedAt, byEditTime: false)
        case .memo(let m):
            return NotesListModel.groupDate(recordedAt: m.recordedAt, lastEditedAt: m.lastEditedAt, byEditTime: false)
        }
    }
}
