import XCTest
import SwiftUI
import SwiftData
@testable import SkriftMobile

/// Q451 (C113, C234, D200): a brand-new note and a reopened note are ONE screen — the same
/// `MemoDetailView` → `MemoPageView` → `noteHeaderCore` (title, grey meta line, then rating ·
/// Personal · tags on one row) — and the phone's tab bar is hidden in every open-note state.
/// Tuur 2026-10-15 (Dev 191): the old new-note screen stacked tag / rating / Personal on three
/// rows and showed the tab bar after Done, because it was its own view (`QuickNoteView`).
@MainActor
final class NoteScreenParityTests: XCTestCase {

    private static func source(_ rel: String) -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SkriftMobileTests
            .deletingLastPathComponent()   // SkriftMobile
        return (try? String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)) ?? ""
    }

    func testNewAndReopenedNoteBuildTheSameScreenAndHeader() throws {
        let repo = NotesRepository(inMemory: true)
        let stored = try Memo.newTyped(into: repo.context)
        stored.title = "Test 2"
        let newScreen = MemoDetailView.screen(for: .newDraft())
        let reopened = MemoDetailView.screen(for: .existing(stored.id))
        XCTAssertTrue(type(of: newScreen) == type(of: reopened))

        // The new note renders a page from its first frame (a pending typed memo), so its header
        // is the reopened note's header (`noteHeaderCore` inside the editor page), not a stand-in.
        let pending = try XCTUnwrap(newScreen.currentMemo, "the new note must render a page before any keystroke")
        XCTAssertNil(pending.modelContext, "D91: nothing is in the store until the first text")
        XCTAssertEqual(MemoPageView.pageKind(pending, locked: false), .editor)
        XCTAssertEqual(MemoPageView.pageKind(stored, locked: false), .editor)
        let page = Self.source("Features/MemoDetail/MemoPageView.swift")
        XCTAssertEqual(page.components(separatedBy: "struct MemoPageView").count - 1, 1)
        XCTAssertTrue(page.contains("noteHeaderCore(isCurrent: isCurrent)"), "the editor page draws the shared header")
    }

    func testTheTabBarIsHiddenInEveryOpenNoteOnThePhone() {
        XCTAssertEqual(MemoDetailView.tabBarVisibility(regular: false), .hidden)
        XCTAssertEqual(MemoDetailView.tabBarVisibility(regular: true), .automatic,
                       "the iPad's regular width keeps its own tab control")
        let detail = Self.source("Features/MemoDetail/MemoDetailView.swift")
        XCTAssertTrue(detail.contains(".toolbar(Self.tabBarVisibility(regular: hSize == .regular), for: .tabBar)"))
    }

    /// Every route into an open note goes through the one factory; the old duplicate is gone.
    func testNoSecondNoteScreenRemains() {
        let list = Self.source("Features/MemosList/MemosListView.swift")
        XCTAssertFalse(list.isEmpty, "could not read MemosListView.swift")
        XCTAssertFalse(list.contains("QuickNoteView"), "the new note must not draw its own screen")
        XCTAssertEqual(list.components(separatedBy: "MemoDetailView.screen(for: route").count - 1, 2,
                       "phone stack and iPad pane both resolve routes through the one factory")
        XCTAssertTrue(Self.source("Features/QuickNote/QuickNoteView.swift").isEmpty, "the duplicate is deleted")
    }

    /// D91 on the one screen: the pending note is inserted at its first text, keeps what the
    /// header set before it, and an untouched or emptied note leaves nothing behind.
    func testPendingNoteIsBornAtTheFirstTextWithItsHeader() throws {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let draft = QuickNoteDraft(pendingID: id)
        let pending = try XCTUnwrap(draft.pending)
        pending.tags = ["idea"]
        pending.significance = 0.5
        pending.destination = .portfolio
        XCTAssertFalse(draft.adoptIfTyped(context: repo.context), "a header pick alone is not a note")
        XCTAssertEqual(try repo.context.fetchCount(FetchDescriptor<Memo>()), 0)

        pending.title = "Test 2"
        XCTAssertTrue(draft.adoptIfTyped(context: repo.context))
        XCTAssertFalse(draft.adoptIfTyped(context: repo.context), "born once")
        let rows = try repo.context.fetch(FetchDescriptor<Memo>())
        XCTAssertEqual(rows.map(\.id), [id])
        XCTAssertEqual(rows.first?.tags, ["idea"])
        XCTAssertEqual(rows.first?.significance, 0.5)
        XCTAssertEqual(rows.first?.destination, .portfolio)
        draft.leave(context: repo.context)
        XCTAssertEqual(try repo.context.fetchCount(FetchDescriptor<Memo>()), 1, "a note with text is kept")
    }

    func testUntouchedOrEmptiedNewNoteLeavesNothing() throws {
        let repo = NotesRepository(inMemory: true)
        let untouched = QuickNoteDraft(pendingID: UUID())
        untouched.leave(context: repo.context)
        XCTAssertEqual(try repo.context.fetchCount(FetchDescriptor<Memo>()), 0)

        let emptied = QuickNoteDraft(pendingID: UUID())
        emptied.pending?.transcript = "a"
        emptied.adoptIfTyped(context: repo.context)
        emptied.pending?.transcript = nil
        emptied.leave(context: repo.context)
        XCTAssertEqual(try repo.context.fetchCount(FetchDescriptor<Memo>()), 0)
        XCTAssertFalse(emptied.adoptIfTyped(context: repo.context), "a removed draft is never re-adopted")
    }
}
