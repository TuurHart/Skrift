import XCTest
import UIKit
@testable import SkriftMobile

/// Q554: tapping Done must not change the order of the pictures and files the user placed
/// (Tuur's recording on Dev 205: photo, library photo, file read photo, file, library photo
/// under half a second after Done). The stored text is quoted before and after Done.
@MainActor
final class NoteBodyBlockOrderTests: XCTestCase {

    private var window: UIWindow!

    override func tearDown() { window = nil; super.tearDown() }

    private func editor(_ body: String = "", audio: String = "") -> (NoteBodyView.Coordinator, NoteBodyTextView, Memo) {
        let memo = Memo(audioFilename: audio, transcript: body.isEmpty ? nil : body)
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
        XCTAssertTrue(tv.becomeFirstResponder())
        return (coordinator, tv, memo)
    }

    private func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    private func type(_ s: String, _ tv: UITextView) { tv.insertText(s); settle() }

    private func photo() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { ctx in
            UIColor.systemOrange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
    }

    private func file(_ c: NoteBodyView.Coordinator, name: String = "a.txt") throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("q554-\(UUID().uuidString).txt")
        try "hello".write(to: tmp, atomically: true, encoding: .utf8)
        c.insertAttachment(fileURL: tmp, originalName: name, uti: "public.plain-text"); settle()
    }

    private func video(_ c: NoteBodyView.Coordinator) throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("q554-\(UUID().uuidString).mov")
        try Data(repeating: 1, count: 64).write(to: tmp)
        c.insertAttachment(fileURL: tmp, originalName: "clip.mov", uti: "com.apple.quicktime-movie"); settle()
    }

    /// Marker literals in the order they stand in `text`.
    private func order(_ text: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"\[\[(?:img|vid|file)_\d+\]\]"#)
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private static let logPath = "/private/tmp/claude-501/q554-probe.log"
    private func log(_ s: String) {
        let line = s + "\n"
        if let h = FileHandle(forWritingAtPath: Self.logPath) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(toFile: Self.logPath, atomically: true, encoding: .utf8) }
    }

    private func undoAll(_ c: NoteBodyView.Coordinator, _ tv: NoteBodyTextView) {
        var n = 0
        while tv.undoManager?.canUndo == true, n < 60 { c.undo(); settle(); n += 1 }
    }
    private func redoAll(_ c: NoteBodyView.Coordinator, _ tv: NoteBodyTextView) {
        var n = 0
        while tv.undoManager?.canRedo == true, n < 60 { c.redo(); settle(); n += 1 }
    }

    /// Runs `build`, then Done; logs stored text before and after; asserts the block order held.
    private func scenario(_ name: String, undoRedo: Bool, body: String = "", audio: String = "",
                          _ build: (NoteBodyView.Coordinator, NoteBodyTextView) throws -> Void) throws {
        let (c, tv, memo) = editor(body, audio: audio)
        try build(c, tv)
        if undoRedo { undoAll(c, tv); redoAll(c, tv) }
        let before = memo.transcript ?? ""
        let shown = c.reconstruct(tv.attributedText)
        c.finishEditing(); settle()
        c.textViewDidEndEditing(tv); settle()
        let after = memo.transcript ?? ""
        let imgs = memo.metadata?.imageManifest?.count ?? 0, atts = memo.metadata?.attachmentManifest?.map(\.kind) ?? []
        log("[\(name) undoRedo=\(undoRedo)] imgs=\(imgs) atts=\(atts)\n  before \(before.debugDescription)\n  shown  \(shown.debugDescription)\n  after  \(after.debugDescription)")
        XCTAssertEqual(order(shown), order(after), "\(name) undoRedo=\(undoRedo): Done reordered the blocks. before \(before.debugDescription) after \(after.debugDescription)")
        XCTAssertEqual(order(before), order(after), "\(name) undoRedo=\(undoRedo): committed text reordered. before \(before.debugDescription) after \(after.debugDescription)")
    }

    func testTextPhotoLibraryPhotoFile() throws {
        for ur in [false, true] {
            try scenario("text,photo,photo,file", undoRedo: ur) { c, tv in
                self.type("Hello world", tv); c.insertPhoto(self.photo()); self.settle()
                c.insertPhoto(self.photo()); self.settle(); try self.file(c)
            }
        }
    }
    func testFileThenPhoto() throws {
        for ur in [false, true] {
            try scenario("text,file,photo", undoRedo: ur) { c, tv in
                self.type("Hello world", tv); try self.file(c); c.insertPhoto(self.photo()); self.settle()
            }
        }
    }
    func testVideoBetweenPhotos() throws {
        for ur in [false, true] {
            try scenario("photo,video,photo", undoRedo: ur) { c, tv in
                self.type("Hello world", tv); c.insertPhoto(self.photo()); self.settle()
                try self.video(c); c.insertPhoto(self.photo()); self.settle()
            }
        }
    }
    func testNoTextPhotoFilePhotoFile() throws {
        for ur in [false, true] {
            try scenario("photo,file,photo,file", undoRedo: ur) { c, tv in
                c.insertPhoto(self.photo()); self.settle(); try self.file(c)
                c.insertPhoto(self.photo()); self.settle(); try self.file(c, name: "b.txt")
            }
        }
    }
    /// Tuur's note: a voice memo (audio, so the speech source) with two dictated lines.
    func testVoiceNoteWithDictatedLines() throws {
        for ur in [false, true] {
            try scenario("voice: photo above, photo,photo,file below", undoRedo: ur, body: "Wor\nType", audio: "memo_q554.m4a") { c, tv in
                tv.selectedRange = NSRange(location: 0, length: 0)
                c.insertPhoto(self.photo()); self.settle()
                tv.selectedRange = NSRange(location: tv.textStorage.length, length: 0)
                c.insertPhoto(self.photo()); self.settle()
                c.insertPhoto(self.photo()); self.settle()
                try self.file(c)
            }
        }
    }
    func testVoiceNoteEndOnly() throws {
        for ur in [false, true] {
            try scenario("voice: end photo,photo,file", undoRedo: ur, body: "Wor\nType", audio: "memo_q554.m4a") { c, tv in
                tv.selectedRange = NSRange(location: tv.textStorage.length, length: 0)
                c.insertPhoto(self.photo()); self.settle()
                c.insertPhoto(self.photo()); self.settle()
                try self.file(c)
            }
        }
    }
    /// Backspace once at the start of a block's line: the glyph now touches the one before it.
    private func backspace(before marker: String, _ c: NoteBodyView.Coordinator, _ tv: NoteBodyTextView) {
        var at: Int?
        let st = tv.textStorage
        st.enumerateAttributes(in: NSRange(location: 0, length: st.length)) { attrs, r, stop in
            if r.length == 1, c.reconstruct(st.attributedSubstring(from: r)) == marker { at = r.location; stop.pointee = true }
        }
        guard let loc = at else { XCTFail("no glyph for \(marker)"); return }
        tv.selectedRange = NSRange(location: loc, length: 0)
        tv.deleteBackward(); settle()
    }

    func testBackspaceBeforeTheFileBlock() throws {
        for ur in [false, true] {
            try scenario("backspace before file", undoRedo: ur, body: "Wor\nType", audio: "memo_q554.m4a") { c, tv in
                tv.selectedRange = NSRange(location: tv.textStorage.length, length: 0)
                c.insertPhoto(self.photo()); self.settle()
                c.insertPhoto(self.photo()); self.settle()
                try self.file(c)
                self.backspace(before: "[[file_001]]", c, tv)
            }
        }
    }
    func testBackspaceBeforeSecondPhoto() throws {
        for ur in [false, true] {
            try scenario("backspace before 2nd photo", undoRedo: ur, body: "Wor\nType", audio: "memo_q554.m4a") { c, tv in
                tv.selectedRange = NSRange(location: tv.textStorage.length, length: 0)
                c.insertPhoto(self.photo()); self.settle()
                c.insertPhoto(self.photo()); self.settle()
                try self.file(c)
                self.backspace(before: "[[img_002]]", c, tv)
            }
        }
    }
    /// One earlier picture glued to the line above (a Backspace) makes the commit lift EVERY
    /// picture run; the others used to land after the file next to them.
    func testGluedPictureElsewhereDoesNotMovePicturesPastTheFile() throws {
        for ur in [false, true] {
            try scenario("glued photo up top, photos+file below", undoRedo: ur, body: "Wor\nType", audio: "memo_q554.m4a") { c, tv in
                tv.selectedRange = NSRange(location: tv.textStorage.length, length: 0)
                c.insertPhoto(self.photo()); self.settle()
                self.type("mid", tv)
                c.insertPhoto(self.photo()); self.settle()
                c.insertPhoto(self.photo()); self.settle()
                try self.file(c)
                self.backspace(before: "[[img_001]]", c, tv)
            }
        }
    }
    func testTypingAfterBlocks() throws {
        for ur in [false, true] {
            try scenario("text,photo,file,photo,text", undoRedo: ur) { c, tv in
                self.type("One line", tv); c.insertPhoto(self.photo()); self.settle(); try self.file(c)
                c.insertPhoto(self.photo()); self.settle(); self.type("tail", tv)
            }
        }
    }
}
