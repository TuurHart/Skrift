import XCTest
import UIKit
@testable import SkriftMobile

/// Q550: Undo walks back through EVERYTHING typed or inserted in a note, in order, and Redo
/// walks forward again (Tuur on Dev 203: typed, took a photo, Undo could not get past the
/// photo). The text is asserted at every step; the photo's file and manifest entry stay while
/// the photo can still be redone.
@MainActor
final class NoteBodyUndoSequenceTests: XCTestCase {

    private var window: UIWindow!

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    private func editor(_ body: String = "") throws -> (NoteBodyView.Coordinator, NoteBodyTextView, Memo) {
        let memo = Memo(audioFilename: "", transcript: body.isEmpty ? nil : body)
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

    /// What the note would store for the current text view contents.
    private func raw(_ c: NoteBodyView.Coordinator, _ tv: NoteBodyTextView) -> String {
        c.reconstruct(tv.attributedText)
    }

    /// One user action = one run-loop turn, so UIKit closes the typing group like a real gesture.
    private func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }

    private func type(_ s: String, _ tv: UITextView) {
        tv.insertText(s)
        settle()
    }

    private func photo() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { ctx in
            UIColor.systemOrange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
    }

    /// Undo all the way down, reading the stored text after every step.
    private func undoAll(_ c: NoteBodyView.Coordinator, _ tv: NoteBodyTextView) -> [String] {
        var seen: [String] = []
        var guardCount = 0
        while tv.undoManager?.canUndo == true, guardCount < 40 {
            c.undo(); settle()
            seen.append(raw(c, tv))
            guardCount += 1
        }
        return seen
    }

    private func redoAll(_ c: NoteBodyView.Coordinator, _ tv: NoteBodyTextView) -> [String] {
        var seen: [String] = []
        var guardCount = 0
        while tv.undoManager?.canRedo == true, guardCount < 40 {
            c.redo(); settle()
            seen.append(raw(c, tv))
            guardCount += 1
        }
        return seen
    }

    func testTypePhotoTypeUndoesToTheStartAndRedoesToTheEnd() throws {
        let (c, tv, memo) = try editor()
        let undo = try XCTUnwrap(tv.undoManager)

        var steps: [String] = [raw(c, tv)]            // the text after each user action, from empty
        type("Hello", tv);   steps.append(raw(c, tv))
        type("\n", tv);      steps.append(raw(c, tv))
        type("World", tv);   steps.append(raw(c, tv))
        c.insertPhoto(photo()); settle()
        let withPhoto = raw(c, tv)
        XCTAssertTrue(withPhoto.contains("[[img_001]]"), "the picture is in the text: \(withPhoto)")
        steps.append(withPhoto)
        type("after", tv);   steps.append(raw(c, tv))
        let final = steps.last!
        XCTAssertTrue(final.hasSuffix("after"), final)

        let photoFile = AppPaths.recordingsDirectory.appendingPathComponent(
            "photo_\(memo.id.uuidString)_001.jpg")

        // Undo: every step lands on the text the note had before that action.
        let backwards = undoAll(c, tv)
        XCTAssertEqual(backwards.last, "", "Undo reaches the empty start; the trail was \(backwards)")
        for earlier in steps.dropLast().reversed() where !backwards.contains(earlier) {
            XCTFail("Undo never showed the text \(earlier.debugDescription); the trail was \(backwards)")
        }
        let order = steps.dropLast().reversed().compactMap { backwards.firstIndex(of: $0) }
        XCTAssertEqual(order, order.sorted(), "Undo shows the earlier texts in order: \(backwards)")
        XCTAssertFalse(raw(c, tv).contains("[[img_"), "no stale picture marker after undoing the picture")
        XCTAssertTrue(FileManager.default.fileExists(atPath: photoFile.path),
                      "the picture's file stays while it can be redone")
        XCTAssertEqual(memo.metadata?.imageManifest?.count, 1, "the manifest entry stays while it can be redone")
        XCTAssertTrue(undo.canRedo)

        // Redo: forward through the same texts, ending on the same picture.
        let forwards = redoAll(c, tv)
        XCTAssertEqual(forwards.last, final, "Redo reaches the end; the trail was \(forwards)")
        for later in steps.dropFirst() where !forwards.contains(later) {
            XCTFail("Redo never showed the text \(later.debugDescription); the trail was \(forwards)")
        }
        XCTAssertEqual(raw(c, tv), final)
        XCTAssertTrue(raw(c, tv).contains("[[img_001]]"), "the same picture came back")
    }

    /// The commit (debounce, Done, the 1 s timer) must not clear the stack by rebuilding the
    /// text when it only normalised it.
    func testACommitAfterThePhotoKeepsTheEarlierUndo() throws {
        let (c, tv, _) = try editor()
        type("One", tv)
        type("\n", tv)
        type("Two", tv)
        c.insertPhoto(photo()); settle()
        c.commitDraft(); settle()
        XCTAssertTrue(tv.undoManager?.canUndo == true)
        let trail = undoAll(c, tv)
        XCTAssertEqual(trail.last, "", "Undo still reaches the start after a commit: \(trail)")
    }

    func testAFileInsertUndoesAndRedoes() throws {
        let (c, tv, memo) = try editor()
        type("Before", tv)
        let before = raw(c, tv)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("q550-\(UUID().uuidString).txt")
        try "hello".write(to: tmp, atomically: true, encoding: .utf8)
        c.insertAttachment(fileURL: tmp, originalName: "q550.txt", uti: "public.plain-text"); settle()
        let withFile = raw(c, tv)
        XCTAssertTrue(withFile.contains("[[file_001]]"), withFile)
        type("tail", tv)

        let trail = undoAll(c, tv)
        XCTAssertTrue(trail.contains(withFile), "Undo stops on the file's text: \(trail)")
        XCTAssertTrue(trail.contains(before), "Undo gets back to the text before the file: \(trail)")
        XCTAssertEqual(trail.last, "")
        XCTAssertFalse(raw(c, tv).contains("[[file_"), "no stale file marker")
        XCTAssertEqual(memo.metadata?.attachmentManifest?.count, 1, "the file stays registered while redoable")

        let forward = redoAll(c, tv)
        XCTAssertTrue(forward.contains(withFile), "Redo brings the file back: \(forward)")
        XCTAssertTrue(raw(c, tv).hasSuffix("tail"))
    }

    func testDeletingAPictureUndoesAndRedoes() throws {
        let (c, tv, _) = try editor()
        type("Top", tv)
        type("\n", tv)
        c.insertPhoto(photo()); settle()
        type("Bottom", tv)
        c.commitDraft()
        let stored = raw(c, tv)
        XCTAssertTrue(stored.contains("[[img_001]]"))

        // Delete through the hold menu's path.
        c.deleteBlock(literal: "[[img_001]]")
        let deleted = raw(c, tv)
        XCTAssertFalse(deleted.contains("[[img_001]]"), "the picture is gone: \(deleted)")

        c.undo(); settle()
        XCTAssertEqual(raw(c, tv), stored, "Undo brings the picture back byte-for-byte")
        c.redo(); settle()
        XCTAssertEqual(raw(c, tv), deleted, "Redo deletes it again")
        c.undo(); settle()
        XCTAssertEqual(raw(c, tv), stored)
    }

    /// Return on a checklist line continues the list (Q536 left it out); one Undo takes the
    /// new line away, a second takes the typing before it.
    func testReturnContinuingAListUndoes() throws {
        let (c, tv, _) = try editor("- [ ] Buy milk")
        tv.selectedRange = NSRange(location: tv.textStorage.length, length: 0)
        let before = raw(c, tv)
        XCTAssertEqual(before, "- [ ] Buy milk")

        // The text view asks its delegate first, as UIKit does on a Return keypress.
        let handled = !(c.textView(tv, shouldChangeTextIn: tv.selectedRange, replacementText: "\n"))
        XCTAssertTrue(handled, "the coordinator continued the list")
        settle()
        let continued = raw(c, tv)
        XCTAssertEqual(continued, "- [ ] Buy milk\n- [ ] ")

        c.undo(); settle()
        XCTAssertEqual(raw(c, tv), before, "Undo takes the new checkbox line away")
        c.redo(); settle()
        XCTAssertEqual(raw(c, tv), continued, "Redo puts it back")
    }

    func testReturnOnAnEmptyChecklistItemUndoes() throws {
        let (c, tv, _) = try editor("- [ ] Buy milk\n- [ ] ")
        tv.selectedRange = NSRange(location: tv.textStorage.length, length: 0)
        let before = raw(c, tv)
        let handled = !(c.textView(tv, shouldChangeTextIn: tv.selectedRange, replacementText: "\n"))
        XCTAssertTrue(handled)
        settle()
        let ended = raw(c, tv)
        XCTAssertNotEqual(ended, before, "the empty item ended the list")
        c.undo(); settle()
        XCTAssertEqual(raw(c, tv), before)
        c.redo(); settle()
        XCTAssertEqual(raw(c, tv), ended)
    }
}
