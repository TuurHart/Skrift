import XCTest
@testable import SkriftMobile

/// Q320 — the list's base rebuild reads the shared backlink index instead of rescanning every
/// transcript, and gets exactly the set `MemoLifecycle.backlinkedIDs` gets.
extension ListDerivedCacheTests {

    private func linkTo(_ id: UUID) -> String { MemoLinkSyntax.link(id: id, title: "Old thought") }

    private var q320Now: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    /// Fixed corpus: a target linked from a transcript, another linked ONLY from a Mac copy-edit,
    /// a third linked only by a TRASHED note, and a self-linking note.
    private func q320Corpus() -> (memos: [Memo], enhancements: [MemoEnhancement], targets: [UUID]) {
        let now = q320Now
        func make(_ text: String, _ minutes: Double) -> Memo {
            Memo(audioFilename: "x.m4a", recordedAt: now.addingTimeInterval(-minutes * 60),
                 transcript: text, transcriptStatus: .done)
        }
        let viaTranscript = make("target one", 100)
        let viaCopyedit = make("target two", 101)
        let viaTrashed = make("target three", 102)
        let untouched = make("nobody links here", 103)
        let a = make("see \(linkTo(viaTranscript.id))", 1)
        let b = make("just words", 2)
        let trashedLinker = make("old \(linkTo(viaTrashed.id))", 3)
        trashedLinker.deletedAt = now
        let selfLinker = make("placeholder", 4)
        selfLinker.transcript = "me \(linkTo(selfLinker.id))"
        let enh = [MemoEnhancement(memoID: b.id, copyedit: "polished \(linkTo(viaCopyedit.id))")]
        return ([viaTranscript, viaCopyedit, viaTrashed, untouched, a, b, trashedLinker, selfLinker], enh,
                [viaTranscript.id, viaCopyedit.id, viaTrashed.id, selfLinker.id])
    }

    /// The index exactly as `NotesRepository.backlinkIndex()` builds it: live notes only.
    private func q320Index(_ memos: [Memo], _ enhancements: [MemoEnhancement]) -> BacklinkIndex {
        let copyedits = Backlinks.copyeditsByMemoID(enhancements)
        return BacklinkIndex.build(rows: memos.filter { $0.deletedAt == nil }.map {
            Backlinks.Row(id: $0.id, transcript: $0.transcript, copyedit: copyedits[$0.id])
        })
    }

    func testTheRebuildReadsTheIndexAndEqualsTheScan() {
        let k = q320Corpus()
        let scanned = ListDerivedCache.buildBase(rawMemos: k.memos, enhancements: k.enhancements,
                                                 now: q320Now, generation: 1)
        let indexed = ListDerivedCache.buildBase(rawMemos: k.memos, enhancements: k.enhancements,
                                                 now: q320Now, generation: 1,
                                                 backlinks: q320Index(k.memos, k.enhancements))
        let expected = MemoLifecycle.backlinkedIDs(
            in: k.memos, copyedits: Backlinks.copyeditsByMemoID(k.enhancements))
        XCTAssertFalse(scanned.backlinkedFromIndex)
        XCTAssertTrue(indexed.backlinkedFromIndex)
        XCTAssertEqual(indexed.backlinked, expected)
        XCTAssertEqual(indexed.backlinked, scanned.backlinked)
        XCTAssertTrue(indexed.backlinked.contains(k.targets[0]))
        XCTAssertTrue(indexed.backlinked.contains(k.targets[1]), "a link only in the copy-edit counts")
        XCTAssertFalse(indexed.backlinked.contains(k.targets[2]), "a trashed linker does not count")
        XCTAssertTrue(indexed.backlinked.contains(k.targets[3]), "a self-link counts as linked")
        XCTAssertEqual(indexed.live.map(\.id), scanned.live.map(\.id))
        XCTAssertEqual(indexed.fading.map(\.id), scanned.fading.map(\.id))
    }

    func testASaveDoesNotRescanWhenAnIndexIsInHand() {
        let k = q320Corpus()
        let c = ListDerivedCache()
        let index = q320Index(k.memos, k.enhancements)
        _ = c.base(rawMemos: k.memos, enhancements: k.enhancements, externalVersion: 0,
                   now: q320Now, backlinks: index)
        let second = c.base(rawMemos: k.memos, enhancements: k.enhancements, externalVersion: 1,
                            now: q320Now, backlinks: index)
        XCTAssertEqual(c.baseBuilds, 2, "the version moved: the base rebuilds")
        XCTAssertTrue(second.backlinkedFromIndex, "and it read the index, not the transcripts")
    }

    func testAStaleIndexIsCorrectedWhenTheCurrentOneLands() {
        var k = q320Corpus()
        let stale = q320Index(k.memos, k.enhancements)
        // A new note links to the untouched one; the index in hand predates it.
        let untouched = k.memos[3]
        k.memos.append(Memo(audioFilename: "n.m4a", recordedAt: q320Now, transcript: "new \(linkTo(untouched.id))",
                            transcriptStatus: .done))
        let current = q320Index(k.memos, k.enhancements)
        let c = ListDerivedCache()
        let first = c.base(rawMemos: k.memos, enhancements: k.enhancements, externalVersion: 1,
                           now: q320Now, backlinks: stale)
        XCTAssertFalse(first.backlinked.contains(untouched.id), "the stale index does not know the new link yet")
        c.backlinksArrived(current)
        XCTAssertTrue(c.isDirty, "the landed index differs: the base is dirty")
        let fixed = c.base(rawMemos: k.memos, enhancements: k.enhancements, externalVersion: 1,
                           now: q320Now, backlinks: current)
        XCTAssertTrue(fixed.backlinked.contains(untouched.id))
        XCTAssertEqual(fixed.backlinked, MemoLifecycle.backlinkedIDs(
            in: k.memos, copyedits: Backlinks.copyeditsByMemoID(k.enhancements)))
        let builds = c.baseBuilds
        c.backlinksArrived(current)
        _ = c.base(rawMemos: k.memos, enhancements: k.enhancements, externalVersion: 1,
                   now: q320Now, backlinks: current)
        XCTAssertEqual(c.baseBuilds, builds, "an index that agrees triggers no rebuild")
    }
}
