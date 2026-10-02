import XCTest
import Foundation
import AppKit
import CoreGraphics

/// Q143 (C119, D126, C25): what the Mac review needs to draw a capture like the phone —
/// image pixels, the PDF's first page + count, a thumbnail when its file exists, the typed
/// thought that leads a non-capture note, and an honest capture banner.
final class CaptureFactsTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-facts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func metadata(_ obj: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: obj)
    }

    private func capture(_ shared: [String: Any], extra: [String: Any] = [:]) -> PipelineFile {
        let pf = PipelineFile(id: UUID().uuidString, filename: "capture", path: dir.path, size: 0, sourceType: .capture)
        pf.audioMetadataJSON = metadata(["sharedContent": shared].merging(extra) { a, _ in a })
        return pf
    }

    private func writePNG(_ url: URL) throws {
        let img = NSImage(size: NSSize(width: 8, height: 6), flipped: false) { r in
            NSColor.systemTeal.setFill(); r.fill(); return true
        }
        let tiff = try XCTUnwrap(img.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    /// A real N-page PDF (blank pages with a rectangle on page 1) written with CoreGraphics.
    private func writePDF(_ url: URL, pages: Int) throws {
        var box = CGRect(x: 0, y: 0, width: 300, height: 400)
        let ctx = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for i in 0..<pages {
            ctx.beginPDFPage(nil)
            if i == 0 { ctx.setFillColor(NSColor.red.cgColor); ctx.fill(CGRect(x: 20, y: 20, width: 100, height: 100)) }
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    // MARK: image pixels

    func testImageCaptureListsItsPhotosInManifestOrder() throws {
        let images = dir.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try writePNG(images.appendingPathComponent("b.png"))
        try writePNG(images.appendingPathComponent("a.png"))
        try Data(#"[{"filename":"b.png","offsetSeconds":0},{"filename":"a.png","offsetSeconds":0},{"filename":"gone.png","offsetSeconds":0}]"#.utf8)
            .write(to: dir.appendingPathComponent("image_manifest.json"))
        let pf = capture(["type": "image", "fileName": "a.png"])
        XCTAssertEqual(pf.captureImageURLs.map(\.lastPathComponent), ["b.png", "a.png"],
                       "manifest order, files that exist only")
        XCTAssertNotNil(NSImage(contentsOf: try XCTUnwrap(pf.captureImageURLs.first)), "the pixels decode")
    }

    func testImageCaptureWithNoPhotosOnDiskHasNoUrls() {
        XCTAssertTrue(capture(["type": "image"]).captureImageURLs.isEmpty)
    }

    // MARK: PDF first page

    func testPDFFirstPageAndPageCount() throws {
        let url = dir.appendingPathComponent("doc.pdf")
        try writePDF(url, pages: 3)
        let page = try XCTUnwrap(CapturePDFPreview.firstPage(at: url, maxWidth: 200))
        XCTAssertEqual(page.pageCount, 3)
        XCTAssertEqual(page.image.size.width, 200, accuracy: 0.5)
        XCTAssertEqual(page.image.size.height, 200 * 400 / 300, accuracy: 0.5, "A4-ish aspect kept")
        XCTAssertEqual(CapturePDFPreview.pageCountLabel(3), "3 pages")
        XCTAssertEqual(CapturePDFPreview.pageCountLabel(1), "1 page")
    }

    func testNonPDFAndUnreadablePDFGiveNoPage() throws {
        let txt = dir.appendingPathComponent("a.txt")
        try Data("hi".utf8).write(to: txt)
        XCTAssertNil(CapturePDFPreview.firstPage(at: txt))
        let bad = dir.appendingPathComponent("bad.pdf")
        try Data("not a pdf".utf8).write(to: bad)
        XCTAssertNil(CapturePDFPreview.firstPage(at: bad))
    }

    func testCaptureDocumentURLFindsTheMaterializedFile() throws {
        let files = dir.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        try writePDF(files.appendingPathComponent("Report.pdf"), pages: 1)
        XCTAssertEqual(capture(["type": "file", "fileName": "Report.pdf"]).captureDocumentURL?.lastPathComponent,
                       "Report.pdf")
        let page = try XCTUnwrap(CapturePDFPreview.firstPage(
            at: try XCTUnwrap(capture(["type": "file"]).captureDocumentURL)))
        XCTAssertEqual(page.pageCount, 1)
    }

    // MARK: link thumbnail + description

    func testLinkDescriptionRidesTheBlobAndThumbnailResolvesFromTheFolder() throws {
        let pf = capture(["type": "url", "url": "https://example.com/p", "urlTitle": "A Post",
                          "urlDescription": "What the page says", "urlThumbnailUrl": "thumb_1.jpg"])
        XCTAssertEqual(pf.sharedContent?.urlDescription, "What the page says")
        XCTAssertNil(pf.captureThumbnailURL, "no file in the folder yet: the globe tile")
        try writePNG(dir.appendingPathComponent("thumb_1.jpg"))
        XCTAssertEqual(pf.captureThumbnailURL?.lastPathComponent, "thumb_1.jpg")
    }

    func testRemoteThumbnailUrlIsNeverFetched() {
        let pf = capture(["type": "url", "urlThumbnailUrl": "https://cdn.example.com/x.jpg"])
        XCTAssertNil(pf.captureThumbnailURL)
        XCTAssertNil(capture(["type": "url", "urlThumbnailUrl": "../escape.jpg"]).captureThumbnailURL)
    }

    // MARK: the typed thought leads a non-capture note

    func testAnnotationLeadOnANonCaptureNote() {
        let pf = PipelineFile(id: "v", filename: "v.m4a", path: dir.appendingPathComponent("original.m4a").path,
                              size: 0, sourceType: .audio)
        pf.audioMetadataJSON = metadata(["annotationText": "  Why I filmed this  "])
        XCTAssertEqual(pf.annotationLead, "Why I filmed this")
        pf.audioMetadataJSON = metadata(["annotationText": "   "])
        XCTAssertNil(pf.annotationLead, "blank is no lead")
        pf.audioMetadataJSON = metadata([:])
        XCTAssertNil(pf.annotationLead)
    }

    func testCaptureNeverDoublesItsAnnotationAsALead() {
        let pf = capture(["type": "text", "text": "q"], extra: ["annotationText": "my words"])
        XCTAssertNil(pf.annotationLead, "a capture's annotation IS its body")
    }

    // MARK: the honest banner

    func testBannerNeverClaimsPolishThatDidNotRun() {
        XCTAssertEqual(CaptureBannerCopy.polish(rated: false, enhanced: false), .unrated)
        XCTAssertEqual(CaptureBannerCopy.polish(rated: true, enhanced: false), .pending)
        XCTAssertEqual(CaptureBannerCopy.polish(rated: false, enhanced: true), .done)
        let unrated = CaptureBannerCopy.text(shared: .url, polish: .unrated)
        XCTAssertFalse(unrated.contains("still ran"))
        XCTAssertFalse(unrated.contains("Enhancement-lite ran"))
        XCTAssertTrue(unrated.contains("Not rated"))
        let pending = CaptureBannerCopy.text(shared: .image, polish: .pending)
        XCTAssertTrue(pending.contains("has not run yet"))
        let done = CaptureBannerCopy.text(shared: .text, polish: .done)
        XCTAssertTrue(done.contains("Enhancement-lite ran: title, tags, summary"))
        XCTAssertTrue(done.contains("blockquote"))
    }
}
