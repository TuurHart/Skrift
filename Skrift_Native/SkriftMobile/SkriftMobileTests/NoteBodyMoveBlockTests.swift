import XCTest
import UIKit
@testable import SkriftMobile

/// Q547: dragging a picture through the REAL editor path (`Coordinator.moveBlock`, then the
/// commit and the reload that follow it) changes nothing but the picture's place. The first
/// device drop turned 'New recording…\n\nYeah yeah…\n[chip]' into one paragraph.
@MainActor
final class NoteBodyMoveBlockTests: XCTestCase {

    private let chipID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private var chip: String { "[[memo:\(chipID.uuidString)|djuhfdufh]]" }

    private func editor(_ body: String, audio: String) throws -> (NoteBodyView.Coordinator, NoteBodyTextView, Memo) {
        let memo = Memo(audioFilename: audio, transcript: body)
        memo.metadata = MemoMetadata(imageManifest: [ImageManifestEntry(filename: "photo_001.jpg", offsetSeconds: 2)])
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: { _ in })
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        return (coordinator, tv, memo)
    }

    /// Display offset of the start of display paragraph `n` (paragraphs split on "\n\n"), or the end.
    private func paragraphStart(_ n: Int, in tv: NoteBodyTextView) -> Int {
        let s = tv.textStorage.string as NSString
        var loc = 0
        for _ in 0..<n {
            let r = s.range(of: "\n\n", range: NSRange(location: loc, length: s.length - loc))
            guard r.location != NSNotFound else { return s.length }
            loc = NSMaxRange(r)
        }
        return loc
    }

    private func check(audio: String, body: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let (c, tv, memo) = try editor(body, audio: audio)
        let literal = "[[img_001]]"
        XCTAssertEqual(c.reconstruct(tv.attributedText), body, "the editor shows the stored body", file: file, line: line)
        let undo = try XCTUnwrap(tv.undoManager)

        // Down (to the top): picture first, every other paragraph and the chip's line intact.
        c.moveBlock(literal: literal, toDisplayLocation: 0)
        let top = "\(literal)\n\n" + body.replacingOccurrences(of: "\n\n\(literal)", with: "")
        XCTAssertEqual(memo.transcript, top, "moved to the top", file: file, line: line)
        XCTAssertEqual(c.reconstruct(tv.attributedText), top, "the editor shows it too", file: file, line: line)

        // Back to the bottom.
        c.moveBlock(literal: literal, toDisplayLocation: (tv.textStorage.string as NSString).length)
        XCTAssertEqual(memo.transcript, body, "moved back to the bottom", file: file, line: line)

        // Into the middle (before display paragraph 1, the second one).
        c.moveBlock(literal: literal, toDisplayLocation: paragraphStart(1, in: tv))
        let paras = body.components(separatedBy: "\n\n").filter { $0 != literal }
        let mid = ([paras[0], literal] + paras.dropFirst()).joined(separator: "\n\n")
        XCTAssertEqual(memo.transcript, mid, "moved between the paragraphs", file: file, line: line)

        // Undo puts the exact text back.
        XCTAssertTrue(undo.canUndo, "the move registered an undo step", file: file, line: line)
        c.undo()
        XCTAssertEqual(c.reconstruct(tv.attributedText), body, "undo restores the exact text", file: file, line: line)
    }

    func testVoiceNoteKeepsParagraphsAndTheChipLine() throws {
        try check(audio: "memo_q547.m4a",
                  body: "New recording, blah blah blah blah blah\n\nYeah yeah oh nice that works good\n\(chip)\n\n[[img_001]]")
    }

    func testVoiceNoteWithTheChipOnItsOwnParagraph() throws {
        try check(audio: "memo_q547.m4a",
                  body: "One.\n\nTwo.\n\n\(chip)\n\n[[img_001]]")
    }

    func testTypedNoteKeepsParagraphs() throws {
        try check(audio: "",
                  body: "New recording\n\nYeah yeah\n\(chip)\n\n[[img_001]]")
    }
}
