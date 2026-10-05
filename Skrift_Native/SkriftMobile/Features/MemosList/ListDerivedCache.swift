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
/// Dirtiness is Observation, not a guess: the base build runs inside `withObservationTracking`.
/// Q322: the tracking is PER NOTE. Each note's list facts (live/fading/trashed, rated, locked,
/// waiting for a polish) are read inside that note's own tracked region, so a change to one note
/// marks only that note dirty and the next pass PATCHES that one row's facts and reassembles the base
/// from the stored facts (no property reads for the other notes), instead of re-reading all of them.
/// Anything the per-note facts cannot answer (membership, a sync import, the clock hour, an
/// enhancement change, a backlink-set change, duplicate rows) rebuilds the whole base as before.
/// Not itself synchronized: MainActor.
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
        /// True when `backlinked` came from the shared `BacklinkIndex` (Q320), false when the base
        /// scanned every transcript itself (no index built yet).
        let backlinkedFromIndex: Bool
        let live: [Memo]
        let fading: [Memo]
        let chipCounts: [QueueFilter: Int]
        let processPile: [Memo]
        /// Q322: set when this base is a one-row-at-a-time patch of generation `patchedFrom`: the ids
        /// whose facts were re-read. nil for a full build.
        var changedIDs: Set<UUID>? = nil
        var patchedFrom: Int? = nil
    }

    /// Everything the base needs to know about ONE note, read once (inside that note's tracked region).
    struct RowFacts: Equatable {
        enum Bucket { case trashed, live, fading }
        var bucket: Bucket
        var rated: Bool
        var locked: Bool
        var deleted: Bool
        /// `ProcessPile.isWaiting` with no polish pass yet: the final answer also needs `!enhanced`.
        var waitingUnlessEnhanced: Bool
    }

    /// How the build tracks what it read. `none` (tests, benchmark) reads untracked.
    struct Tracking {
        /// Whole-base reads (canonical rows, enhancements, a backlink scan): any change = full rebuild.
        var full: (() -> Void) -> Void
        /// One note's reads: a change marks only that note dirty.
        var row: (UUID, () -> Void) -> Void
        static let none = Tracking(full: { $0() }, row: { $1() })
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

    /// Bases produced: full builds plus one-row patches (`fullBuilds` + `rowPatches`).
    private(set) var baseBuilds = 0
    private(set) var fullBuilds = 0
    /// Q322: one-row patches (a note's facts re-read; the other notes' facts reused).
    private(set) var rowPatches = 0
    /// Q322: note facts re-read by patches (1 per edited note).
    private(set) var rowsRebuilt = 0
    private(set) var derivedBuilds = 0
    /// How many notes had their search text lowercased (one per note per note-version).
    private(set) var preparedBuilds = 0

    // MARK: - State

    private struct BaseKey: Equatable { var memos: Int; var enhancements: Int }
    private var base: ListBase?
    private var baseKey: BaseKey?
    private var baseBucket = 0
    private var baseExternalVersion = 0
    private var baseNow = Date()
    private var facts: [RowFacts] = []
    private var indexByID: [UUID: Int] = [:]
    private var hasDuplicateRows = false
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

    /// A tracked property changed (any thread that mutates a model, in practice main). `full` = the
    /// whole base is stale; `rows` = only these notes' facts are.
    private final class DirtyBox: @unchecked Sendable {
        private let lock = NSLock()
        private var full = true
        private var rows = Set<UUID>()
        var isDirty: Bool { lock.lock(); defer { lock.unlock() }; return full || !rows.isEmpty }
        var isFull: Bool { lock.lock(); defer { lock.unlock() }; return full }
        var dirtyRows: Set<UUID> { lock.lock(); defer { lock.unlock() }; return rows }
        func markFull() { lock.lock(); full = true; lock.unlock() }
        func markRow(_ id: UUID) { lock.lock(); rows.insert(id); lock.unlock() }
        func clearAll() { lock.lock(); full = false; rows.removeAll(); lock.unlock() }
        func clearRows() { lock.lock(); rows.removeAll(); lock.unlock() }
    }

    /// Run `body` and arrange for the first change to anything it read to dirty the whole base and
    /// re-evaluate the view that owns it.
    private func tracked<T>(_ body: () -> T) -> T {
        let box = dirtyBox
        return withObservationTracking(body, onChange: { [weak self] in
            box.markFull()   // synchronous: the next body pass must see it
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.scheduleTick() } }
        })
    }

    /// Like `tracked`, but the first change marks only note `id` dirty.
    private func trackedRow(_ id: UUID, _ body: () -> Void) {
        let box = dirtyBox
        withObservationTracking(body, onChange: { [weak self] in
            box.markRow(id)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.scheduleTick() } }
        })
    }

    private var tracking: Tracking {
        Tracking(full: { [unowned self] body in _ = self.tracked(body) },
                 row: { [unowned self] id, body in self.trackedRow(id, body) })
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
        dirtyBox.markFull()
        base = nil
        derivedCache = nil
        lastSearch = nil
    }

    var isDirty: Bool { dirtyBox.isDirty }

    // MARK: - Level 1: the memo-set model

    /// The memo-set model for the current query results. `rawMemos` / `enhancements` are the
    /// view's `@Query` arrays. `externalVersion` is `NotesRepository.memoStructureVersion` (bumped per
    /// CloudKit import and per save that inserted or deleted rows; a plain edit patches its row). `allowStale`: the list is covered by a pushed note (compact
    /// width), so a pure property change may wait for the pop; a membership change never waits
    /// (a deleted model must not be rendered).
    ///
    /// `backlinks` (Q320): the repository's shared backlink index, the current version's or the last
    /// built one. With it the rebuild never rescans transcripts (that scan was 774 ms of main on the
    /// 2,000-note library, per save). nil (nothing built yet) scans, exactly as before. When the
    /// index in hand was an older version's, `backlinksArrived` corrects the list once the current
    /// one lands, so only a link made a moment ago can show for one async build.
    func base(rawMemos: [Memo], enhancements: [MemoEnhancement], externalVersion: Int,
              now: Date = Date(), allowStale: Bool = false, backlinks: BacklinkIndex? = nil) -> ListBase {
        var memoHasher = Hasher()
        for m in rawMemos { memoHasher.combine(ObjectIdentifier(m)) }
        var enhHasher = Hasher()
        for e in enhancements { enhHasher.combine(ObjectIdentifier(e)) }
        let key = BaseKey(memos: memoHasher.finalize() &+ rawMemos.count,
                          enhancements: enhHasher.finalize() &+ enhancements.count)
        let bucket = Int(now.timeIntervalSinceReferenceDate / 3600)   // the fading clock moves hourly

        var patchRows: Set<UUID>?
        if let b = base, key == baseKey {
            let wholeStale = dirtyBox.isFull || externalVersion != baseExternalVersion || bucket != baseBucket
            let rows = dirtyBox.dirtyRows
            if allowStale { return b }
            if !wholeStale && rows.isEmpty { return b }
            // Q322: a note-level change patches that note's facts when nothing else moved. The index
            // in hand must agree with the one the base used (a backlink-set change re-buckets other
            // notes, so it rebuilds), and rows must be one per id (a duplicate group's keeper can move).
            if !wholeStale, !hasDuplicateRows, let index = backlinks, b.backlinkedFromIndex,
               index.linkedIDs == b.backlinked {
                patchRows = rows
            }
            if let rows = patchRows { return patchBase(b, rows: rows) }
        }

        dirtyBox.clearAll()
        generation += 1
        baseBuilds += 1
        fullBuilds += 1
        let built = Self.buildBase(rawMemos: rawMemos, enhancements: enhancements, now: now, generation: generation,
                                   backlinks: backlinks, tracking: tracking, facts: &facts)
        base = built
        baseKey = key
        baseBucket = bucket
        baseNow = now
        baseExternalVersion = externalVersion
        hasDuplicateRows = rawMemos.count != built.memos.count
        indexByID = Dictionary(built.memos.enumerated().map { ($0.element.id, $0.offset) },
                               uniquingKeysWith: { a, _ in a })
        if prepared.count > built.memos.count {
            let ids = Set(built.memos.map(\.id))
            prepared = prepared.filter { ids.contains($0.key) }
        }
        return built
    }

    /// Q322: re-read the facts of `rows` only (re-tracking each), then reassemble from the stored
    /// facts. Everything else (enhanced ids, titles, polish, the backlink set) carries over.
    private func patchBase(_ b: ListBase, rows: Set<UUID>) -> ListBase {
        dirtyBox.clearRows()
        let t = tracking
        var changed = Set<UUID>()
        for id in rows {
            guard let i = indexByID[id] else { continue }
            let m = b.memos[i]
            t.row(id) { facts[i] = Self.rowFacts(of: m, backlinked: b.backlinked, now: baseNow) }
            changed.insert(id)
        }
        generation += 1
        baseBuilds += 1
        rowPatches += 1
        rowsRebuilt += changed.count
        let parts = Self.assemble(memos: b.memos, facts: facts, enhanced: b.enhanced)
        let patched = ListBase(generation: generation, memos: b.memos, enhanced: b.enhanced,
                               enhancedTitleByMemoID: b.enhancedTitleByMemoID, polish: b.polish,
                               backlinked: b.backlinked, backlinkedFromIndex: b.backlinkedFromIndex,
                               live: parts.live, fading: parts.fading, chipCounts: parts.chipCounts,
                               processPile: parts.processPile,
                               changedIDs: changed, patchedFrom: b.generation)
        base = patched
        return patched
    }

    /// One note's list facts. The reads here are the reads the old whole-base build made, plus the
    /// properties the filter / sort / day-grouping read per row (recordedAt, createdAt, editedAt,
    /// duration, locked), so a change to any of them dirties the note.
    static func rowFacts(of m: Memo, backlinked: Set<UUID>, now: Date) -> RowFacts {
        _ = m.recordedAt; _ = m.createdAt; _ = m.editedAt; _ = m.duration
        let deleted = m.deletedAt != nil
        let bucket: RowFacts.Bucket = deleted ? .trashed
            : (MemoLifecycle.isFading(m, backlinked: backlinked, now: now) ? .fading : .live)
        return RowFacts(bucket: bucket, rated: NoteConsent.isRated(m), locked: m.locked, deleted: deleted,
                        waitingUnlessEnhanced: ProcessPile.isWaiting(m, enhancedIDs: []))
    }

    /// The base's live / fading split, chip counts and process pile from stored facts, in `memos`
    /// order. Same rules as `MemoLifecycle.partition`, `QueueFilter.admits`, `ProcessPile`.
    static func assemble(memos: [Memo], facts: [RowFacts], enhanced: Set<UUID>)
        -> (live: [Memo], fading: [Memo], chipCounts: [QueueFilter: Int], processPile: [Memo]) {
        var live: [Memo] = [], fading: [Memo] = [], pile: [Memo] = []
        var needsWork = 0, done = 0, notRated = 0
        for (i, m) in memos.enumerated() {
            let f = facts[i]
            switch f.bucket {
            case .live: live.append(m)
            case .fading: fading.append(m)
            case .trashed: break
            }
            let processed = enhanced.contains(m.id)
            if QueueFilter.needsWork.admits(rated: f.rated, processed: processed, locked: f.locked) { needsWork += 1 }
            if QueueFilter.done.admits(rated: f.rated, processed: processed, locked: f.locked) { done += 1 }
            if !f.rated && !f.deleted && !f.locked { notRated += 1 }
            if f.waitingUnlessEnhanced && !processed { pile.append(m) }
        }
        return (live, fading, NotesListModel.chipCounts(needsWork: needsWork, done: done, notRated: notRated), pile)
    }

    /// The pure build (static so tests and the benchmark can call it without a cache).
    static func buildBase(rawMemos: [Memo], enhancements: [MemoEnhancement], now: Date,
                          generation: Int, backlinks: BacklinkIndex? = nil) -> ListBase {
        var scratch: [RowFacts] = []
        return buildBase(rawMemos: rawMemos, enhancements: enhancements, now: now, generation: generation,
                         backlinks: backlinks, tracking: .none, facts: &scratch)
    }

    /// The build proper. `facts` receives one entry per canonical row, aligned with `ListBase.memos`.
    static func buildBase(rawMemos: [Memo], enhancements: [MemoEnhancement], now: Date,
                          generation: Int, backlinks: BacklinkIndex?, tracking: Tracking,
                          facts: inout [RowFacts]) -> ListBase {
        var memos: [Memo] = []
        tracking.full { memos = MemoDuplicates.canonicalRows(rawMemos) }
        var backlinked: Set<UUID> = backlinks?.linkedIDs ?? []
        if backlinks == nil {
            // No index built yet: scan every transcript (and copy-edit) once. Any change to one of
            // them stales the whole set, so it is one whole-base region.
            tracking.full {
                backlinked = MemoLifecycle.backlinkedIDs(in: memos, copyedits: Backlinks.copyeditsByMemoID(enhancements))
            }
        }
        var enhanced = Set<UUID>()
        var titles: [UUID: String] = [:]
        var polish: [UUID: (title: String, summary: String)] = [:]
        tracking.full {
            enhanced = Set(enhancements.lazy.filter(\.isProcessed).map(\.memoID))
            for e in enhancements {
                let t = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty, titles[e.memoID] == nil { titles[e.memoID] = t }
                if polish[e.memoID] == nil { polish[e.memoID] = (e.title, e.summary) }
            }
        }
        facts = []
        facts.reserveCapacity(memos.count)
        for m in memos {
            var f = RowFacts(bucket: .live, rated: false, locked: false, deleted: false, waitingUnlessEnhanced: false)
            tracking.row(m.id) { f = rowFacts(of: m, backlinked: backlinked, now: now) }
            facts.append(f)
        }
        let parts = assemble(memos: memos, facts: facts, enhanced: enhanced)
        return ListBase(generation: generation, memos: memos, enhanced: enhanced,
                        enhancedTitleByMemoID: titles, polish: polish, backlinked: backlinked,
                        backlinkedFromIndex: backlinks != nil,
                        live: parts.live, fading: parts.fading, chipCounts: parts.chipCounts,
                        processPile: parts.processPile)
    }

    /// The current version's backlink index just landed (Q320). If the base was built from an
    /// older index (or from a scan) and the linked set differs, rebuild once from the right one.
    func backlinksArrived(_ index: BacklinkIndex) {
        guard let base, base.backlinked != index.linkedIDs else { return }
        dirtyBox.markFull()
        scheduleTick()
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
            let hit = matchedPool(base: base, params: params, query: q)   // reads are tracked per note, in preparedSearch
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
        // Q322: across a one-row patch every note the patch did not touch keeps its search text.
        if var e = prepared[m.id], let from = base.patchedFrom, e.generation == from,
           let changed = base.changedIDs, !changed.contains(m.id) {
            e.generation = base.generation
            prepared[m.id] = e
            return e.prepared
        }
        let p = base.polish[m.id]
        // The reads below (fingerprint + snapshot) are this note's own tracked region: a change to a
        // search source marks just this note dirty (Q322), so the next pass patches its row.
        var result: PreparedNoteSearch?
        trackedRow(m.id) {
            let f = Fingerprint(
                lastEditedAt: m.lastEditedAt, transcriptCount: m.transcript?.utf8.count, title: m.title,
                tags: m.tags, annotationCount: m.annotationText?.utf8.count, metadataCount: m.metadataData?.count,
                sharedCount: m.sharedContentData?.count, locked: m.locked,
                polishTitle: p?.title, polishSummary: p?.summary)
            if var e = prepared[m.id], e.fingerprint == f {
                e.generation = base.generation
                prepared[m.id] = e
                result = e.prepared
                return
            }
            preparedBuilds += 1
            let snap = m.noteSearchSnapshot(unlockedThisSession: false, enhancedTitle: p?.title, summary: p?.summary)
            let prep = PreparedNoteSearch(snap)
            prepared[m.id] = PreparedEntry(fingerprint: f, generation: base.generation, prepared: prep)
            result = prep
        }
        return result!
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
