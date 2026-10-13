import XCTest

/// Q361 / D186 / D191 / C279 (`plan/perf2/f-mac-ui.md` M1 M2 M3 M9 M11): the Mac sidebar's rows,
/// chip counts, quiet/stranded sets, sort and day groups come from ONE cache that is rebuilt when
/// the memo set changes, not on every `SidebarView.body` pass (every click, recording-meter tick
/// and run-progress tick). Mirrors the phone's `ListDerivedCacheTests` (Q315).
///
/// Counters, not clocks: a body pass with an unchanged memo set does no corpus scan; a search
/// keystroke does not re-lowercase unchanged notes; the cached rows equal the uncached path
/// (`PipelineFile`/`Memo` through `MacListFilter` + `WayOutRules` + `MemoLifecycle`) on the corpus.
/// Synthetic notes only, no store.
@MainActor
final class MacListWorkTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private struct Corpus {
        var files: [PipelineFile]
        var memos: [Memo]
        var backlinked: Set<UUID>
        var addedAt: [String: Date]
        var processed: Set<UUID>
    }

    /// 30 pipeline rows (some polished, one locked, one with a place in its metadata blob),
    /// 20 memos: rated stranded, unrated quiet, locked quiet, an old fading one, a backlinked one.
    private func corpus() -> Corpus {
        var files: [PipelineFile] = []
        var memos: [Memo] = []
        for i in 0..<30 {
            let id = UUID()
            let f = PipelineFile(id: id.uuidString, filename: "rec\(i).m4a", path: "/tmp/x", size: 1, sourceType: .audio,
                                 uploadedAt: now.addingTimeInterval(-Double(i) * 3_600 - 17))
            f.transcript = i % 3 == 0 ? "Morning walk number \(i) and the flamingo" : "Quiet words \(i) about irrigation"
            f.enhancedTitle = i % 4 == 0 ? "Pump plan \(i)" : nil
            f.enhancedSummary = i % 5 == 0 ? "gist about mornings" : nil
            if i % 6 == 0 { f.enhanceStatus = .done }
            f.locked = i == 7
            if i == 9 { f.audioMetadataJSON = Data(#"{"location":{"placeName":"Lisbon harbour"}}"#.utf8) }
            files.append(f)
            // every 3rd pipeline row also has a memo with the SAME id (a synced, ingested note)
            if i % 3 == 0 {
                let m = Memo(id: id, audioFilename: "rec\(i).m4a", recordedAt: f.uploadedAt,
                             transcript: f.transcript, transcriptStatus: .done)
                m.significance = 0.6
                memos.append(m)
            }
        }
        for j in 0..<20 {
            let age = Double(j % 5) * 20 * 86_400            // 0 ... 80 days: the old ones fade
            let m = Memo(audioFilename: "q\(j).m4a", recordedAt: now.addingTimeInterval(-age - Double(j) * 90),
                         transcript: j % 2 == 0 ? "Morning quiet note \(j)" : "Garden words \(j) [[memo:\(memos[0].id.uuidString)|first]]",
                         transcriptStatus: .done)
            m.significance = j % 4 == 0 ? 0.7 : 0                 // 0.7 = rated + no row = stranded
            m.locked = j == 3
            memos.append(m)
        }
        let backlinked = MemoLifecycle.backlinkedIDs(in: memos)
        let added = MacListFilter.addedDates(memos: memos)
        return Corpus(files: files, memos: memos, backlinked: backlinked, addedAt: added, processed: [])
    }

    private func inputs(_ k: Corpus, version: Int = 1) -> MacListDerivedCache.Inputs {
        .init(files: k.files, memos: k.memos, memoVersion: version, backlinked: k.backlinked,
              addedAtByID: k.addedAt, processedIDs: k.processed, now: now)
    }

    private func derive(_ c: MacListDerivedCache, _ k: Corpus, _ p: MacListDerivedCache.Params = .init(),
                        version: Int = 1) -> MacListDerivedCache.Derived {
        c.derived(inputs(k, version: version), params: p,
                  fileTitle: { $0.enhancedTitle ?? $0.filename },
                  entryTitle: { e in
                      switch e {
                      case .file(let f): return f.enhancedTitle ?? f.filename
                      case .memo(let m): return WayOutRules.displayTitle(m)
                      }
                  },
                  dayLabel: { MemoDate.group($0) })
    }

    /// The pre-cache path, run straight through the shared rules (what `SidebarView.entries` did).
    private func uncachedIDs(_ k: Corpus, _ p: MacListDerivedCache.Params) -> [String] {
        var f = MacListFilter(chip: p.chip, query: p.query, from: p.from, to: p.to, dateField: p.dateField,
                              addedAtByID: k.addedAt, isUnlocked: { p.unlocked.contains($0) }, processedIDs: k.processed)
        f.chip = p.chip
        let title: (PipelineFile) -> String = { $0.enhancedTitle ?? $0.filename }
        let sortedFiles = f.sort(f.fileRows(k.files), by: p.sort, title: title)
        let queueFiles = sortedFiles.filter { !WayOutRules.isQuietLocalTake($0) }
        var out: [SidebarEntry] = queueFiles.map { .file($0) }
        out.append(contentsOf: f.memoRows(memos: k.memos, files: k.files, now: now).map { .memo($0) })
        return f.sort(out, by: p.sort, title: { e in
            switch e {
            case .file(let x): return title(x)
            case .memo(let m): return WayOutRules.displayTitle(m)
            }
        }).map(\.id)
    }

    // MARK: - A body pass with an unchanged memo set does no corpus scan

    func testUnchangedMemoSetDoesNoCorpusScan() {
        let k = corpus(), c = MacListDerivedCache()
        let d1 = derive(c, k)
        XCTAssertEqual(c.baseBuilds, 1)
        let scansAfterFirst = c.corpusScans
        XCTAssertGreaterThan(scansAfterFirst, 0, "the first pass has to scan the corpus once")
        // 200 body passes (clicks, recording-meter ticks, run-progress ticks): same set, same params.
        for _ in 0..<200 { _ = derive(c, k) }
        XCTAssertEqual(c.baseBuilds, 1, "an unchanged memo set must not rebuild the base")
        XCTAssertEqual(c.derivedBuilds, 1, "unchanged params must not rebuild the rows")
        XCTAssertEqual(c.corpusScans, scansAfterFirst, "a body pass must not scan the corpus")
        XCTAssertEqual(c.backlinkScans, 0, "the sidebar hands the cached backlinked set in; nothing rescans transcripts")
        XCTAssertEqual(d1.entries.map(\.id), derive(c, k).entries.map(\.id))
    }

    func testChipSwitchReusesTheBase() {
        let k = corpus(), c = MacListDerivedCache()
        _ = derive(c, k)
        let scans = c.corpusScans
        for chip in QueueFilter.allCases { _ = derive(c, k, .init(chip: chip)) }
        XCTAssertEqual(c.baseBuilds, 1, "a filter change is not a memo-set change")
        XCTAssertEqual(c.corpusScans, scans)
    }

    func testChangedMemoSetRebuildsOnce() {
        var k = corpus(); let c = MacListDerivedCache()
        _ = derive(c, k)
        k.memos.removeLast()
        for _ in 0..<20 { _ = derive(c, k, version: 2) }
        XCTAssertEqual(c.baseBuilds, 2)
    }

    func testChangedFilePropertyRebuildsBase() {
        let k = corpus(), c = MacListDerivedCache()
        let before = derive(c, k).chipCounts[.done]
        _ = derive(c, k)
        XCTAssertEqual(c.baseBuilds, 1)
        // A polish finishing on a row changes Done; no list input changed, only the model did.
        let target = k.files.first { $0.enhanceStatus != .done && !$0.locked }!
        target.enhanceStatus = .done
        XCTAssertTrue(c.isDirty, "observation must mark the base stale")
        let after = derive(c, k).chipCounts[.done]
        XCTAssertEqual(after, (before ?? 0) + 1)
        XCTAssertEqual(c.baseBuilds, 2)
    }

    // MARK: - A search keystroke does not re-lowercase unchanged notes

    func testSearchKeystrokeDoesNotReLowercaseUnchangedNotes() {
        let k = corpus(), c = MacListDerivedCache()
        _ = derive(c, k, .init(query: "m"))
        let prepared = c.preparedBuilds
        XCTAssertGreaterThan(prepared, 0)
        XCTAssertLessThanOrEqual(prepared, k.files.count + k.memos.count)
        for q in ["mo", "mor", "morn", "morni", "mornin", "morning"] {
            _ = derive(c, k, .init(query: q))
        }
        XCTAssertEqual(c.preparedBuilds, prepared, "typing must not re-lowercase notes that did not change")
        XCTAssertEqual(c.baseBuilds, 1)
    }

    func testEditedNoteIsRePreparedAlone() {
        let k = corpus(), c = MacListDerivedCache()
        _ = derive(c, k, .init(query: "flamingo"))
        let prepared = c.preparedBuilds
        k.files[1].transcript = "A brand new flamingo sentence for the second row"
        _ = derive(c, k, .init(query: "flamingos"))
        _ = derive(c, k, .init(query: "flamingo"))
        XCTAssertEqual(c.preparedBuilds, prepared + 1, "only the edited note is prepared again")
        XCTAssertTrue(derive(c, k, .init(query: "flamingo")).entries.contains { $0.id == "pf-" + k.files[1].id })
    }

    // MARK: - Results equal the uncached path

    func testCachedRowsEqualUncachedRowsOnTheCorpus() {
        let k = corpus(), c = MacListDerivedCache()
        let unlockedSets: [Set<String>] = [[], [k.files[7].id]]
        var checked = 0
        for chip in QueueFilter.allCases {
            for sort in SidebarSort.allCases {
                for query in ["", "morning", "  Flamingo ", "lisbon", "garden", "zzz-nothing", "pump"] {
                    for unlocked in unlockedSets {
                        let p = MacListDerivedCache.Params(chip: chip, query: query, sort: sort, unlocked: unlocked)
                        XCTAssertEqual(derive(c, k, p).entries.map(\.id), uncachedIDs(k, p),
                                       "chip \(chip) sort \(sort) query '\(query)'")
                        checked += 1
                    }
                }
            }
        }
        XCTAssertEqual(c.baseBuilds, 1)
        XCTAssertGreaterThan(checked, 100)
    }

    func testChipCountsEqualTheUncachedFormula() {
        let k = corpus(), c = MacListDerivedCache()
        let counts = derive(c, k).chipCounts
        var f = MacListFilter(addedAtByID: k.addedAt, processedIDs: k.processed)
        let stranded = WayOutRules.stranded(memos: k.memos, files: k.files)
        func count(_ chip: QueueFilter) -> Int {
            f.chip = chip
            return k.files.filter { f.inChip($0) }.count + stranded.filter { f.inChip($0) }.count
        }
        XCTAssertEqual(counts[.needsWork], count(.needsWork))
        XCTAssertEqual(counts[.done], count(.done))
        XCTAssertEqual(counts[.notRated], ProcessPile.unrated(memos: k.memos).count)
    }

    func testQuietRowsWithHandedInBacklinkSetEqualTheScanningOverload() {
        let k = corpus()
        XCTAssertEqual(WayOutRules.unpipelined(memos: k.memos, files: k.files, backlinked: k.backlinked, now: now).map(\.id),
                       WayOutRules.unpipelined(memos: k.memos, files: k.files, now: now).map(\.id))
        XCTAssertEqual(WayOutRules.lockedQuiet(memos: k.memos, files: k.files, backlinked: k.backlinked, now: now).map(\.id),
                       WayOutRules.lockedQuiet(memos: k.memos, files: k.files, now: now).map(\.id))
        XCTAssertEqual(MacListFilter(chip: .all, query: "morning").memoRows(memos: k.memos, files: k.files, backlinked: k.backlinked, now: now).map(\.id),
                       MacListFilter(chip: .all, query: "morning").memoRows(memos: k.memos, files: k.files, now: now).map(\.id))
    }

    // MARK: - Snippets are built once per note version (M9)

    func testSnippetPlainIsStableAndOnlyReadsTheHead() {
        let body = String(repeating: "**Speaker 1:** hello [[Tiuri Hartog]] [[img_001]] ", count: 4_000)
        XCTAssertEqual(NoteSnippet.plain(body).prefix(60), NoteSnippet.plain(String(body.prefix(1_200))).prefix(60))
        XCTAssertEqual(NoteSnippet.plain("a [[memo:\(UUID().uuidString)|Pump]] **b** [[X|y]] [[Z]] [[img_2]]"), "a Pump b y Z ")
    }

    func testSnippetCacheBuildsOncePerNoteVersion() {
        let c = MacRowSnippetCache()
        var builds = 0
        for _ in 0..<50 { _ = c.value(id: "a", version: 1) { builds += 1; return "x" } }
        XCTAssertEqual(builds, 1)
        _ = c.value(id: "a", version: 2) { builds += 1; return "y" }
        XCTAssertEqual(builds, 2)
    }
}
