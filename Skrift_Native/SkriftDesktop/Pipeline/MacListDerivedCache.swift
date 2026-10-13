import Foundation
import Observation

/// Q361 (D186 / D191 / C279; `plan/perf2/f-mac-ui.md` M1 M2 M11): the Mac sidebar's list as a
/// CACHED MODEL, the Mac half of the phone's `ListDerivedCache` (Q315).
///
/// Before this, `SidebarView.body` re-derived the whole list on every pass: chip counts x4,
/// stranded/quiet sets, two sorts, two full-corpus backlink text scans, per-row day grouping,
/// and every search keystroke re-lowercased and re-decoded every note. A body pass runs on every
/// click, every recording-meter push and every run-progress tick.
///
/// Two levels, both rebuilt only when their inputs change:
/// - Base (the memo set): chip counts, stranded / quiet / locked-quiet / fading-hit memos. Keyed on
///   the identity of the file and memo rows, the memo-set version the sidebar bumps when it
///   re-reads the store, the backlink set size, and the clock hour (fading moves hourly). The
///   backlink set is an INPUT (the sidebar refreshes it with its memo fetch); this never scans
///   transcripts for it unless handed nil.
/// - Derived (what one chip / query / sort / date range shows): entries, queue rows, ids, day
///   groups. Keyed on the base generation, the params and the calendar day.
///
/// Staleness is Observation, not a guess: both builds run inside `withObservationTracking`, so a
/// change to any model property they read (a row's polish state, lock, a memo's rating) marks the
/// cache dirty and bumps `tick`, which the sidebar's body reads.
///
/// Search matches against each note's lowercased text (`PreparedNoteSearch`), built once per note
/// VERSION (a cheap fingerprint), so a keystroke lowercases nothing and decodes no JSON.
/// Foundation + Observation only, so the host-less `SkriftDesktopTests` drive it.
@MainActor
@Observable
final class MacListDerivedCache {

    struct Params: Equatable {
        var chip: QueueFilter = .all
        var query: String = ""
        var from: Date?
        var to: Date?
        var dateField: MemoDateField = .recorded
        var sort: SidebarSort = .newest
        /// `LockGate.unlockedIDs`: a note unlocked this session may match on its body.
        var unlocked: Set<String> = []
    }

    struct Inputs {
        var files: [PipelineFile]
        var memos: [Memo]
        /// Bumped by the sidebar whenever it re-reads the store (`refreshCloudMemos`).
        var memoVersion: Int
        /// The cached backlink set. nil = scan once (counted in `backlinkScans`).
        var backlinked: Set<UUID>?
        var addedAtByID: [String: Date]
        var processedIDs: Set<UUID>
        var now: Date = Date()
    }

    struct Derived {
        let chipCounts: [QueueFilter: Int]
        /// No pipeline row and no quiet memo at all (the empty-state test).
        let hasNoQuietMemos: Bool
        /// The pipeline rows as drawn (sorted, quiet local takes out).
        let queueRowFiles: [PipelineFile]
        /// Every row as drawn, quiet notes included, in the active sort.
        let entries: [SidebarEntry]
        let orderedIDs: [String]
        let displayedIDs: [String]
        /// Day-grouped entries; one flat "" bucket under Title sort.
        let groups: [(title: String, items: [SidebarEntry])]
    }

    // MARK: - Counters (read by tests)

    /// Observation tick: the sidebar's body reads this, so a tracked change re-evaluates it.
    private(set) var tick = 0
    @ObservationIgnored private(set) var baseBuilds = 0
    @ObservationIgnored private(set) var derivedBuilds = 0
    /// Passes over the file + memo corpus (one per base build).
    @ObservationIgnored private(set) var corpusScans = 0
    @ObservationIgnored private(set) var backlinkScans = 0
    /// Notes whose search text was lowercased (one per note per note-version).
    @ObservationIgnored private(set) var preparedBuilds = 0

    // MARK: - State

    private struct Base {
        let generation: Int
        let chipCounts: [QueueFilter: Int]
        let stranded: [Memo]
        let unpipelined: [Memo]
        let lockedQuiet: [Memo]
        /// Fading, unrated memos with no pipeline row: they join the list only while searching.
        let fadingHits: [Memo]
    }
    private struct BaseKey: Equatable {
        var files: Int, memos: Int, version: Int, backlinked: Int, added: Int, processed: Int, hour: Int
    }
    private struct DerivedKey: Equatable {
        var generation: Int, params: Params, day: Date
    }
    private struct Fingerprint: Equatable {
        var transcriptBytes: Int?
        var title: String?
        var summary: String?
        var tags: [String]
        var extra: Int?          // OCR / annotation size
        var metadataBytes: Int?
        var sharedBytes: Int?
        var locked: Bool
        var stamp: Date?
    }
    private struct PreparedEntry {
        let fingerprint: Fingerprint
        let prepared: PreparedNoteSearch
    }

    @ObservationIgnored private var base: Base?
    @ObservationIgnored private var baseKey: BaseKey?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var derivedCache: (key: DerivedKey, value: Derived)?
    @ObservationIgnored private var preparedFiles: [String: PreparedEntry] = [:]
    @ObservationIgnored private var preparedMemos: [UUID: PreparedEntry] = [:]
    @ObservationIgnored private let dirty = DirtyBox()
    @ObservationIgnored private var tickScheduled = false

    private final class DirtyBox: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = true
        var isDirty: Bool { lock.lock(); defer { lock.unlock() }; return flag }
        func mark() { lock.lock(); flag = true; lock.unlock() }
        func clear() { lock.lock(); flag = false; lock.unlock() }
    }

    var isDirty: Bool { dirty.isDirty }

    /// Forget everything (tests; the next call rebuilds).
    func invalidate() {
        dirty.mark()
        base = nil
        derivedCache = nil
    }

    /// Run `body`; the first change to anything it read dirties the cache and re-evaluates the
    /// sidebar. Synchronous mark (the next body pass must see it), coalesced tick.
    private func tracked<T>(_ body: () -> T) -> T {
        let box = dirty
        return withObservationTracking(body, onChange: { [weak self] in
            box.mark()
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.scheduleTick() } }
        })
    }

    private func scheduleTick() {
        guard !tickScheduled else { return }
        tickScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tickScheduled = false
                self.tick &+= 1
            }
        }
    }

    // MARK: - The two levels

    func derived(_ i: Inputs, params: Params,
                 fileTitle: (PipelineFile) -> String,
                 entryTitle: (SidebarEntry) -> String,
                 dayLabel: (Date) -> String) -> Derived {
        _ = tick   // the body that called this re-evaluates when a tracked read changes
        let b = ensureBase(i)
        let day = Calendar.current.startOfDay(for: i.now)
        let key = DerivedKey(generation: b.generation, params: params, day: day)
        if let c = derivedCache, c.key == key, !dirty.isDirty { return c.value }
        derivedBuilds += 1
        let value = tracked { buildDerived(i, base: b, params: params, fileTitle: fileTitle,
                                           entryTitle: entryTitle, dayLabel: dayLabel) }
        derivedCache = (key, value)
        return value
    }

    private func ensureBase(_ i: Inputs) -> Base {
        var fh = Hasher()
        for f in i.files { fh.combine(ObjectIdentifier(f)) }
        var mh = Hasher()
        for m in i.memos { mh.combine(ObjectIdentifier(m)) }
        let key = BaseKey(files: fh.finalize() &+ i.files.count, memos: mh.finalize() &+ i.memos.count,
                          version: i.memoVersion, backlinked: i.backlinked?.count ?? -1,
                          added: i.addedAtByID.count, processed: i.processedIDs.count,
                          hour: Int(i.now.timeIntervalSinceReferenceDate / 3600))
        if let b = base, key == baseKey, !dirty.isDirty { return b }
        dirty.clear()
        generation += 1
        baseBuilds += 1
        corpusScans += 1
        let built = tracked { buildBase(i) }
        base = Base(generation: generation, chipCounts: built.chipCounts, stranded: built.stranded,
                    unpipelined: built.unpipelined, lockedQuiet: built.lockedQuiet, fadingHits: built.fadingHits)
        baseKey = key
        derivedCache = nil
        return base!
    }

    private func buildBase(_ i: Inputs) -> Base {
        var backlinked = i.backlinked
        if backlinked == nil {
            backlinkScans += 1
            backlinked = MemoLifecycle.backlinkedIDs(in: i.memos)
        }
        let bl = backlinked ?? []
        let stranded = WayOutRules.stranded(memos: i.memos, files: i.files)
        let quiet = WayOutRules.quietSplit(memos: i.memos, files: i.files, backlinked: bl, now: i.now)
        var f = MacListFilter(addedAtByID: i.addedAtByID, processedIDs: i.processedIDs)
        func count(_ chip: QueueFilter) -> Int {
            f.chip = chip
            return i.files.filter { f.inChip($0) }.count + stranded.filter { f.inChip($0) }.count
        }
        let counts = NotesListModel.chipCounts(needsWork: count(.needsWork), done: count(.done),
                                               notRated: ProcessPile.unrated(memos: i.memos).count)
        let ingested = Set(i.files.compactMap { UUID(uuidString: $0.id) })
        let fading = MemoLifecycle.partition(i.memos, backlinked: bl, now: i.now).fading.filter {
            !NoteConsent.isRated($0) && !ingested.contains($0.id)
        }
        return Base(generation: 0, chipCounts: counts, stranded: stranded, unpipelined: quiet.unpipelined,
                    lockedQuiet: quiet.lockedQuiet, fadingHits: fading)
    }

    private func buildDerived(_ i: Inputs, base b: Base, params p: Params,
                              fileTitle: (PipelineFile) -> String,
                              entryTitle: (SidebarEntry) -> String,
                              dayLabel: (Date) -> String) -> Derived {
        let unlocked = p.unlocked
        let filter = MacListFilter(chip: p.chip, query: p.query, from: p.from, to: p.to,
                                   dateField: p.dateField, addedAtByID: i.addedAtByID,
                                   isUnlocked: { unlocked.contains($0) }, processedIDs: i.processedIDs)
        let searching = NotesListModel.isSearching(p.query)
        let q = NoteVisibility.normalizedQuery(p.query)

        let fileHit: (PipelineFile) -> Bool = searching
            ? { [unowned self] f in self.prepared(f).matches(normalizedQuery: q, unlockedThisSession: unlocked.contains(f.id)) }
            : { _ in true }
        let memoHit: (Memo) -> Bool = searching
            ? { [unowned self] m in self.prepared(m).matches(normalizedQuery: q, unlockedThisSession: unlocked.contains(m.id.uuidString)) }
            : { _ in true }

        // Title sort evaluates the title per comparison; read it once per row instead.
        var fileTitles: [String: String] = [:]
        if p.sort == .title { for f in i.files { fileTitles[f.id] = fileTitle(f) } }
        let sortedFiles = filter.sort(i.files.filter { fileHit($0) && filter.passesFilter($0) }, by: p.sort,
                                      title: { fileTitles[$0.id] ?? fileTitle($0) })
        let queueRowFiles = sortedFiles.filter { !WayOutRules.isQuietLocalTake($0) }

        let memoRows = NotesListModel.listRows(
            live: b.stranded + b.unpipelined + b.lockedQuiet, fading: b.fadingHits, searching: searching,
            matchesSearch: memoHit, passesFilter: { filter.passesFilter($0) })

        var out: [SidebarEntry] = queueRowFiles.map { .file($0) }
        out.append(contentsOf: memoRows.map { .memo($0) })
        var entryTitles: [String: String] = [:]
        if p.sort == .title { for e in out { entryTitles[e.id] = entryTitle(e) } }
        let entries = filter.sort(out, by: p.sort, title: { entryTitles[$0.id] ?? entryTitle($0) })

        let groups: [(title: String, items: [SidebarEntry])] = p.sort == .title
            ? [(title: "", items: entries)]
            : NotesListModel.dateGroups(entries, date: { $0.groupDate(field: p.dateField, addedAtByID: i.addedAtByID) },
                                        ascending: p.sort == .oldest, label: dayLabel)
        // D197: the sections follow the picked date (Recorded by default) while Newest still sorts
        // on the added day, so the drawn order is the groups' order, not `entries`'. The ⇧-click
        // range and the selectable set read that drawn order.
        let drawn = groups.flatMap(\.items)
        let queueIDs = Set(queueRowFiles.map(\.id))
        return Derived(
            chipCounts: b.chipCounts,
            hasNoQuietMemos: i.files.isEmpty && b.unpipelined.isEmpty,
            queueRowFiles: queueRowFiles,
            entries: entries,
            orderedIDs: drawn.compactMap { e in
                if case .file(let f) = e, queueIDs.contains(f.id) { return f.id }
                return nil
            },
            displayedIDs: drawn.map { e in
                switch e {
                case .file(let f): return f.id
                case .memo(let m): return m.id.uuidString
                }
            },
            groups: groups)
    }

    // MARK: - Prepared search text (M11 / S1)

    private func prepared(_ f: PipelineFile) -> PreparedNoteSearch {
        let fp = Fingerprint(transcriptBytes: f.transcript?.utf8.count, title: f.enhancedTitle,
                             summary: f.enhancedSummary, tags: f.tags,
                             extra: f.imageOCRText?.utf8.count, metadataBytes: f.audioMetadataJSON?.count,
                             sharedBytes: nil, locked: f.locked, stamp: nil)
        if let e = preparedFiles[f.id], e.fingerprint == fp { return e.prepared }
        preparedBuilds += 1
        let p = PreparedNoteSearch(f.noteSearchSnapshot(unlockedThisSession: false))
        preparedFiles[f.id] = PreparedEntry(fingerprint: fp, prepared: p)
        return p
    }

    private func prepared(_ m: Memo) -> PreparedNoteSearch {
        let fp = Fingerprint(transcriptBytes: m.transcript?.utf8.count, title: m.title, summary: nil, tags: m.tags,
                             extra: m.annotationText?.utf8.count, metadataBytes: m.metadataData?.count,
                             sharedBytes: m.sharedContentData?.count, locked: m.locked, stamp: m.lastEditedAt)
        if let e = preparedMemos[m.id], e.fingerprint == fp { return e.prepared }
        preparedBuilds += 1
        let p = PreparedNoteSearch(m.noteSearchSnapshot(unlockedThisSession: false))
        preparedMemos[m.id] = PreparedEntry(fingerprint: fp, prepared: p)
        return p
    }
}

/// Q361 (M9): a row's built card content, kept per note VERSION. The row's snippet is a
/// regex pass over the whole body (an hour-long transcript is 50-100 KB); `QueueRowView.body`
/// re-ran it on every hover in/out and every selection change. Build once per (id, version).
@MainActor
final class MacRowSnippetCache {
    static let shared = MacRowSnippetCache()
    private var entries: [String: (version: Int, value: Any)] = [:]
    private(set) var builds = 0

    func value<V>(id: String, version: Int, build: () -> V) -> V {
        if let e = entries[id], e.version == version, let v = e.value as? V { return v }
        builds += 1
        if entries.count > 6_000 { entries.removeAll(keepingCapacity: true) }   // bounded: a rebuild is only a miss
        let v = build()
        entries[id] = (version, v)
        return v
    }
}
