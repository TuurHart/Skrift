import XCTest
import UIKit
@testable import SkriftMobile

/// Q551: after a picture or file goes into a note, the caret sits on its own empty line below
/// the block (as in Apple Notes), so the next word is a new paragraph. Found by Q550: the caret
/// stayed right after the picture glyph and the stored text read `[[img_001]]OMEGA`. A voice
/// note whose paragraphs end without punctuation also lost its paragraph breaks around the
/// existing picture when a second picture was added (the commit read the new inline marker as a
/// mid-sentence drop and re-joined the neighbours).
@MainActor
final class NoteBodyPhotoCaretTests: XCTestCase {

    private var window: UIWindow!
    override func tearDown() { window = nil; super.tearDown() }

    /// Four unpunctuated voice paragraphs around a picture already in the note.
    private let voice = "first thought about the thing\n\nsecond thought about another thing\n\n[[img_001]]\n\nthird thought without a stop\n\nfourth thought also open ended"

    private func editor(_ body: String, audio: String = "memo_q551.m4a") throws -> (NoteBodyView.Coordinator, NoteBodyTextView, Memo) {
        let memo = Memo(audioFilename: audio, transcript: body)
        memo.metadata = MemoMetadata(imageManifest: [ImageManifestEntry(filename: "photo_001.jpg", offsetSeconds: 2)])
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: { _ in })
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        tv.delegate = coordinator
        tv.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        window.addSubview(tv)
        window.makeKeyAndVisible()
        coordinator.textView = tv
        coordinator.load(force: true)
        XCTAssertTrue(tv.becomeFirstResponder(), "the editor takes the keyboard")
        return (coordinator, tv, memo)
    }

    private func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    private func raw(_ c: NoteBodyView.Coordinator, _ tv: NoteBodyTextView) -> String { c.reconstruct(tv.attributedText) }

    private func photo() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { ctx in
            UIColor.systemOrange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
    }

    private func caret(after needle: String?, in tv: NoteBodyTextView) {
        let s = tv.textStorage.string as NSString
        let at = needle.map { NSMaxRange(s.range(of: $0)) } ?? s.length
        tv.selectedRange = NSRange(location: at, length: 0)
    }

    private func undoAll(_ c: NoteBodyView.Coordinator, _ tv: NoteBodyTextView) {
        var n = 0
        while tv.undoManager?.canUndo == true, n < 40 { c.undo(); settle(); n += 1 }
    }

    private func tempFile() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("q551-\(UUID().uuidString).txt")
        try "hello".write(to: tmp, atomically: true, encoding: .utf8)
        return tmp
    }

    // MARK: picture

    func testCaretAtTheEndOfAVoiceNoteThenAWordIsANewParagraph() throws {
        let (c, tv, memo) = try editor(voice)
        caret(after: nil, in: tv)
        c.insertPhoto(photo()); settle()
        tv.insertText("OMEGA"); settle()
        c.commitDraft()
        XCTAssertEqual(memo.transcript, voice + "\n\n[[img_002]]\n\nOMEGA")
        XCTAssertEqual(memo.metadata?.imageManifest?.count, 2)
    }

    func testCaretInTheMiddleOfASentence() throws {
        let (c, tv, memo) = try editor(voice)
        caret(after: "third thought", in: tv)
        c.insertPhoto(photo()); settle()
        tv.insertText("OMEGA"); settle()
        c.commitDraft()
        let expected = "first thought about the thing\n\nsecond thought about another thing\n\n[[img_001]]\n\nthird thought without a stop\n\n[[img_002]]\n\nOMEGA\n\nfourth thought also open ended"
        XCTAssertEqual(memo.transcript, expected)
    }

    func testNothingTypedSavesNoTrailingBlankLine() throws {
        let (c, tv, memo) = try editor(voice)
        caret(after: nil, in: tv)
        c.insertPhoto(photo()); settle()
        c.commitDraft()
        XCTAssertEqual(memo.transcript, voice + "\n\n[[img_002]]")
        XCTAssertFalse(memo.transcript?.hasSuffix("\n") ?? true)
        // The caret waits on its own line below the block.
        let shown = tv.textStorage.string as NSString
        XCTAssertEqual(tv.selectedRange.location, shown.length, "caret is at the very end of the view")
        XCTAssertTrue(shown.substring(from: max(0, shown.length - 2)) == "\n\n", "an empty line stands below the picture")
    }

    func testMiddleOfANoteWithNothingTypedStaysSeparate() throws {
        let (c, tv, memo) = try editor(voice)
        caret(after: "second thought", in: tv)
        c.insertPhoto(photo()); settle()
        c.commitDraft(); settle()
        let expected = "first thought about the thing\n\nsecond thought about another thing\n\n[[img_002]]\n\n[[img_001]]\n\nthird thought without a stop\n\nfourth thought also open ended"
        XCTAssertEqual(memo.transcript, expected)
    }

    func testUndoReturnsTheExactTextAfterInsertAndAfterTyping() throws {
        let (c, tv, _) = try editor(voice)
        caret(after: "third thought", in: tv)
        c.insertPhoto(photo()); settle()
        undoAll(c, tv)
        XCTAssertEqual(raw(c, tv), voice, "one Undo takes the picture and its empty line away")

        let (c2, tv2, _) = try editor(voice)
        caret(after: nil, in: tv2)
        c2.insertPhoto(photo()); settle()
        tv2.insertText("OMEGA"); settle()
        c2.commitDraft()
        undoAll(c2, tv2)
        XCTAssertEqual(raw(c2, tv2), voice, "Undo all the way restores the note")
    }

    func testTypedNoteWithPunctuatedParagraphs() throws {
        let body = "One line.\n\nTwo lines."
        let (c, tv, memo) = try editor(body, audio: "")
        memo.metadata = MemoMetadata(imageManifest: [])
        caret(after: "One line.", in: tv)
        c.insertPhoto(photo()); settle()
        tv.insertText("Word"); settle()
        c.commitDraft()
        XCTAssertEqual(memo.transcript, "One line.\n\n[[img_001]]\n\nWord\n\nTwo lines.")
    }

    // MARK: file

    func testFileInsertAtTheEndThenAWord() throws {
        let (c, tv, memo) = try editor(voice)
        caret(after: nil, in: tv)
        c.insertAttachment(fileURL: try tempFile(), originalName: "q551.txt", uti: "public.plain-text"); settle()
        tv.insertText("OMEGA"); settle()
        c.commitDraft()
        XCTAssertEqual(memo.transcript, voice + "\n\n[[file_001]]\n\nOMEGA")
        undoAll(c, tv)
        XCTAssertEqual(raw(c, tv), voice)
    }

    func testFileInsertMidSentenceKeepsEveryParagraph() throws {
        let (c, tv, memo) = try editor(voice)
        caret(after: "third thought", in: tv)
        c.insertAttachment(fileURL: try tempFile(), originalName: "q551.txt", uti: "public.plain-text"); settle()
        tv.insertText("OMEGA"); settle()
        c.commitDraft()
        let expected = "first thought about the thing\n\nsecond thought about another thing\n\n[[img_001]]\n\nthird thought without a stop\n\n[[file_001]]\n\nOMEGA\n\nfourth thought also open ended"
        XCTAssertEqual(memo.transcript, expected)
    }
}
