import PDFKit
import UIKit
import XCTest
@testable import SkriftMobile

/// Q463 (D212, D214, the Q462 mock): a highlight and its comment go into the PDF he shares as a
/// real PDF highlight annotation whose contents are the comment, read back by PDFKit from the
/// written file. The Library PDF is never altered; "Clean" shares it as imported.
final class PDFAnnotationExportTests: XCTestCase {

    private let line = "Sensor integration and field tests: €18,000"
    private let comment = "Ask Rui if the second test site is still Sines."

    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("q463_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    /// A generated three-page PDF with the budget line on page 2 (never one of his files).
    private func samplePDF() throws -> URL {
        let url = dir.appendingPathComponent("sample.pdf")
        let font = UIFont.systemFont(ofSize: 13)
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { ctx in
            for p in 1...3 {
                ctx.beginPage()
                ("Page \(p) heading" as NSString).draw(at: CGPoint(x: 56, y: 60), withAttributes: [.font: font])
                if p == 2 {
                    ((line + " covers two test sites") as NSString).draw(at: CGPoint(x: 56, y: 120), withAttributes: [.font: font])
                    ("Travel: €3,200" as NSString).draw(at: CGPoint(x: 56, y: 160), withAttributes: [.font: font])
                }
            }
        }
        try data.write(to: url)
        return url
    }

    private func highlight(comment: String?) -> SourceHighlight {
        SourceHighlight(text: line, page: 2, word: 0, comment: comment, commentedAt: comment == nil ? nil : Date())
    }

    func testCommentRoundTripsAsHighlightContentsOnItsPage() throws {
        let source = try samplePDF()
        let out = try PDFAnnotationExport.write(source: source, highlights: [highlight(comment: comment)],
                                                variant: .annotated, title: "GFR grant", into: dir.appendingPathComponent("share"))
        let doc = try XCTUnwrap(PDFDocument(url: out), "the written copy opens")
        let page2 = try XCTUnwrap(doc.page(at: 1))
        // PDFAnnotation.type is the subtype without its slash ("Highlight", "Text").
        let marks = page2.annotations.filter { $0.type == "Highlight" }
        XCTAssertFalse(marks.isEmpty, "page 2 carries a highlight annotation")
        XCTAssertTrue(marks.contains { $0.contents == comment }, "the highlight's contents are the comment")
        XCTAssertTrue(page2.annotations.contains { $0.type == "Text" && $0.contents == comment },
                      "a commented highlight gets a sticky-note pin in the margin")
        for i in [0, 2] {
            XCTAssertTrue(doc.page(at: i)?.annotations.isEmpty ?? false, "other pages stay clean")
        }
    }

    func testHighlightWithoutCommentHasNoContentsAndNoPin() throws {
        let source = try samplePDF()
        let out = try PDFAnnotationExport.write(source: source, highlights: [highlight(comment: "   ")],
                                                variant: .annotated, title: "GFR grant", into: dir.appendingPathComponent("share"))
        let page2 = try XCTUnwrap(PDFDocument(url: out)?.page(at: 1))
        XCTAssertFalse(page2.annotations.isEmpty, "the yellow is still written")
        XCTAssertTrue(page2.annotations.allSatisfy { $0.type == "Highlight" }, "no pin without a comment")
        XCTAssertTrue(page2.annotations.allSatisfy { ($0.contents ?? "").isEmpty })
    }

    func testTheLibraryFileIsNeverAltered() throws {
        let source = try samplePDF()
        let before = try Data(contentsOf: source)
        _ = try PDFAnnotationExport.write(source: source, highlights: [highlight(comment: comment)],
                                          variant: .annotated, title: "GFR grant", into: dir.appendingPathComponent("a"))
        _ = try PDFAnnotationExport.write(source: source, highlights: [highlight(comment: comment)],
                                          variant: .clean, title: "GFR grant", into: dir.appendingPathComponent("b"))
        XCTAssertEqual(try Data(contentsOf: source), before, "the Library PDF stays byte-for-byte as imported")
        XCTAssertTrue(PDFDocument(url: source)?.page(at: 1)?.annotations.isEmpty ?? false)
    }

    func testCleanShareIsTheFileAsImported() throws {
        let source = try samplePDF()
        let out = try PDFAnnotationExport.write(source: source, highlights: [highlight(comment: comment)],
                                                variant: .clean, title: "GFR grant", into: dir.appendingPathComponent("share"))
        XCTAssertEqual(out.lastPathComponent, "GFR grant.pdf")
        XCTAssertEqual(try Data(contentsOf: out), try Data(contentsOf: source))
    }

    func testAnnotatedCopyIsNamedAsTheMockShows() {
        XCTAssertEqual(PDFAnnotationExport.fileName(title: "GFR grant application, draft 3", variant: .annotated),
                       "GFR grant application, draft 3 (highlights).pdf")
        XCTAssertEqual(PDFAnnotationExport.fileName(title: "a/b", variant: .clean), "a-b.pdf", "no path separators")
    }

    func testCommentIsAdditiveAndOptionalInTheSyncedRecord() throws {
        // An older record (no comment keys) decodes; a commented one round-trips.
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"x","page":1,"word":0,"createdAt":0}"#
        let decoded = try JSONDecoder().decode(SourceHighlight.self, from: Data(old.utf8))
        XCTAssertNil(decoded.comment)
        XCTAssertNil(decoded.commentAudio)
        var h = decoded
        h.comment = comment
        h.commentAudio = "clip.m4a"
        let back = try JSONDecoder().decode(SourceHighlight.self, from: JSONEncoder().encode(h))
        XCTAssertEqual(back, h)
    }

    func testCommentingSetsAndClears() {
        let h = highlight(comment: nil)
        let set = SourceHighlights.commenting(h.id, comment: "  Ask Rui.  ", audio: nil, in: [h])
        XCTAssertEqual(set[0].comment, "Ask Rui.")
        XCTAssertNotNil(set[0].commentedAt)
        let cleared = SourceHighlights.commenting(h.id, comment: "", audio: nil, in: set)
        XCTAssertNil(cleared[0].comment)
        XCTAssertFalse(cleared[0].hasComment)
        let spoken = SourceHighlights.commenting(h.id, comment: "", audio: "a.m4a", in: [h])
        XCTAssertTrue(spoken[0].hasComment, "a spoken comment with no words heard keeps its audio (C274)")
    }

    func testMenuGainsCommentForPDFHighlights() {
        XCTAssertEqual(SourceMenu.pdfHighlightItems(hasComment: false), ["Copy", "Comment", "Remove highlight"])
        XCTAssertEqual(SourceMenu.pdfHighlightItems(hasComment: true), ["Copy", "Edit comment", "Remove highlight"])
    }
}
