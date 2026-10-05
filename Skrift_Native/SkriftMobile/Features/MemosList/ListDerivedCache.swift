import Foundation
import Observation
import SwiftUI

/// Q315 — the Notes list's derived data as a CACHED MODEL, rebuilt when the memo set (or a
/// property it read) changes, not on every `MemosListView.body` pass.
///
/// Measured on the iPhone 13 over 2,000 notes (`plan/perf2/MEASURED.md`): searching "morning"
/// ~10 s of main thread, stopping a recording 6.4 s, Done after typing 2.9 s, all in
/// `derived` → `filtered` / `listRows` / `matchesSearch` / `MemoLifecycle.backlinkedIDs`, which
/// the body re-ran in full on every redraw (every keystroke, every sync batch).
///
/// Two levels:
/// - `ListBase` (the memo-set model): canonical rows, enhanced ids, enhanced titles, the
///   backlink set, the live/fading split, chip counts, the process pile. Rebuilt when the set
///   changes (membership, a read property, a repository `memoSetVersion` bump, the clock hour).
/// - `NotesListDerived` (what one query/chip/sort/filter shows): rebuilt when the base or
///   those parameters change. A search that EXTENDS the previous query narrows from the previous
///   hits, and matches against each note's lowercased search text, built once per note version.
///
/// Dirtiness is Observation, not a guess: the base build runs inside `withObservationTracking`,
/// so the first change to any `Memo` / `MemoEnhancement` property it read marks the cache dirty
/// (the same reads the old body made, so the same changes). Not itself synchronized: MainActor.
@MainActor
final class ListDerivedCache: ObservableObject {

    // MARK: - The two cached values

    struct ListBase {
        let generation: Int
        /// One row per id (`MemoDuplicates.canonicalRows`).
        let memos: [Memo]
        let enhanced: Set<UUID>
        /// memoID → the Mac's generated title (non-empty, trimmed).
        let enhancedTitleByMemoID: [UUID: String]
        /// memoID → (generated title, summary) for the shared matcher (Q103/C236).
        let polish: [UUID: (title: String, summary: String)]
        let backlinked: Set<UUID>
        let live: [Memo]
        let fading: [Memo]
        let chipCounts: [QueueFilter: Int]
        let processPile: [Memo]
    }

    struct Params: Equatable {
        var search: String
        var chip: QueueFilter
        var filter: MemoFilter
        var sort: MemoSort
        /// `LockGate.unlockedIDs`: a note unlocked this session may match on its body.
        var unlocked: Set<String>
    }

    // MARK: - Counters (read by tests: "does not rebuild" / "does not re-lowercase")

    private(set) var baseBuilds = 0
    private(set) var derivedBuilds = 0
    /// How many notes had their search text lowercased (one per note per note-version).
    private(set) var preparedBuilds = 0

    // MARK: - State

    private struct BaseKey: Equatable { var memos: Int; var enhancements: Int }
    private var base: ListBase?
    private var baseKey: BaseKey?
    private var baseBucket = 0
    private var baseExternalVersion = 0
    private var generation = 0
    private let dirtyBox = DirtyBox()

    private var derivedCache: (generation: Int, params: Params, relatedIDs: [UUID], value: NotesListDerived)?

    /// The previous query's hits (live + fading pool, before chip/date filters), for narrowing.
    private var lastSearch: (generation: Int, query: String, unlocked: Set<String>, ids: Set<UUID>)?

    private struct Fingerprint: Equatable {
        var lastEditedAt: Date
        var transcriptCount: Int?
        var title: String?
        var tags: [String]
        var annotationCount: Int?
        var metadataCount: Int?
        var sharedCount: Int?
        var locked: Bool
        var polishTitle: String?
        var polishSummary: String?
    }
    private struct PreparedEntry {
        var fingerprint: Fingerprint
        var generation: Int
        let prepared: PreparedNoteSearch
    }
    private var prepared: [UUID: PreparedEntry] = [:]

    private var tickScheduled = false

    // MARK: - Dirtiness

    /// A tracked property changed (any thread that mutates a model — in practice main).
    private final class DirtyBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value = true
        var isDirty: Bool { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ v: Bool) { lock.lock(); value = v; lock.unlock() }
    }

    /// Run `body` and arrange for the first change to anything it read to dirty the cache and
    /// re-evaluate the view that owns it.
    private func tracked<T>(_ body: () -> T) -> T {
        let box = dirtyBox
        return withObservationTracking(body, onChange: { [weak self] in
            box.set(true)   // synchronous: the next body pass must see it
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.scheduleTick() } }
        })
    }

    private func scheduleTick() {
        guard !tickScheduled else { return }
        tickScheduled = true
        // Next turn: many changes in one burst re-evaluate the list once.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tickScheduled = false
                self.objectWillChange.send()
            }
        }
    }

    /// Forget everything (tests; and the next call rebuilds).
    func invalidate() {
        dirtyBox.set(true)
        base = nil
        derivedCache = nil
        lastSearch = nil
    }

    var isDirty: Bool { dirtyBox.isDirty }

    // MARK: - Level 1: the memo-set model

    /// The memo-set model for the current query results. `rawMemos` / `enhancements` are the
    /// view's `@Query` arrays. `externalVersion` is `NotesRepository.memoSetVersion` (bumped per
    /// save and per CloudKit import). `allowStale`: the list is covered by a pushed note (compact
    /// width), so a pure property change may wait for the pop; a membership change never waits
    /// (a deleted model must not be rendered).
    func base(rawMemos: [Memo], enhancements: [MemoEnhancement], externalVersion: Int,
              now: Date = Date(), allowStale: Bool = false) -> ListBase {
        var memoHasher = Hasher()
        for m in rawMemos { memoHasher.combine(ObjectIdentifier(m)) }
        var enhHasher = Hasher()
        for e in enhancements { enhHasher.combine(ObjectIdentifier(e)) }
        let key = BaseKey(memos: memoHasher.finalize() &+ rawMemos.count,
                          enhancements: enhHasher.finalize() &+ enhancements.count)
        let bucket = Int(now.timeIntervalSinceReferenceDate / 3600)   // the fading clock moves hourly

        if let b = base, key == baseKey {
            let propertiesChanged = dirtyBox.isDirty || externalVersion != baseExternalVersion
            if allowStale { return b }
            if !propertiesChanged && bucket == baseBucket { return b }
        }

        dirtyBox.set(false)
        generation += 1
        baseBuilds += 1
        let built = tracked {
            Self.buildBase(rawMemos: rawMemos, enhancements: enhancements, now: now, generation: generation)
        }
        base = built
        baseKey = key
        baseBucket = bucket
        baseExternalVersion = externalVersion
        if prepared.count > built.memos.count {
            let ids = Set(built.memos.map(\.id))
            prepared = prepared.filter { ids.contains($0.key) }
        }
        return built
    }

    /// The pure build (static so tests and the benchmark can call it without a cache).
    static func buildBase(rawMemos: [Memo], enhancements: [MemoEnhancement], now: Date,
                          generation: Int) -> ListBase {
        let memos = MemoDuplicates.canonicalRows(rawMemos)
        let backlinked = MemoLifecycle.backlinkedIDs(in: memos, copyedits: Backlinks.copyeditsByMemoID(enhancements))
        let enhanced = Set(enhancements.lazy.filter(\.isProcessed).map(\.memoID))
        let split = MemoLifecycle.partition(memos, backlinked: backlinked, now: now)
        var titles: [UUID: String] = [:]
        var polish: [UUID: (title: String, summary: String)] = [:]
        for e in enhancements {
            let t = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, titles[e.memoID] == nil { titles[e.memoID] = t }
            if polish[e.memoID] == nil { polish[e.memoID] = (e.title, e.summary) }
        }
        // Properties the filter / sort / day-grouping read per row. Read here, inside the base's
        // tracking, so a change to one of them dirties the cache (the derived pass reads them
        // again but is not itself tracked).
        for m in memos {
            _ = m.recordedAt; _ = m.createdAt; _ = m.editedAt; _ = m.duration; _ = m.locked
        }
        let counts = NotesListModel.chipCounts(
            needsWork: memos.filter { QueueFilter.needsWork.admits($0, enhancedIDs: enhanced) }.count,
            done: memos.filter { QueueFilter.done.admits($0, enhancedIDs: enhanced) }.count,
            notRated: ProcessPile.unrated(memos: memos).count)
        return ListBase(generation: generation, memos: memos, enhanced: enhanced,
                        enhancedTitleByMemoID: titles, polish: polish, backlinked: backlinked,
                        live: split.live, fading: split.fading, chipCounts: counts,
                        processPile: ProcessPile.waiting(memos: memos, enhancedIDs: enhanced))
    }

    // MARK: - Level 2: what this query / chip / sort / filter shows

    func derived(base: ListBase, params: Params, related: [Memo]) -> NotesListDerived {
        let relatedIDs = related.map(\.id)
        if let c = derivedCache, c.generation == base.generation, c.params == params, c.relatedIDs == relatedIDs {
            return c.value
        }
        derivedBuilds += 1
        let searching = NotesListModel.isSearching(params.search)

        var rows: [Memo]
        if searching {
            let q = NoteVisibility.normalizedQuery(params.search)
            let hit = tracked { matchedPool(base: base, params: params, query: q) }
            lastSearch = (base.generation, q, params.unlocked, Set(hit.live.lazy.map(\.id)).union(hit.fading.lazy.map(\.id)))
            rows = NotesListModel.listRows(
                live: hit.live, fading: hit.fading, searching: true,
                matchesSearch: { _ in true },
                passesFilter: { MemosListView.passesFilter($0, chip: params.chip, filter: params.filter, enhanced: base.enhanced) })
        } else {
            lastSearch = nil
            rows = NotesListModel.listRows(
                live: base.live, fading: base.fading, searching: false,
                matchesSearch: { _ in true },
                passesFilter: { MemosListView.passesFilter($0, chip: params.chip, filter: params.filter, enhanced: base.enhanced) })
        }
        rows.sort { MemosListView.isOrdered($0, $1, by: params.sort) }

        let shown = Set(rows.map(\.id))
        let relatedRows: [Memo] = related.isEmpty ? [] : MemosListView.relatedRows(
            related, shown: shown, chip: params.chip, filter: params.filter, enhanced: base.enhanced,
            isLocked: { !NoteVisibility.contentVisible(locked: $0.locked,
                                                       unlockedThisSession: params.unlocked.contains($0.id.uuidString)) })

        let value = NotesListDerived(
            groups: Self.groups(from: rows, sort: params.sort),
            flatIndex: Dictionary(rows.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a }),
            related: relatedRows,
            enhancedTitleByMemoID: base.enhancedTitleByMemoID,
            searchFadingIDs: searching ? Set(base.fading.map(\.id)) : [],
            backlinked: base.backlinked)
        derivedCache = (base.generation, params, relatedIDs, value)
        return value
    }

    static func groups(from rows: [Memo], sort: MemoSort) -> [NotesListGroup] {
        if sort == .longest {
            return rows.isEmpty ? [] : [NotesListGroup(title: "Longest first", memos: rows)]
        }
        return NotesListModel.dayGroups(rows) {
            MemoDate.group(NotesListModel.groupDate(recordedAt: $0.recordedAt, lastEditedAt: $0.lastEditedAt,
                                                    byEditTime: sort == .edited))
        }.map { NotesListGroup(title: $0.title, memos: $0.items) }
    }

    /// The live and fading notes matching `query`. An extension of the previous query only
    /// looks at the previous hits (a note matching "morning" matched "morn").
    private func matchedPool(base: ListBase, params: Params, query q: String) -> (live: [Memo], fading: [Memo]) {
        var live = base.live, fading = base.fading
        if let last = lastSearch, last.generation == base.generation, last.unlocked == params.unlocked,
           !last.query.isEmpty, q.hasPrefix(last.query) {
            live = live.filter { last.ids.contains($0.id) }
            fading = fading.filter { last.ids.contains($0.id) }
        }
        let unlocked = params.unlocked
        func match(_ m: Memo) -> Bool {
            preparedSearch(for: m, base: base)
                .matches(normalizedQuery: q, unlockedThisSession: unlocked.contains(m.id.uuidString))
        }
        return (live.filter(match), fading.filter(match))
    }

    /// The note's lowercased search text; rebuilt only when the note's search sources changed.
    private func preparedSearch(for m: Memo, base: ListBase) -> PreparedNoteSearch {
        if let e = prepared[m.id], e.generation == base.generation { return e.prepared }
        let p = base.polish[m.id]
        let f = Fingerprint(
            lastEditedAt: m.lastEditedAt, transcriptCount: m.transcript?.utf8.count, title: m.title,
            tags: m.tags, annotationCount: m.annotationText?.utf8.count, metadataCount: m.metadataData?.count,
            sharedCount: m.sharedContentData?.count, locked: m.locked,
            polishTitle: p?.title, polishSummary: p?.summary)
        if var e = prepared[m.id], e.fingerprint == f {
            e.generation = base.generation
            prepared[m.id] = e
            return e.prepared
        }
        preparedBuilds += 1
        let snap = m.noteSearchSnapshot(unlockedThisSession: false, enhancedTitle: p?.title, summary: p?.summary)
        let prep = PreparedNoteSearch(snap)
        prepared[m.id] = PreparedEntry(fingerprint: f, generation: base.generation, prepared: prep)
        return prep
    }
}

struct NotesListGroup { let title: String; let memos: [Memo] }

/// Everything the list body derives from ONE filter + sort pass (R92/C278).
struct NotesListDerived {
    let groups: [NotesListGroup]
    let flatIndex: [UUID: Int]
    let related: [Memo]
    let enhancedTitleByMemoID: [UUID: String]
    let searchFadingIDs: Set<UUID>
    let backlinked: Set<UUID>
}
