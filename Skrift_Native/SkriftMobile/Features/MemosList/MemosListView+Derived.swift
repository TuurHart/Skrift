import SwiftUI

extension MemosListView {
    // MARK: - Derived

    /// How close a note's fade must be before the notebook mentions it.
    private static let fadeWarningDays = 7

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
        guard !NoteConsent.isRated(memo), memo.deletedAt == nil, !memo.locked else { return nil }
        let station = MemoSpine.station(for: .from(memo, backlinked: backlinked), now: now)
        switch station {
        case .fading:
            return MemoSpine.oneLiner(for: station, now: now)
        case .new(let fadesAt):
            let warnAt = fadesAt.addingTimeInterval(-Double(Self.fadeWarningDays) * 86_400)
            return now >= warnAt ? MemoSpine.oneLiner(for: station, now: now) : nil
        default:
            return nil
        }
    }

    /// The lifecycle split (MemoLifecycle, 2026-07-17): fading notes leave the
    /// main LIST — but not SEARCH (no-bad-info, 2026-07-21): "no results" about
    /// a note that exists-and-is-recoverable is the worst possible answer to
    /// "where did my note go?". A fading search hit wears an amber tag.
    /// Takes the backlink set as a parameter (R92/C278) — the caller computes
    /// `MemoLifecycle.backlinkedIDs(in:)` ONCE per render and threads it through,
    /// instead of `MemoLifecycle.partition` re-running that corpus scan itself.
    func lifecycle(backlinked: Set<UUID>) -> (live: [Memo], fading: [Memo]) {
        var live: [Memo] = [], fading: [Memo] = []
        for m in memos where m.deletedAt == nil {
            if MemoLifecycle.isFading(m, backlinked: backlinked) { fading.append(m) } else { live.append(m) }
        }
        return (live, fading)
    }

    var searchingNow: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    func filtered(lifecycle: (live: [Memo], fading: [Memo]), enhanced: Set<UUID>) -> [Memo] {
        var out = lifecycle.live.filter { matchesSearch($0) && matchesFilter($0, enhanced: enhanced) }
        if searchingNow {
            out += lifecycle.fading.filter { matchesSearch($0) && matchesFilter($0, enhanced: enhanced) }
        }
        return out.sorted(by: sortComparator)
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
        let backlinked = MemoLifecycle.backlinkedIDs(in: memos)
        let enhanced = enhancedMemoIDs
        let split = lifecycle(backlinked: backlinked)
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


    func matchesSearch(_ memo: Memo) -> Bool {
        memo.matches(query: search)
    }

    /// The rendered Related section: raw semantic hits minus exact matches,
    /// passed through the same filter sheet as everything else. `enhanced` is
    /// threaded in from `derived`'s one-per-render `enhancedMemoIDs` build.
    func relatedDisplay(excluding exact: Set<UUID>, enhanced: Set<UUID>) -> [Memo] {
        guard !related.isEmpty else { return [] }
        return related.filter { !exact.contains($0.id) && matchesFilter($0, enhanced: enhanced) }
    }

    /// Debounced semantic lookup for the current query (P8). Exact matches
    /// never wait on this — it fills the Related section in async.
    func scheduleRelated() {
        // Engine load starts at the FIRST keystroke, not after the debounce —
        // a cold load is minutes on device (devlog 2026-07-08), so every
        // head-start counts. No-op when warm or when the index is off.
        if !search.isEmpty { JournalIndexService.shared.warmUp() }
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
        // The Mac's triage chip (regular width only). `.all` is a no-op, so
        // compact and the phone are untouched (listChip stays .all there).
        // D136: the chip bar filters on EVERY width now (was iPad-regular only —
        // `listChip` stayed `.all` on the phone before, a no-op).
        if !ProcessPile.matches(listChip, memo, enhancedIDs: enhanced) { return false }
        if filter.unsyncedOnly && memo.syncStatus == .synced { return false }
        if filter.hasPhotosOnly && memo.thumbnailPhotoFilename == nil { return false }
        if let place = filter.place, memo.metadata?.location?.placeName != place { return false }
        if filter.from != nil || filter.to != nil {
            let d = filter.dateField == .added ? memo.addedAt : memo.recordedAt
            if !DateRangeFilter.contains(d, from: filter.from, to: filter.to) { return false }
        }
        return true
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

    /// The date a memo is grouped under (day-headers), matching the active sort so
    /// the headers and the order agree.
    func groupDate(_ memo: Memo) -> Date {
        switch sort {
        case .added:  return memo.addedAt
        case .edited: return memo.lastEditedAt
        default:      return memo.recordedAt   // recent / oldest (longest = single group)
        }
    }
}
