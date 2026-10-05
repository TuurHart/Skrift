import XCTest
@testable import SkriftMobile

/// Q322 — editing ONE note patches that note's row facts; it does not rebuild the whole list base,
/// and the patched base equals a full rebuild exactly. Synthetic notes only; no store.
extension ListDerivedCacheTests {

    private var q322Now: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    private func q322Corpus() -> (memos: [Memo], enhancements: [MemoEnhancement]) {
        var memos: [Memo] = []
        for i in 0..<40 {
            let age = Double(i % 8) * 9 * 86_400
            memos.append(Memo(audioFilename: "m\(i).m4a", duration: Double(30 + i),
                              recordedAt: q322Now.addingTimeInterval(-age - Double(i) * 60),
                              transcript: i % 3 == 0 ? "Morning walk \(i)" : "Quiet words \(i)",
                              transcriptStatus: .done, significance: i % 6 == 0 ? 0.7 : 0,
                              createdAt: q322Now.addingTimeInterval(-age - Double(i))))
        }
        memos[7].locked = true
        let enh = [MemoEnhancement(memoID: memos[6].id, copyedit: "Polished.", title: "Zenith", summary: "gist",
                                   processedAt: q322Now)]
        return (memos, enh)
    }

    private func q322Index(_ k: (memos: [Memo], enhancements: [MemoEnhancement])) -> BacklinkIndex {
        let copyedits = Backlinks.copyeditsByMemoID(k.enhancements)
        return BacklinkIndex.build(rows: k.memos.filter { $0.deletedAt == nil }.map {
            Backlinks.Row(id: $0.id, transcript: $0.transcript, copyedit: copyedits[$0.id])
        })
    }

    private func q322Base(_ c: ListDerivedCache, _ k: (memos: [Memo], enhancements: [MemoEnhancement]),
                          structure: Int = 0) -> ListDerivedCache.ListBase {
        c.base(rawMemos: k.memos, enhancements: k.enhancements, externalVersion: structure,
               now: q322Now, backlinks: q322Index(k))
    }

    /// A from-scratch build over the SAME current memo state.
    private func q322Full(_ k: (memos: [Memo], enhancements: [MemoEnhancement])) -> ListDerivedCache.ListBase {
        ListDerivedCache.buildBase(rawMemos: k.memos, enhancements: k.enhancements, now: q322Now, generation: 0,
                                   backlinks: q322Index(k))
    }

    private func q322AssertEqual(_ a: ListDerivedCache.ListBase, _ b: ListDerivedCache.ListBase,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.memos.map(\.id), b.memos.map(\.id), "memos", file: file, line: line)
        XCTAssertEqual(a.live.map(\.id), b.live.map(\.id), "live", file: file, line: line)
        XCTAssertEqual(a.fading.map(\.id), b.fading.map(\.id), "fading", file: file, line: line)
        XCTAssertEqual(a.processPile.map(\.id), b.processPile.map(\.id), "process pile", file: file, line: line)
        XCTAssertEqual(a.chipCounts, b.chipCounts, "chip counts", file: file, line: line)
        XCTAssertEqual(a.enhanced, b.enhanced, "enhanced", file: file, line: line)
        XCTAssertEqual(a.backlinked, b.backlinked, "backlinked", file: file, line: line)
        XCTAssertEqual(a.enhancedTitleByMemoID, b.enhancedTitleByMemoID, "titles", file: file, line: line)
    }

    func testEditingOneTranscriptRebuildsOneRowNotTheBase() {
        let k = q322Corpus(), c = ListDerivedCache()
        _ = q322Base(c, k)
        XCTAssertEqual(c.fullBuilds, 1)
        k.memos[12].transcript = "A body that was typed into just now"
        XCTAssertTrue(c.isDirty)
        let patched = q322Base(c, k)
        XCTAssertEqual(c.fullBuilds, 1, "the whole base was not rebuilt")
        XCTAssertEqual(c.rowPatches, 1)
        XCTAssertEqual(c.rowsRebuilt, 1, "one note's facts were re-read")
        XCTAssertEqual(patched.changedIDs, [k.memos[12].id])
        q322AssertEqual(patched, q322Full(k))
    }

    func testPatchedBaseEqualsAFullRebuildAcrossManyEdits() {
        let k = q322Corpus(), c = ListDerivedCache()
        _ = q322Base(c, k)
        // Each pass edits something the list reads; every patched base must equal a full rebuild,
        // which also proves the patched notes were re-tracked (the second edit of memo 18 patches again).
        let edits: [(String, () -> Void)] = [
            ("rate an unrated note", { k.memos[1].significance = 0.7 }),
            ("empty a rated note's body", { k.memos[6].transcript = "   " }),
            ("lock a note", { k.memos[2].locked = true }),
            ("trash a note", { k.memos[3].deletedAt = self.q322Now }),
            ("restore it", { k.memos[3].deletedAt = nil }),
            ("keep an old unrated note (leaves fading)", { k.memos[15].keptAt = self.q322Now }),
            ("edit memo 18", { k.memos[18].transcript = "first edit" }),
            ("edit memo 18 again", { k.memos[18].transcript = "second edit" }),
            ("two notes at once", { k.memos[9].significance = 0.7; k.memos[10].locked = true }),
        ]
        for (name, edit) in edits {
            edit()
            let patched = q322Base(c, k)
            q322AssertEqual(patched, q322Full(k))
            XCTAssertNotNil(patched.changedIDs, "\(name): should have been a patch")
        }
        XCTAssertEqual(c.fullBuilds, 1)
        XCTAssertEqual(c.rowPatches, edits.count)
    }

    func testAPassWithNothingDirtyBuildsNothing() {
        let k = q322Corpus(), c = ListDerivedCache()
        _ = q322Base(c, k)
        _ = q322Base(c, k)
        _ = q322Base(c, k)
        XCTAssertEqual(c.baseBuilds, 1)
        XCTAssertEqual(c.rowPatches, 0)
    }

    func testAChangedBacklinkSetRebuildsEverything() {
        let k = q322Corpus(), c = ListDerivedCache()
        _ = q322Base(c, k)
        // Memo 20 now links to memo 21: the linked set changed, so other notes may leave the fade clock.
        k.memos[20].transcript = "see \(MemoLinkSyntax.link(id: k.memos[21].id, title: "Old"))"
        c.backlinksArrived(q322Index(k))          // what the list does when the current index lands
        let b = q322Base(c, k)
        XCTAssertEqual(c.fullBuilds, 2, "a different backlink set is a whole-base change")
        XCTAssertTrue(b.backlinked.contains(k.memos[21].id))
        q322AssertEqual(b, q322Full(k))
    }

    func testASyncOrStructureVersionRebuildsEverything() {
        let k = q322Corpus(), c = ListDerivedCache()
        _ = q322Base(c, k, structure: 0)
        k.memos[4].transcript = "edited"
        _ = q322Base(c, k, structure: 1)
        XCTAssertEqual(c.fullBuilds, 2)
        XCTAssertEqual(c.rowPatches, 0)
    }

    func testAnEnhancementChangeRebuildsEverything() {
        let k = q322Corpus(), c = ListDerivedCache()
        _ = q322Base(c, k)
        k.enhancements[0].title = "A new generated title"
        let b = q322Base(c, k)
        XCTAssertEqual(c.fullBuilds, 2)
        XCTAssertEqual(b.enhancedTitleByMemoID[k.memos[6].id], "A new generated title")
    }

    func testDuplicateRowsAlwaysRebuildFully() {
        var k = q322Corpus()
        k.memos.append(Memo(audioFilename: "dup.m4a", recordedAt: q322Now, transcript: "dup", transcriptStatus: .done))
        k.memos[40].id = k.memos[0].id          // a duplicate id: the keeper can move on an edit
        let c = ListDerivedCache()
        _ = q322Base(c, k)
        k.memos[0].locked = true; k.memos[40].locked = true
        let b = q322Base(c, k)
        XCTAssertEqual(c.rowPatches, 0)
        XCTAssertEqual(c.fullBuilds, 2)
        q322AssertEqual(b, q322Full(k))
    }

    func testAPatchKeepsEveryOtherNotesSearchText() {
        let k = q322Corpus(), c = ListDerivedCache()
        func search(_ q: String) -> NotesListDerived {
            let p = ListDerivedCache.Params(search: q, chip: .all, filter: MemoFilter(), sort: .added, unlocked: [])
            return c.derived(base: q322Base(c, k), params: p, related: [])
        }
        _ = search("morning")
        let first = c.preparedBuilds
        XCTAssertGreaterThan(first, 0)
        k.memos[12].transcript = "Now it also says morning"
        let d = search("morning")
        XCTAssertEqual(c.rowPatches, 1)
        XCTAssertEqual(c.preparedBuilds, first + 1, "only the edited note's search text was lowercased again")
        XCTAssertTrue(d.groups.flatMap { $0.memos }.contains { $0.id == k.memos[12].id })
    }
}
