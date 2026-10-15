import XCTest
import SwiftUI
import UIKit
@testable import SkriftMobile

/// Q466 (C113, C234; mock Q452 option B, Tuur 2026-10-15): while he types with the keyboard up
/// the note scrolls the header away like Apple Notes and keeps the caret just above the keyboard
/// bar. Nothing folds; dragging down brings the header back.
@MainActor
final class TypingScrollTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 393, height: 852)
    private let keyboard: CGFloat = 336     // keyboard + the Skrift bar over the bottom of the page
    private let headerHeight: CGFloat = 220

    /// A real note text view in a window, a tall header hosted in its scroll content.
    private func makeNote() -> (NoteBodyTextView, UIWindow) {
        let tv = NoteBodyTextView()
        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = true
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 20, bottom: 24, right: 20)
        tv.textContainer.lineFragmentPadding = 0
        tv.font = .systemFont(ofSize: 17)
        tv.installAccessoryHosts()
        tv.setAccessories(header: AnyView(Color.gray.frame(height: headerHeight)), footer: AnyView(EmptyView()))
        tv.frame = screen
        let vc = UIViewController()
        vc.view.addSubview(tv)
        let window = UIWindow(frame: screen)
        window.rootViewController = vc
        window.makeKeyAndVisible()
        tv.frame = screen
        tv.layoutIfNeeded()
        return (tv, window)
    }

    /// The caret's bottom edge in the visible frame, from the top of the view.
    private func caretBottomOnScreen(_ tv: NoteBodyTextView) -> CGFloat {
        let end = tv.selectedTextRange!.end
        return tv.caretRect(for: end).maxY - tv.contentOffset.y
    }

    private func type(_ lines: Int, into tv: NoteBodyTextView) {
        for i in 0..<lines {
            tv.insertText("Line \(i) of the note he is typing.\n")
            tv.layoutIfNeeded()
            tv.followCaretWhileTyping(keyboardOverlap: keyboard, animated: false)
            tv.layoutIfNeeded()
        }
    }

    func testFirstLinesScrollTheHeaderOutAndKeepTheCaretAboveTheKeyboard() {
        let (tv, window) = makeNote()
        withExtendedLifetime(window) {
            XCTAssertEqual(tv.contentOffset.y, -tv.adjustedContentInset.top, accuracy: 1, "starts at the top")
            type(1, into: tv)
            let headerOff = headerHeight - tv.adjustedContentInset.top
            XCTAssertGreaterThanOrEqual(tv.contentOffset.y, headerOff - 1,
                                        "the first line of text scrolls the whole header off the top")
            XCTAssertGreaterThan(tv.typingRoom, 0, "a one-line note borrows room so the header can leave")
            XCTAssertEqual(tv.contentInset.bottom, 0,
                           "room is blank CONTENT: a bottom contentInset makes UITextView's own caret-follow scroll the text away (Q466 sim)")
            type(4, into: tv)
            XCTAssertEqual(tv.contentOffset.y, headerOff, accuracy: 1, "five short lines: the text stays at the top, not scrolled past")
            type(30, into: tv)
            XCTAssertLessThanOrEqual(caretBottomOnScreen(tv), screen.height - keyboard,
                                     "typing past the visible area keeps the caret above the keyboard bar")
            XCTAssertGreaterThanOrEqual(tv.contentOffset.y, headerOff - 1, "the header stays out")
        }
    }

    /// Sim (Q466): UITextView's own scroll-to-selection shoved the caret line to the top of the view
    /// on every Return once the typing room made that offset reachable.
    func testAVisibleCaretIsNotScrolledAwayByUIKitsOwnFollow() {
        let (tv, window) = makeNote()
        withExtendedLifetime(window) {
            type(3, into: tv)
            XCTAssertGreaterThan(tv.typingRoom, 0)
            let before = tv.contentOffset.y
            let caret = tv.caretRect(for: tv.selectedTextRange!.end)
            tv.scrollRectToVisible(caret.insetBy(dx: 0, dy: -300), animated: false)
            XCTAssertEqual(tv.contentOffset.y, before, accuracy: 0.5, "the caret is on screen: no scroll")
        }
    }

    func testNothingMovesOnceTheHeaderIsAlreadyOff() {
        XCTAssertNil(TypingScroll.targetOffset(current: 400, headerHeight: 220, adjustedTop: 100,
                                               caretBottom: 500, boundsHeight: 852, bottomCover: 336))
    }

    func testCaretLowerThanTheKeyboardPushesFurtherThanTheHeader() throws {
        let y = try XCTUnwrap(TypingScroll.targetOffset(current: 0, headerHeight: 220, adjustedTop: 100,
                                                        caretBottom: 900, boundsHeight: 852, bottomCover: 336))
        XCTAssertEqual(y, 900 + TypingScroll.caretMargin - 852 + 336, "caret bottom lands 12 pt above the keyboard")
        XCTAssertGreaterThan(y, 220 - 100)
    }

    func testDraggingDownBringsTheHeaderBackAndEndingEditsReturnsTheRoom() {
        let (tv, window) = makeNote()
        withExtendedLifetime(window) {
            type(2, into: tv)
            XCTAssertGreaterThan(tv.contentOffset.y, 0)
            tv.setContentOffset(CGPoint(x: 0, y: -tv.adjustedContentInset.top), animated: false)
            XCTAssertEqual(tv.contentOffset.y, -tv.adjustedContentInset.top, accuracy: 1, "the header is reachable again")
            tv.releaseTypingRoom()
            XCTAssertEqual(tv.typingRoom, 0)
            XCTAssertEqual(tv.contentInset.bottom, 0)
        }
    }

    func testCoordinatorAsksTheTextViewToFollowTheCaretAfterEveryEdit() throws {
        let src = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Features/MemoDetail/NoteBodyView.swift"), encoding: .utf8)
        XCTAssertTrue(src.contains("followCaretWhileTyping()"), "textViewDidChange must call the follow")
        XCTAssertTrue(src.contains("releaseTypingRoom()"), "end of editing returns the borrowed room")
    }
}
