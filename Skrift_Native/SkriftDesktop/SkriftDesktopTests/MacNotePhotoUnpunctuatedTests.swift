import XCTest
import Foundation

/// Q552: a voice note whose paragraphs end without punctuation, with a picture already in it.
/// Adding another picture on the Mac (`NotePhoto.inserting`, called from BodyTextView.addPhoto)
/// must keep every paragraph and the old picture where they are. The phone had this fault
/// (Q547, Q551): `BodyV2.committed` read the old picture after an unpunctuated paragraph as
/// mid-sentence and glued the paragraphs around it.
final class MacNotePhotoUnpunctuatedTests: XCTestCase {

    private let note = "first thought\n\nsecond thought\n\n[[img_001]]\n\nthird thought"

    private func paragraphs(_ s: String) -> [String] {
        s.components(separatedBy: "\n\n")
    }

    private func assertKeptEverything(_ stored: String, newMarker: String,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let parts = paragraphs(stored)
        for want in ["first thought", "second thought", "[[img_001]]", "third thought", newMarker] {
            XCTAssertTrue(parts.contains(want), "\"\(want)\" is not its own paragraph in: \(stored.debugDescription)",
                          file: file, line: line)
        }
        func idx(_ s: String) -> Int { parts.firstIndex(of: s) ?? -1 }
        XCTAssertLessThan(idx("first thought"), idx("second thought"), file: file, line: line)
        XCTAssertLessThan(idx("second thought"), idx("[[img_001]]"), file: file, line: line)
        XCTAssertLessThan(idx("[[img_001]]"), idx("third thought"), file: file, line: line)
        XCTAssertEqual(parts.count, 5, "four old paragraphs/pictures plus the new picture: \(stored.debugDescription)",
                       file: file, line: line)
    }

    func testSecondPictureWithTheCaretAtTheEnd() {
        let r = NotePhoto.inserting(number: 2, into: note, atOffset: (note as NSString).length, manifestCount: 2)
        print("Q552 caret at end  ->", r.text.debugDescription)
        assertKeptEverything(r.text, newMarker: "[[img_002]]")
        XCTAssertEqual(r.text, note + "\n\n[[img_002]]")
    }

    func testSecondPictureWithTheCaretMidSentence() {
        let caret = (note as NSString).range(of: "third").location + 3        // "thi|rd thought"
        let r = NotePhoto.inserting(number: 2, into: note, atOffset: caret, manifestCount: 2)
        print("Q552 caret mid      ->", r.text.debugDescription)
        assertKeptEverything(r.text, newMarker: "[[img_002]]")
    }

    func testSecondPictureWithTheCaretMidSentenceInAnEarlierParagraph() {
        let caret = (note as NSString).range(of: "second").location + 3       // "sec|ond thought"
        let r = NotePhoto.inserting(number: 2, into: note, atOffset: caret, manifestCount: 2)
        print("Q552 caret mid, 2nd ->", r.text.debugDescription)
        assertKeptEverything(r.text, newMarker: "[[img_002]]")
    }

    func testSecondPictureAtAParagraphBoundaryBeforeTheOldPicture() {
        let caret = (note as NSString).range(of: "\n\n[[img_001]]").location  // end of "second thought"
        let r = NotePhoto.inserting(number: 2, into: note, atOffset: caret, manifestCount: 2)
        print("Q552 caret boundary ->", r.text.debugDescription)
        assertKeptEverything(r.text, newMarker: "[[img_002]]")
    }

    /// `BodyTextView.textDidEndEditing` (the typed commit): no manifest is passed down, so the
    /// marker is inert text and only whitespace is normalised. The shape must come back unchanged.
    func testTheTypedCommitLeavesTheShapeAlone() {
        for text in [note, note + "\n\n[[img_002]]",
                     "first thought\n\n[[img_001]]\n\nsecond thought\n\n[[img_002]]\n\nthird thought"] {
            let out = BodyV2.committed(BodyV2.Input(text: text, source: .typed))
            print("Q552 typed commit   ->", out.debugDescription)
            XCTAssertEqual(out, text)
        }
    }

    /// The same commit with the manifest known (the capture drainer, the Mac ingest).
    func testTheTypedCommitWithAManifestLeavesTheShapeAlone() {
        let two = Array(repeating: ImageManifestEntry(filename: "", offsetSeconds: 0), count: 2)
        let text = note + "\n\n[[img_002]]"
        let out = BodyV2.committed(BodyV2.Input(text: text, manifest: two, source: .typed, userEdited: true))
        print("Q552 typed+manifest ->", out.debugDescription)
        XCTAssertEqual(out, text)
    }
}
