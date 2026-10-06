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

    /// The query the list is filtered by: the search field's text, settled ~150 ms after the
    /// last keystroke (Q315) so a burst of typing filters once, not per letter.
    var searchingNow: Bool { NotesListModel.isSearching(appliedSearch) }

    /// The phone's adapter onto the shared list rule (`NotesListModel.listRows`, Q104): live
    /// rows plus, while searching, fading rows, both through the same search + chip + filter
    /// sheet. Unsorted; pure so `NotesListFilterParityTests` drives it. The list itself runs the
    /// same rule through `ListDerivedCache` (prepared search text, narrowing, cached per memo
    /// set); `ListDerivedCacheTests` proves both paths agree.
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

    typealias Group = NotesListGroup
    typealias Derived = NotesListDerived

    /// The memo-set model (`ListDerivedCache.ListBase`): canonical rows, enhanced ids, backlink set,
    /// live/fading split, chip counts, process pile. Cached; rebuilt only when the memo set or a
    /// property it read changes. While a note is pushed over the list (compact width) a pure
    /// property change waits for the pop; membership changes never wait.
    var listBase: ListDerivedCache.ListBase {
        listCache.base(rawMemos: rawMemos, enhancements: enhancements,
                       externalVersion: repository.memoStructureVersion,   // Q322: edits patch per note; only sync + insert/delete rebuild all
                       allowStale: !isRegular && !path.isEmpty,
                       backlinks: repository.backlinkIndexNow()?.index)   // Q320: no per-rebuild transcript scan
    }

    /// Everything the list body shows for the current query / chip / sort / filter (R92/C278).
    var derived: Derived {
        listCache.derived(
            base: listBase,
            params: ListDerivedCache.Params(search: appliedSearch, chip: listChip, filter: filter, sort: sort,
                                            unlocked: LockGate.shared.unlockedIDs),
            related: related)
    }

    /// The rendered Related section is built inside `derived` (hits minus exact matches, through
    /// the same filter sheet as everything else).

    /// The phone's adapter onto the shared Related rule (`NotesListModel.relatedRows`, Q104).
    /// Q101 (C91/C161): a semantic hit is the note's words too — a hidden locked note never surfaces.
    static func relatedRows(_ hits: [Memo], shown: Set<UUID>, chip: QueueFilter, filter: MemoFilter,
                            enhanced: Set<UUID>, isLocked: (Memo) -> Bool) -> [Memo] {
        NotesListModel.relatedRows(hits, shown: shown, id: \.id, hidden: isLocked,
                                   passesFilter: { passesFilter($0, chip: chip, filter: filter, enhanced: enhanced) })
    }

    /// Settle the list's query ~150 ms after the last keystroke (Q315). Clearing applies at once.
    func applySearchDebounced(_ text: String) {
        applyTask?.cancel()
        if !NotesListModel.isSearching(text) {
            appliedSearch = text
            return
        }
        applyTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            appliedSearch = text
        }
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
        guard !q.isEmpty, JournalIndexService.shared.isActive else {
            if !related.isEmpty { related = [] }
            return
        }
        let scores = await JournalIndexService.shared.searchScores(q, repository: repository)
        guard !Task.isCancelled, q == search.trimmingCharacters(in: .whitespaces) else { return }
        let byID = Dictionary(memos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        related = JournalIndexService.relatedResults(scores: scores, excluding: [], memosByID: byID)
    }

    /// The phone's chip + filter-sheet answer for one memo, through the shared rule
    /// (`NotesListModel.passesFilter`, Q104). D136: the chip bar filters on every width.
    static func passesFilter(_ memo: Memo, chip: QueueFilter, filter: MemoFilter, enhanced: Set<UUID>) -> Bool {
        let d = NotesListModel.filterDate(field: filter.dateField, recordedAt: memo.recordedAt, addedAt: memo.addedAt)
        return NotesListModel.passesFilter(inChip: chip.admits(memo, enhancedIDs: enhanced),
                                           date: d, from: filter.from, to: filter.to)
    }

    /// Changes when any device's edit head changes (C98): drives the conflict re-check. One hash,
    /// not a string per head per body pass.
    var editHeadsStamp: Int {
        var h = Hasher()
        for head in editHeads { h.combine(head.memoID); h.combine(head.editedAt.timeIntervalSince1970) }
        return h.finalize()
    }

    /// The list order for a sort (a strict "a before b").
    static func isOrdered(_ a: Memo, _ b: Memo, by sort: MemoSort) -> Bool {
        switch sort {
        case .added:  return a.addedAt > b.addedAt
        case .edited: return a.lastEditedAt > b.lastEditedAt
        case .recent: return a.recordedAt > b.recordedAt
        case .oldest: return a.recordedAt < b.recordedAt
        case .longest: return a.duration > b.duration
        }
    }
}

/// The "Syncing with iCloud…" capsule (a floating pill at the bottom of the list). Its own view so
/// the Notes list does not observe all of `CloudSyncMonitor` — only `isSyncing` is shown here (Q315).
struct SyncingCapsule: View {
    @ObservedObject private var cloudSync = CloudSyncMonitor.shared

    var body: some View {
        Group {
            if cloudSync.isSyncing {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.mini)
                    Text("Syncing with iCloud…").font(.caption)
                }
                .foregroundStyle(Color.skTextDim)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.skElev))
                .overlay(Capsule().stroke(Color.skBorder, lineWidth: 1))
                .padding(.bottom, 14)
                .transition(.opacity)
                .accessibilityIdentifier("cloud-sync-indicator")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: cloudSync.isSyncing)
    }
}
