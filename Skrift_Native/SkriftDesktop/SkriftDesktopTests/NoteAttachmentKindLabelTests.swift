import XCTest
import Foundation

/// Q396 (D202, C239): the file card's kind word comes from one fixed extension table in Shared,
/// so a DXF reads "DXF drawing" on the phone, the Mac and in the Q384 mock. The system's own
/// type description (which differs per platform and OS version) is never consulted.
final class NoteAttachmentKindLabelTests: XCTestCase {

    private func file(_ name: String, uti: String = "public.data") -> NoteAttachmentEntry {
        NoteAttachmentEntry(kind: NoteAttachment.Kind.file, filename: "file_x_001." + (name as NSString).pathExtension,
                            name: name, uti: uti, byteCount: 4096)
    }

    func testCADAndPrintTypesHaveTheirOwnWords() {
        XCTAssertEqual(NoteAttachment.kindLabel(file("loom.dxf")), "DXF drawing")
        XCTAssertEqual(NoteAttachment.kindLabel(file("plan.dwg")), "DWG drawing")
        XCTAssertEqual(NoteAttachment.kindLabel(file("bracket.step")), "STEP model")
        XCTAssertEqual(NoteAttachment.kindLabel(file("bracket.stp")), "STEP model")
        XCTAssertEqual(NoteAttachment.kindLabel(file("fan.stl")), "STL model")
        XCTAssertEqual(NoteAttachment.kindLabel(file("fan.3mf")), "3MF model")
        XCTAssertEqual(NoteAttachment.kindLabel(file("fan.obj")), "OBJ model")
        XCTAssertEqual(NoteAttachment.kindLabel(file("part.gcode")), "G-code file")
    }

    func testOfficeAndDocumentTypes() {
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.pdf")), "PDF document")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.docx")), "Word document")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.doc")), "Word document")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.xlsx")), "Excel spreadsheet")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.csv")), "CSV spreadsheet")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.pptx")), "PowerPoint presentation")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.key")), "Keynote presentation")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.pages")), "Pages document")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.numbers")), "Numbers spreadsheet")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.txt")), "Text file")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.md")), "Markdown file")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.rtf")), "Rich text document")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.epub")), "ePub book")
    }

    func testImageAudioArchiveTypes() {
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.png")), "PNG image")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.jpg")), "JPEG image")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.jpeg")), "JPEG image")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.heic")), "HEIC image")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.svg")), "SVG image")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.mp3")), "MP3 audio")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.m4a")), "M4A audio")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.wav")), "WAV audio")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.zip")), "ZIP archive")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.7z")), "7Z archive")
    }

    /// Same words whatever the system says about the type, and whatever case the name has.
    func testTheSystemTypeAndTheCaseDoNotChangeTheWord() {
        XCTAssertEqual(NoteAttachment.kindLabel(file("LOOM.DXF", uti: "com.autodesk.dxf")), "DXF drawing")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.pdf", uti: "com.adobe.pdf")), "PDF document")
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.dxf", uti: "dyn.ah62d4rv4ge80c6dq")), "DXF drawing")
    }

    func testUnknownIsTheUppercaseExtensionAndFile() {
        XCTAssertEqual(NoteAttachment.kindLabel(file("a.qzx")), "QZX file")
        XCTAssertEqual(NoteAttachment.kindLabel(file("noext")), "File")
    }

    func testVideoIsVideoAndTheSubtitleUsesTheLabel() {
        let v = NoteAttachmentEntry(kind: NoteAttachment.Kind.video, filename: "video_x_001.mov", name: "clip.mov",
                                    uti: "com.apple.quicktime-movie", byteCount: 1_000_000, durationSeconds: 42)
        XCTAssertEqual(NoteAttachment.kindLabel(v), "Video")
        XCTAssertTrue(NoteAttachment.subtitle(file("loom.dxf")).hasPrefix("DXF drawing · "))
        XCTAssertEqual(NoteAttachment.capturedFileCard(name: "loom.dxf", byteCount: nil).subtitle, "DXF drawing")
    }
}
