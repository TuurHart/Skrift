import SwiftUI

extension MemosListView {
    // MARK: - Derived

    /// Unrated-live = the quiet FADE, every width (m1b B + Tuur's 2026-07-23
    /// phone extension — his flow rates important notes AT capture, so an
    /// unrated row genuinely means untriaged, not fresh: "when I take a note
    /// that I know is important I give it a score straight away"). Rating IS
    /// the flag (no Flag verb anywhere, same correction as the Mac's m6 peek);
    /// tap opens the note, whose Importance circles are the rating surface.
    func isUnratedLive(_ memo: Memo) -> Bool {
        !NoteConsent.isRated(memo) && memo.deletedAt == nil && !memo.locked
    }

    /// Urgency-only clock line (⏱ eyeball wave 2, 2026-07-22; asymmetry
    /// REVISED 2026-07-23 — the fade above now runs on every width): the line
    /// appears (amber) only when the clock actually matters — fading starts
    /// within `fadeWarningDays`, or the note is already fading (a search hit).
    func clockLine(for memo: Memo, backlinked: Set<UUID>, now: Date = Date()) -> String? {
        // Q107: the rule is shared (`MemoSpine.rowClockLine`) — the Mac's quiet rows call it too.
        MemoSpine.rowClockLine(for: memo, backlinked: backlinked, now: now)
    }

    var searchingNow: Bool { NotesListModel.isSearching(search) }

    func filtered(lifecycle: (live: [Memo], fading: [Memo]), enhanced: Set<UUID>) -> [Memo] {
        // The generated title + summary live on MemoEnhancement; index them once per pass
        // (only while searching) so the shared matcher sees them (Q103/C236).
        let polish: [UUID: (title: String, summary: String)] = searchingNow
            ? Dictionary(enhancements.map { ($0.memoID, ($0.title, $0.summary)) }, uniquingKeysWith: { a, _ in a })
            : [:]
        return Self.listRows(lifecycle: lifecycle, search: search, chip: listChip, filter: filter,
                             enhanced: enhanced, polish: polish,
                             isUnlocked: { LockGate.shared.isUnlocked($0) })
            .sorted(by: sortComparator)
    }

    /// The phone's adapter onto the shared list rule (`NotesListModel.listRows`, Q104): live
    /// rows plus, while searching, fading rows, both through the same search + chip + filter
    /// sheet. Unsorted; pure so `NotesListFilterParityTests` drives it.
    static func listRows(lifecycle: (live: [Memo], fading: [Memo]), search: String, chip: QueueFilter,
                         filter: MemoFilter, enhanced: Set<UUID>,
                         polish: [UUID: (title: String, summary: String)] = [:],
                         isUnlocked: (String) -> Bool) -> [Memo] {
        NotesListModel.listRows(
            live: lifecycle.live, fading: lifecycle.fading, searching: NotesListModel.isSearching(search),
            matchesSearch: { m in
                let p = polish[m.id]
                return m.matches(query: search, unlockedThisSession: isUnlocked(m.id.uuidString),
                                 enhancedTitle: p?.title, summary: p?.summary)
            },
            passesFilter: { passesFilter($0, chip: chip, filter: filter, enhanced: enhanced) })
    }

    struct Group { let title: String; let memos: [Memo] }

    /// Everything the list body derives from ONE filter+sort pass (R92/C278):
    /// `flatIndex`, `enhancedTitleByMemoID` and `searchFadingIDs` used to be
    /// separate computed properties read per visible ROW inside `ForEach`, each
    /// re-running its own full corpus scan N times. Now built once here and
    /// read by index/lookup in the row loop — O(1) scans per render, not O(N).
    struct Derived {
        let groups: [Group]
        let flatIndex: [UUID: Int]
        let related: [Memo]
        let enhancedTitleByMemoID: [UUID: String]
        let searchFadingIDs: Set<UUID>
        let backlinked: Set<UUID>
    }

    var derived: Derived {
        let backlinked = MemoLifecycle.backlinkedIDs(in: memos, copyedits: Backlinks.copyeditsByMemoID(enhancements))
        let enhanced = enhancedMemoIDs
        let split = MemoLifecycle.partition(memos, backlinked: backlinked)  // one backlink scan per render (R92/C278)
        let f = filtered(lifecycle: split, enhanced: enhanced)
        let fadingIDs: Set<UUID> = searchingNow ? Set(split.fading.map(\.id)) : []
        return Derived(
            groups: groups(from: f),
            flatIndex: Dictionary(f.enumerated().map { ($0.element.id, $0.offset) },
                                  uniquingKeysWith: { a, _ in a }),
            related: relatedDisplay(excluding: Set(f.map(\.id)), enhanced: enhanced),
            enhancedTitleByMemoID: enhancedTitleByMemoID(),
            searchFadingIDs: fadingIDs,
            backlinked: backlinked)
    }

    func groups(from filtered: [Memo]) -> [Group] {
        if sort == .longest {
            return filtered.isEmpty ? [] : [Group(title: "Longest first", memos: filtered)]
        }
        // Shared cross-app grouping pass (NotesListModel.dayGroups) instead of
        // a hand-rolled order-array + bucket-dict loop duplicating the exact
        // same logic (sweep-b finding #9).
        return NotesListModel.dayGroups(filtered) { MemoDate.group(groupDate($0)) }
            .map { Group(title: $0.title, memos: $0.items) }
    }


    func matchesSearch(_ memo: Memo, polish: (title: String, summary: String)? = nil) -> Bool {
        memo.matches(query: search, unlockedThisSession: LockGate.shared.isUnlocked(memo.id.uuidString),
                     enhancedTitle: polish?.title, summary: polish?.summary)
    }

    /// The rendered Related section: raw semantic hits minus exact matches,
    /// passed through the same filter sheet as everything else. `enhanced` is
    /// threaded in from `derived`'s one-per-render `enhancedMemoIDs` build.
    func relatedDisplay(excluding exact: Set<UUID>, enhanced: Set<UUID>) -> [Memo] {
        guard !related.isEmpty else { return [] }
        return Self.relatedRows(related, shown: exact, chip: listChip, filter: filter, enhanced: enhanced,
                                isLocked: { LockGate.shared.isLocked($0) })
    }

    /// The phone's adapter onto the shared Related rule (`NotesListModel.relatedRows`, Q104).
    /// Q101 (C91/C161): a semantic hit is the note's words too — a hidden locked note never surfaces.
    static func relatedRows(_ hits: [Memo], shown: Set<UUID>, chip: QueueFilter, filter: MemoFilter,
                            enhanced: Set<UUID>, isLocked: (Memo) -> Bool) -> [Memo] {
        NotesListModel.relatedRows(hits, shown: shown, id: \.id, hidden: isLocked,
                                   passesFilter: { passesFilter($0, chip: chip, filter: filter, enhanced: enhanced) })
    }

    /// Debounced semantic lookup for the current query (P8). Exact matches
    /// never wait on this — it fills the Related section in async.
    func scheduleRelated() {
        // Engine load starts at the FIRST keystroke, not after the debounce —
        // a cold load is minutes on device (devlog 2026-07-08), so every
        // head-start counts. No-op when warm or when the index is off.
        if SemanticSearch.warmsEngine(forQuery: search) { JournalIndexService.shared.warmUp() }
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await refreshRelated()
        }
    }

    func refreshRelated() async {
        let q = search.trimmingCharacters(in: .whitespaces)
        // Round-5 trace: device searches produced ZERO SemanticSearch lines
        // while sweeps ran fine — log the entry + every gate's verdict.
        if !q.isEmpty {
            let service = JournalIndexService.shared
            DevLog.log("refreshRelated '\(q.prefix(30))' active=\(service.isActive) enabled=\(service.isEnabled) model=\(GemmaEmbedder.isModelDownloaded)")
        }
        guard !q.isEmpty, JournalIndexService.shared.isActive else {
            if !related.isEmpty { related = [] }
            return
        }
        let scores = await JournalIndexService.shared.searchScores(q, repository: repository)
        guard !Task.isCancelled, q == search.trimmingCharacters(in: .whitespaces) else { return }
        let byID = Dictionary(memos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        related = JournalIndexService.relatedResults(scores: scores, excluding: [], memosByID: byID)
    }

    func matchesFilter(_ memo: Memo, enhanced: Set<UUID>) -> Bool {
        Self.passesFilter(memo, chip: listChip, filter: filter, enhanced: enhanced)
    }

    /// The phone's chip + filter-sheet answer for one memo, through the shared rule
    /// (`NotesListModel.passesFilter`, Q104). D136: the chip bar filters on every width.
    static func passesFilter(_ memo: Memo, chip: QueueFilter, filter: MemoFilter, enhanced: Set<UUID>) -> Bool {
        let d = NotesListModel.filterDate(field: filter.dateField, recordedAt: memo.recordedAt, addedAt: memo.addedAt)
        return NotesListModel.passesFilter(inChip: chip.admits(memo, enhancedIDs: enhanced),
                                           date: d, from: filter.from, to: filter.to)
    }

    func sortComparator(_ a: Memo, _ b: Memo) -> Bool {
        switch sort {
        case .added:  return a.addedAt > b.addedAt
        case .edited: return a.lastEditedAt > b.lastEditedAt
        case .recent: return a.recordedAt > b.recordedAt
        case .oldest: return a.recordedAt < b.recordedAt
        case .longest: return a.duration > b.duration
        }
    }

    /// The date a memo is grouped under (day-headers): the note's real date via the shared
    /// rule (`NotesListModel.groupDate`) — NOT `addedAt`, even when the list is ordered by
    /// "Recently added" (Q97: arrival time is not a day the note happened).
    func groupDate(_ memo: Memo) -> Date {
        NotesListModel.groupDate(recordedAt: memo.recordedAt, lastEditedAt: memo.lastEditedAt,
                                 byEditTime: sort == .edited)
    }
}
