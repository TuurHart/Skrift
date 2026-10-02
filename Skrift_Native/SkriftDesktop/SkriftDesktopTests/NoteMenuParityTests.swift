import XCTest

/// Q180 (C239/C240/C179/C161; parity audit list-sidebar-83, note-menu-07, -13): the list context
/// menus, Redo and Copy transcript follow ONE rule set from `Shared/UI/NoteMenu.swift`.
final class NoteMenuParityTests: XCTestCase {

    // ── list menus build from NoteMenuItem; absences are declared with a reason ──

    func testPhoneListIsRemindLockCopyDeleteInSharedOrder() {
        XCTAssertEqual(NoteMenuLayout.listItems(.phoneList, state: NoteMenuState()),
                       [.remind, .lock, .copyTranscript, .delete])
        XCTAssertEqual(NoteMenuLayout.listItems(.phoneList, state: NoteMenuState(locked: true)),
                       [.remind, .unlock, .copyTranscript, .delete])
    }

    func testQuietMacListIsLockCopyDeleteLikeThePhone() {
        XCTAssertEqual(NoteMenuLayout.listItems(.macQuietList, state: NoteMenuState()),
                       [.lock, .copyTranscript, .delete])
        XCTAssertEqual(NoteMenuLayout.listItems(.macQuietList, state: NoteMenuState(locked: true)),
                       [.unlock, .copyTranscript, .delete])
    }

    func testRatedMacListFollowsSharedOrderAndGates() {
        let all = NoteMenuState(isConversation: true, canRetranscribe: true, redoOffered: true,
                                hasWorkingFolder: true, hasExportedFile: true)
        XCTAssertEqual(NoteMenuLayout.listItems(.macList, state: all),
                       [.flattenToMonologue, .retranscribe, .redo, .copyTranscript, .copyMarkdown,
                        .revealInFinder, .openInObsidian, .delete])
        XCTAssertEqual(NoteMenuLayout.listItems(.macList, state: NoteMenuState()),
                       [.copyTranscript, .copyMarkdown, .delete],
                       "gated items vanish when their gate is closed")
    }

    func testItemsAreInDeclarationOrderOnEverySurface() {
        let everything = NoteMenuState(isConversation: true, canRetranscribe: true, redoOffered: true,
                                       canUndoTidyUp: true, hasWorkingFolder: true, hasExportedFile: true)
        for surface in NoteMenuSurface.allCases {
            for locked in [false, true] {
                var s = everything; s.locked = locked
                let items = NoteMenuLayout.listItems(surface, state: s)
                let idx = items.compactMap { NoteMenuItem.allCases.firstIndex(of: $0) }
                XCTAssertEqual(idx, idx.sorted(), "\(surface) must render in NoteMenuItem order")
                XCTAssertEqual(items.last, .delete, "delete is last on \(surface)")
            }
        }
    }

    func testEveryAbsenceCarriesAReasonAndNoAbsentItemIsListed() {
        let everything = NoteMenuState(isConversation: true, canRetranscribe: true, redoOffered: true,
                                       canUndoTidyUp: true, hasWorkingFolder: true, hasExportedFile: true)
        for surface in NoteMenuSurface.allCases {
            var listed = Set(NoteMenuLayout.listItems(surface, state: everything))
            listed.formUnion(NoteMenuLayout.listItems(surface, state: NoteMenuState(locked: true)))
            for item in NoteMenuItem.allCases {
                if let why = item.absence(on: surface) {
                    XCTAssertFalse(why.trimmingCharacters(in: .whitespaces).isEmpty, "\(item) on \(surface): empty reason")
                    XCTAssertFalse(listed.contains(item), "\(item) is declared absent on \(surface) yet listed")
                } else {
                    XCTAssertTrue(listed.contains(item), "\(item) is not absent on \(surface) yet never listed")
                }
            }
        }
    }

    func testLockedRatedMacRowStillOffersCopyBecauseItAuthenticates() {
        let items = NoteMenuLayout.listItems(.macList, state: NoteMenuState(locked: true))
        XCTAssertTrue(items.contains(.copyTranscript), "locked copy authenticates then copies; it is no longer greyed out")
    }

    // ── Redo: one availability rule, one parts list ──

    func testRedoIsOfferedWhenAnyPartExists() {
        func offered(_ t: String?, _ c: String?, _ s: String?, engine: Bool = true, locked: Bool = false) -> Bool {
            NoteRedoItem.isOffered(title: t, copyEdit: c, summary: s, engineAvailable: engine, locked: locked)
        }
        XCTAssertTrue(offered("T", "C", "S"))
        XCTAssertTrue(offered(nil, nil, "S"), "any ONE part is enough (the iPad's rule; the Mac used to need all three)")
        XCTAssertTrue(offered("T", "", nil))
        XCTAssertFalse(offered(nil, nil, nil))
        XCTAssertFalse(offered("  ", "\n", ""), "whitespace is not a part")
        XCTAssertFalse(offered("T", "C", "S", engine: false))
        XCTAssertFalse(offered("T", "C", "S", locked: true))
    }

    func testRedoRuleMatchesThePhonesHasContent() {
        let parts: [String] = ["", "x"]
        for t in parts { for c in parts { for s in parts {
            let enh = MemoEnhancement(memoID: UUID(), copyedit: c, title: t, summary: s)
            XCTAssertEqual(NoteRedoItem.isOffered(title: t, copyEdit: c, summary: s, engineAvailable: true, locked: false),
                           enh.hasContent, "title=\(t) copyedit=\(c) summary=\(s)")
        } } }
    }

    func testConversationsKeepVerbatimSoCopyEditIsHidden() {
        XCTAssertEqual(NoteRedoItem.offered(isConversation: false), [.title, .copyEdit, .summary])
        XCTAssertEqual(NoteRedoItem.offered(isConversation: true), [.title, .summary])
    }

    func testFlatRedoLabelsForTheCompactDialog() {
        XCTAssertEqual(NoteRedoItem.allCases.map(\.flatLabel), ["Redo title", "Redo copy-edit", "Redo summary"])
    }

    func testMacRedoGateUsesTheSharedRule() {
        let f = PipelineFile(filename: "a.m4a")
        XCTAssertFalse(MacNoteMenu.redoOffered(f, locked: false))
        f.enhancedSummary = "only a summary"
        XCTAssertTrue(MacNoteMenu.redoOffered(f, locked: false), "one part is enough on the Mac too")
        XCTAssertFalse(MacNoteMenu.redoOffered(f, locked: true))
    }

    // ── Copy transcript: one rule ──

    func testCopyRuleLockedAuthenticatesThenCopies() {
        XCTAssertEqual(CopyTranscriptRule.step(needsAuth: true, text: "words"), .authenticate)
        XCTAssertEqual(CopyTranscriptRule.step(needsAuth: false, text: "words"), .copy("words"))
    }

    func testCopyRuleEmptySaysNothingToCopyYet() {
        XCTAssertEqual(CopyTranscriptRule.emptyMessage, "Nothing to copy yet")
        XCTAssertEqual(CopyTranscriptRule.step(needsAuth: false, text: nil), .nothingToCopy)
        XCTAssertEqual(CopyTranscriptRule.step(needsAuth: false, text: ""), .nothingToCopy)
    }

    // ── both apps actually use the rules (source scan, like SharedCopyUsageTests) ──

    private static var nativeRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func read(_ rel: String) throws -> String {
        let url = Self.nativeRoot.appendingPathComponent(rel)
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { throw XCTSkip("no \(rel)") }
        return s.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
    }

    func testListMenusAndCopyEntryPointsReadTheSharedRules() throws {
        let phoneList = try read("SkriftMobile/Features/MemosList/MemosListView+Actions.swift")
        XCTAssertTrue(phoneList.contains("NoteMenuLayout.listItems(.phoneList"))
        XCTAssertTrue(phoneList.contains("CopyTranscriptRule.emptyMessage"))
        XCTAssertTrue(phoneList.contains("GatedCopy.copyTranscript"))
        let gated = try read("SkriftMobile/Services/GatedCopy.swift")
        XCTAssertTrue(gated.contains("CopyTranscriptRule.step"))
        let detail = try read("SkriftMobile/Features/MemoDetail/MemoDetailView.swift")
        XCTAssertTrue(detail.contains("NoteRedoItem.isOffered"))
        XCTAssertTrue(detail.contains("flatLabel"), "the compact dialog carries Redo")
        let sidebar = try read("SkriftDesktop/Features/Sidebar/SidebarView.swift")
        XCTAssertTrue(sidebar.contains("NoteMenuLayout.listItems(.macList"))
        XCTAssertTrue(sidebar.contains("NoteMenuLayout.listItems(.macQuietList"))
        XCTAssertFalse(sidebar.contains("Button(\"Open\")"), "the quiet row's bare Open carried no information")
        let actions = try read("SkriftDesktop/Features/Review/NoteActions.swift")
        XCTAssertTrue(actions.contains("MacNoteMenu.redoOffered"))
        XCTAssertFalse(actions.contains(".disabled(locked)"), "Mac Copy authenticates; it no longer greys out")
        let macCopy = try read("SkriftDesktop/Features/Review/MacGatedCopy.swift")
        XCTAssertTrue(macCopy.contains("CopyTranscriptRule.step"))
    }
}
