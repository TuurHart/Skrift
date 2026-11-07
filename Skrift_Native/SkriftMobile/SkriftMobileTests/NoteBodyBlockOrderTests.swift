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

    private func editor(_ body: String = "") -> (NoteBodyView.Coordinator, NoteBodyTextView, Memo) {
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

    func testProbeTextPhotoLibraryPhotoFileThenDone() throws {
        let (c, tv, memo) = editor()
        type("Hello world", tv)
        c.insertPhoto(photo()); settle()
        let s1 = memo.transcript ?? ""
        c.insertPhoto(photo()); settle()
        let s2 = memo.transcript ?? ""
        try file(c)
        let before = memo.transcript ?? ""
        let shown = c.reconstruct(tv.attributedText)
        c.finishEditing(); settle()
        c.textViewDidEndEditing(tv); settle()
        let after = memo.transcript ?? ""
        print("Q554 s1 \(s1.debugDescription)")
        print("Q554 s2 \(s2.debugDescription)")
        print("Q554 before \(before.debugDescription)")
        print("Q554 shown \(shown.debugDescription)")
        print("Q554 after \(after.debugDescription)")
        XCTAssertEqual(order(after), order(before))
    }
}
