import XCTest
@testable import SkriftMobile

/// Q315 — the Notes list's derived data is a cached model: a body pass with an unchanged memo set
/// does not rebuild rows, a search keystroke does not re-lowercase unchanged notes, and the cached
/// path gives exactly the rows the uncached path (`MemosListView.listRows` + sort) gives.
/// Synthetic notes only; no store (plain `@Model` instances observe and mutate fine detached).
@MainActor
final class ListDerivedCacheTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private struct Corpus {
        var memos: [Memo]
        var enhancements: [MemoEnhancement]
    }

    /// 40 notes: some fading (old, done, unrated), some rated, one locked, one backlinked target,
    /// a few with a polish title / summary, "morning" in various places.
    private func corpus() -> Corpus {
        var memos: [Memo] = []
        for i in 0..<40 {
            let age = Double(i % 8) * 9 * 86_400            // 0 ... 63 days old
            let m = Memo(audioFilename: "m\(i).m4a", duration: Double(30 + i * 7),
                         recordedAt: now.addingTimeInterval(-age - Double(i) * 60),
                         tags: i % 5 == 0 ? ["garden", "morning-pages"] : [],
                         title: i % 4 == 0 ? "Note \(i) about the Pump" : nil,
                         transcript: i % 3 == 0 ? "Morning walk number \(i) and the flamingo" : "Quiet words \(i) about irrigation",
                         transcriptStatus: .done,
                         significance: i % 6 == 0 ? 0.7 : 0,
                         createdAt: now.addingTimeInterval(-age - Double(i)))
            memos.append(m)
        }
        memos[7].locked = true
        memos[7].title = "Locked ledger"
        memos[7].transcript = "secret morning plans"
        memos[11].transcript = "see [[memo:\(memos[13].id.uuidString)|thirteen]] for the morning"
        var enh: [MemoEnhancement] = []
        enh.append(MemoEnhancement(memoID: memos[2].id, copyedit: "Polished.", title: "Zenith Plan",
                                   summary: "gist about mornings", processedAt: now))
        enh.append(MemoEnhancement(memoID: memos[5].id, title: "Generated  ", summary: ""))
        return Corpus(memos: memos, enhancements: enh)
    }

    private func cache() -> ListDerivedCache { ListDerivedCache() }

    private func base(_ c: ListDerivedCache, _ k: Corpus, version: Int = 0, now: Date? = nil,
                      allowStale: Bool = false) -> ListDerivedCache.ListBase {
        c.base(rawMemos: k.memos, enhancements: k.enhancements, externalVersion: version,
               now: now ?? self.now, allowStale: allowStale)
    }

    private func params(_ search: String = "", chip: QueueFilter = .all, sort: MemoSort = .added,
                        filter: MemoFilter = MemoFilter(), unlocked: Set<String> = []) -> ListDerivedCache.Params {
        .init(search: search, chip: chip, filter: filter, sort: sort, unlocked: unlocked)
    }

    private func ids(_ d: NotesListDerived) -> [UUID] { d.groups.flatMap { $0.memos.map(\.id) } }

    /// The pre-cache path, run straight through the shared rule.
    private func uncached(_ k: Corpus, _ p: ListDerivedCache.Params) -> [UUID] {
        let copyedits = Backlinks.copyeditsByMemoID(k.enhancements)
        let backlinked = MemoLifecycle.backlinkedIDs(in: k.memos, copyedits: copyedits)
        let split = MemoLifecycle.partition(k.memos, backlinked: backlinked, now: now)
        let enhanced = Set(k.enhancements.filter(\.isProcessed).map(\.memoID))
        let polish: [UUID: (title: String, summary: String)] = NotesListModel.isSearching(p.search)
            ? Dictionary(k.enhancements.map { ($0.memoID, ($0.title, $0.summary)) }, uniquingKeysWith: { a, _ in a })
            : [:]
        return MemosListView.listRows(lifecycle: split, search: p.search, chip: p.chip, filter: p.filter,
                                      enhanced: enhanced, polish: polish,
                                      isUnlocked: { p.unlocked.contains($0) })
            .sorted { MemosListView.isOrdered($0, $1, by: p.sort) }
            .map(\.id)
    }

    // MARK: - A body pass with an unchanged memo set does not rebuild

    func testUnchangedMemoSetDoesNotRebuildRows() {
        let k = corpus(), c = cache()
        let b1 = base(c, k)
        let d1 = c.derived(base: b1, params: params(), related: [])
        for _ in 0..<5 {                                   // five more body passes, nothing changed
            let b = base(c, k)
            _ = c.derived(base: b, params: params(), related: [])
        }
        XCTAssertEqual(c.baseBuilds, 1)
        XCTAssertEqual(c.derivedBuilds, 1)
        XCTAssertEqual(ids(c.derived(base: b1, params: params(), related: [])), ids(d1))
    }

    func testChangingSortOrChipRebuildsOnlyTheDerivedLevel() {
        let k = corpus(), c = cache()
        let b = base(c, k)
        _ = c.derived(base: b, params: params(), related: [])
        _ = c.derived(base: base(c, k), params: params(sort: .longest), related: [])
        _ = c.derived(base: base(c, k), params: params(chip: .needsWork), related: [])
        XCTAssertEqual(c.baseBuilds, 1)
        XCTAssertEqual(c.derivedBuilds, 3)
    }

    func testAPropertyTheBaseReadDirtiesTheCacheAndTheNextPassRebuilds() {
        let k = corpus(), c = cache()
        let before = base(c, k)
        XCTAssertFalse(c.isDirty)
        XCTAssertEqual(before.chipCounts[.notRated], k.memos.filter { !NoteConsent.isRated($0) && !$0.locked }.count)

        k.memos[1].significance = 0.7                      // rate an unrated note
        XCTAssertTrue(c.isDirty, "the first change to a property the build read must dirty the cache at once")
        let after = base(c, k)
        XCTAssertEqual(c.baseBuilds, 2)
        XCTAssertEqual(after.chipCounts[.notRated], (before.chipCounts[.notRated] ?? 0) - 1)
    }

    func testARepositoryVersionBumpOrTheClockHourRebuilds() {
        let k = corpus(), c = cache()
        _ = base(c, k, version: 1)
        _ = base(c, k, version: 1)
        XCTAssertEqual(c.baseBuilds, 1)
        _ = base(c, k, version: 2)                         // save() / CloudKit import
        XCTAssertEqual(c.baseBuilds, 2)
        _ = base(c, k, version: 2, now: now.addingTimeInterval(2 * 3600))   // fading clock moved
        XCTAssertEqual(c.baseBuilds, 3)
    }

    func testCoveredListKeepsTheBaseOnAPropertyChangeButNeverOnAMembershipChange() {
        var k = corpus()
        let c = cache()
        _ = base(c, k)
        k.memos[3].significance = 0.7
        _ = base(c, k, allowStale: true)
        XCTAssertEqual(c.baseBuilds, 1, "a pure property change waits for the pop")
        _ = base(c, k)
        XCTAssertEqual(c.baseBuilds, 2, "and lands when the list is uncovered")

        k.memos.removeLast()                               // a memo left the query (deleted / trashed)
        let b = base(c, k, allowStale: true)
        XCTAssertEqual(c.baseBuilds, 3, "membership never waits: a deleted model must not render")
        XCTAssertEqual(b.memos.count, 39)
    }

    // MARK: - A search keystroke does not re-lowercase unchanged memos

    func testKeystrokesDoNotRelowercaseUnchangedNotes() {
        let k = corpus(), c = cache()
        let b = base(c, k)
        _ = c.derived(base: b, params: params("m"), related: [])
        let afterFirst = c.preparedBuilds
        XCTAssertGreaterThan(afterFirst, 0)
        XCTAssertLessThanOrEqual(afterFirst, k.memos.count)
        for q in ["mo", "mor", "morn", "morni", "mornin", "morning", "morning ", "morning"] {
            _ = c.derived(base: base(c, k), params: params(q), related: [])
        }
        XCTAssertEqual(c.preparedBuilds, afterFirst, "typing the rest of the word lowercases nothing new")

        // One note changes: only that note is lowercased again.
        k.memos[4].transcript = "A completely different body, still about the morning light"
        _ = c.derived(base: base(c, k), params: params("morning"), related: [])
        XCTAssertEqual(c.preparedBuilds, afterFirst + 1)
    }

    func testNarrowingStartsFromThePreviousHitsAndBackspaceWidensAgain() {
        let k = corpus(), c = cache()
        let wide = ids(c.derived(base: base(c, k), params: params("mor"), related: []))
        let narrow = ids(c.derived(base: base(c, k), params: params("morning"), related: []))
        XCTAssertTrue(Set(narrow).isSubset(of: Set(wide)))
        XCTAssertLessThan(narrow.count, wide.count)
        let widened = ids(c.derived(base: base(c, k), params: params("mor"), related: []))
        XCTAssertEqual(widened, wide, "backspacing must bring the wider hit set back")
    }

    // MARK: - Same rows as the uncached path

    func testCachedRowsEqualTheUncachedRowsForAFixedCorpus() {
        let k = corpus(), c = cache()
        let queries = ["", "m", "mo", "mor", "morn", "morning", "morning ", "pump", "ZENITH", "gist", "generated",
                       "ledger", "secret", "flamingo", "zzz-no-hit", "thirteen", "irrigation", "garden"]
        let chips: [QueueFilter] = [.all, .needsWork, .done, .notRated]
        let sorts: [MemoSort] = [.added, .edited, .recent, .oldest, .longest]
        let unlockSets: [Set<String>] = [[], [k.memos[7].id.uuidString]]
        var compared = 0
        for unlocked in unlockSets {
            for q in queries {                              // in typing order, so narrowing is exercised
                for chip in chips {
                    for sort in sorts {
                        let p = params(q, chip: chip, sort: sort, unlocked: unlocked)
                        let got = ids(c.derived(base: base(c, k), params: p, related: []))
                        XCTAssertEqual(got, uncached(k, p), "q=\(q) chip=\(chip) sort=\(sort) unlocked=\(unlocked.count)")
                        compared += 1
                    }
                }
            }
        }
        XCTAssertEqual(compared, 2 * queries.count * chips.count * sorts.count)
        XCTAssertEqual(c.baseBuilds, 1)
    }

    func testDateFilterAndRelatedRowsMatchTheSharedRules() {
        let k = corpus(), c = cache()
        var f = MemoFilter()
        f.from = now.addingTimeInterval(-20 * 86_400)
        let p = params("", filter: f)
        XCTAssertEqual(ids(c.derived(base: base(c, k), params: p, related: [])), uncached(k, p))

        // Related: a hit already shown is dropped, a hidden locked hit never surfaces.
        let shown = k.memos[0], other = k.memos[9], locked = k.memos[7]
        let d = c.derived(base: base(c, k), params: params(), related: [shown, other, locked])
        XCTAssertEqual(d.related.map(\.id), [])             // all three are already in the unfiltered list
        let d2 = c.derived(base: base(c, k), params: params("pump"), related: [other, locked, shown])
        XCTAssertFalse(d2.related.contains { $0.id == locked.id }, "a hidden locked note never surfaces")
    }

    // MARK: - The prepared matcher is the shared matcher

    func testPreparedMatcherAgreesWithTheSnapshotMatcher() {
        let k = corpus()
        let queries = ["", "  ", "morning", "MORNING", "pump", "ledger", "secret", "garden", "morning-pages",
                       "no such thing", " flamingo "]
        for m in k.memos {
            for unlocked in [false, true] {
                let snap = m.noteSearchSnapshot(unlockedThisSession: unlocked, enhancedTitle: "Zenith Plan", summary: "gist")
                let prepared = PreparedNoteSearch(snap)
                for q in queries {
                    XCTAssertEqual(prepared.matches(normalizedQuery: NoteVisibility.normalizedQuery(q), unlockedThisSession: unlocked),
                                   NoteSearch.matches(query: q, snap), "q=\(q) locked=\(m.locked) unlocked=\(unlocked)")
                }
            }
        }
    }

    func testEmptyQueryNeverBuildsASnapshot() {
        // The cheap exit: `Memo.matches` with no query is true without decoding anything.
        let m = Memo(title: "x", transcript: "y")
        XCTAssertTrue(m.matches(query: ""))
        XCTAssertTrue(m.matches(query: "   "))
        XCTAssertFalse(m.matches(query: "zzz"))
    }
}
