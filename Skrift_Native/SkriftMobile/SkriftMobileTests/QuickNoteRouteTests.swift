import XCTest
import SwiftData
@testable import SkriftMobile

/// Q47 (BUGS §3, build 172): the ✎ tap must always route to a NEW draft, and
/// never resolve to an existing memo — including the memo the launch
/// recovery sweep may just have created ("Recovered recording…", dated when
/// the interrupted take started, so it sorts newest). The bug: a bare `UUID`
/// path compared against a SEPARATE `quickNoteDraftID` state var could
/// desync; `NoteRoute` carries its own draft/memo kind inline so there is
/// nothing left to desync from.
@MainActor
final class QuickNoteRouteTests: XCTestCase {

    /// A store already holding memos, including one that looks exactly like
    /// a launch-recovered take: newest by `recordedAt` (a fresh crash
    /// recovers with "now"), titled `MemoSaver.recoveredTitle`.
    private func storeWithRecoveredRecording() -> (repo: NotesRepository, recoveredID: UUID) {
        let repo = NotesRepository(inMemory: true)
        // An older, ordinary note.
        let older = try! Memo.newTyped(into: repo.context, now: Date().addingTimeInterval(-3600))
        older.title = "Groceries"
        older.transcript = "Milk, eggs"
        // The recovered recording: newest, so a naive "memos.first" default
        // would land on it.
        let recovered = try! Memo.newTyped(into: repo.context, now: Date())
        recovered.title = MemoSaver.recoveredTitle
        try? repo.context.save()
        return (repo, recovered.id)
    }

    func testNewDraftRouteIsNeverAnExistingMemoID() {
        let (repo, recoveredID) = storeWithRecoveredRecording()
        let existingIDs = Set((try? repo.context.fetch(FetchDescriptor<Memo>()))?.map(\.id) ?? [])
        XCTAssertTrue(existingIDs.contains(recoveredID), "fixture sanity: the recovered memo is in the store")

        // The ✎ tap always mints a fresh route.
        let route = NoteRoute.newDraft()

        XCTAssertTrue(route.isDraft, "✎ must route to a draft, never straight to an existing memo")
        XCTAssertFalse(existingIDs.contains(route.id),
                        "a fresh draft id must never collide with (or be mistaken for) an existing memo's id")
        XCTAssertNotEqual(route.id, recoveredID,
                           "the ✎ route must never resolve to the recovered recording specifically")
    }

    /// Mirrors the destination-closure switch in `MemosListView` — proves the
    /// two route kinds can never be confused with each other by construction
    /// (no cross-referenced side state to go stale).
    func testDraftAndMemoRoutesResolveToDifferentScreens() {
        let (_, recoveredID) = storeWithRecoveredRecording()
        let draftRoute = NoteRoute.newDraft()
        let memoRoute = NoteRoute.existing(recoveredID)

        func resolvesToQuickNote(_ route: NoteRoute) -> Bool {
            switch route {
            case .draft: return true
            case .memo: return false
            }
        }

        XCTAssertTrue(resolvesToQuickNote(draftRoute))
        XCTAssertFalse(resolvesToQuickNote(memoRoute))
        XCTAssertNotEqual(draftRoute, memoRoute)
    }

    func testRepeatedNewDraftCallsNeverRepeatAnID() {
        let routes = (0..<50).map { _ in NoteRoute.newDraft() }
        XCTAssertEqual(Set(routes.map(\.id)).count, routes.count,
                        "every ✎ tap must mint its own fresh draft id")
    }
}
