import XCTest
import SwiftData
@testable import SkriftMobile

/// Q314: opening a note does no whole-library work. 2,000 in-memory memos stand in for the
/// measured library (plan/perf2/MEASURED.md): the open must build titles only for the notes that
/// link here, and the backlink index must be reused until something is saved or synced.
@MainActor
final class NoteOpenWorkTests: XCTestCase {

    private func link(_ id: UUID) -> String { MemoLinkSyntax.link(id: id, title: "Old thought") }

    /// 2,000 untitled memos with multi-line bodies; `linkers` link to `target`.
    private func library(count: Int = 2000, target: UUID, linkers: Int = 2)
        -> (repo: NotesRepository, target: Memo, linkerIDs: [UUID]) {
        let repo = NotesRepository(inMemory: true)
        let now = Date()
        let targetMemo = Memo(audioFilename: "t.m4a", recordedAt: now.addingTimeInterval(-10_000_000),
                              transcript: "The note being opened", transcriptStatus: .done)
        targetMemo.id = target
        repo.context.insert(targetMemo)
        var linkerIDs: [UUID] = []
        for i in 0..<count {
            let isLinker = i < linkers
            let body = (isLinker ? "see \(link(target)) " : "") +
                "Line \(i) of a long untitled body. " + String(repeating: "More words here. ", count: 30)
            let m = Memo(audioFilename: "m\(i).m4a", recordedAt: now.addingTimeInterval(-Double(i) * 60),
                         transcript: body, transcriptStatus: .done)
            repo.context.insert(m)
            if isLinker { linkerIDs.append(m.id) }
        }
        repo.save()
        return (repo, targetMemo, linkerIDs)
    }

    func testOpeningANoteBuildsTitlesOnlyForTheNotesThatLinkHere() async {
        let target = UUID()
        let (repo, _, linkerIDs) = library(target: target)
        var titleBuilds = 0
        let work = await NoteOpenWork.load(for: target, wantsBacklinks: true, repository: repo,
                                           titleOf: { titleBuilds += 1; return $0.ladderTitle() })
        XCTAssertEqual(work.backlinks.map(\.id), linkerIDs, "newest first")
        XCTAssertEqual(titleBuilds, linkerIDs.count,
                       "no full-corpus title build: one title per note that links here, not 2,001")
        XCTAssertEqual(work.linkedIDs, [target])
    }

    func testAnUnratedOpenBuildsNoTitlesAtAll() async {
        let target = UUID()
        let (repo, _, _) = library(target: target)
        var titleBuilds = 0
        _ = await NoteOpenWork.load(for: target, wantsBacklinks: false, repository: repo,
                                    titleOf: { titleBuilds += 1; return $0.ladderTitle() })
        XCTAssertEqual(titleBuilds, 0)
    }

    func testTheBacklinkIndexIsReusedAcrossTwoOpensAndRebuiltAfterASave() async {
        let target = UUID()
        let (repo, _, linkerIDs) = library(target: target)
        let first = await NoteOpenWork.load(for: target, wantsBacklinks: true, repository: repo)
        let second = await NoteOpenWork.load(for: linkerIDs[0], wantsBacklinks: true, repository: repo)
        XCTAssertEqual(repo.backlinkCache.buildCount, 1, "two opens, no save between: one build")
        XCTAssertEqual(first.backlinks.count, linkerIDs.count)
        XCTAssertTrue(second.backlinks.isEmpty)

        repo.save()   // a commit bumps the memo-set version
        _ = await NoteOpenWork.load(for: target, wantsBacklinks: true, repository: repo)
        XCTAssertEqual(repo.backlinkCache.buildCount, 2, "rebuilt after a save")

        _ = await NoteOpenWork.load(for: target, wantsBacklinks: true, repository: repo)
        XCTAssertEqual(repo.backlinkCache.buildCount, 2, "and reused again")
    }

    func testASyncImportAlsoRebuildsTheIndex() async {
        let target = UUID()
        let (repo, _, _) = library(count: 20, target: target)
        _ = await repo.backlinkIndex()
        repo.noteStoreDidChangeBySync()
        _ = await repo.backlinkIndex()
        XCTAssertEqual(repo.backlinkCache.buildCount, 2)
    }

    func testANewLinkAfterASaveShowsUp() async {
        let target = UUID()
        let (repo, _, linkerIDs) = library(count: 20, target: target)
        let before = await NoteOpenWork.load(for: target, wantsBacklinks: true, repository: repo)
        XCTAssertEqual(before.backlinks.count, linkerIDs.count)
        let late = Memo(audioFilename: "late.m4a", recordedAt: Date(),
                        transcript: "newest \(link(target))", transcriptStatus: .done)
        repo.insert(late)
        let after = await NoteOpenWork.load(for: target, wantsBacklinks: true, repository: repo)
        XCTAssertEqual(after.backlinks.first?.id, late.id)
        XCTAssertEqual(after.backlinks.count, linkerIDs.count + 1)
    }

    /// The index answers exactly what the per-open scans answered: `Backlinks.scan` for who links
    /// here, `MemoLifecycle.backlinkedIDs` for the linked set, including a link only in the
    /// Mac's copy-edit and excluding a trashed linker.
    func testTheIndexMatchesTheOldScans() async {
        let repo = NotesRepository(inMemory: true)
        let now = Date()
        func make(_ text: String, _ minutes: Double) -> Memo {
            let m = Memo(audioFilename: "x.m4a", recordedAt: now.addingTimeInterval(-minutes * 60),
                         transcript: text, transcriptStatus: .done)
            repo.context.insert(m)
            return m
        }
        let target = make("target", 100)
        let viaTranscript = make("see \(link(target.id))", 1)
        let viaCopyedit = make("just words", 2)
        let trashedLinker = make("old \(link(target.id))", 3)
        let selfLinker = make("me \(link(UUID()))", 4)
        repo.context.insert(MemoEnhancement(memoID: viaCopyedit.id, copyedit: "polished \(link(target.id))"))
        trashedLinker.deletedAt = now
        repo.save()

        let index = await repo.backlinkIndex()
        let live = repo.allMemos()
        let copyedits = Backlinks.copyeditsByMemoID(repo.allEnhancements())
        let rows = live.map { Backlinks.Row(id: $0.id, transcript: $0.transcript, copyedit: copyedits[$0.id]) }
        XCTAssertEqual(index.linkers(of: target.id), Backlinks.scan(for: target.id, in: rows))
        XCTAssertEqual(index.linkers(of: target.id), [viaTranscript.id, viaCopyedit.id])
        XCTAssertEqual(index.linkedIDs, MemoLifecycle.backlinkedIDs(in: live, copyedits: copyedits))
        _ = selfLinker
    }

    func testThePickersTitlesAreBuiltOncePerVersion() {
        let target = UUID()
        let (repo, targetMemo, _) = library(count: 50, target: target)
        let builds = NoteOpenWork.candidateBuilds
        let a = NoteOpenWork.linkCandidates(excluding: target, repository: repo)
        let b = NoteOpenWork.linkCandidates(excluding: targetMemo.id, repository: repo)
        XCTAssertEqual(NoteOpenWork.candidateBuilds, builds + 1, "reopening the picker reuses the titles")
        XCTAssertEqual(a.count, 50)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        repo.save()
        _ = NoteOpenWork.linkCandidates(excluding: target, repository: repo)
        XCTAssertEqual(NoteOpenWork.candidateBuilds, builds + 2, "rebuilt after a save")
    }
}
