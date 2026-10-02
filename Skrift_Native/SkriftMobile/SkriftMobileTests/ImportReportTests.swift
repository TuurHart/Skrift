import XCTest
@testable import SkriftMobile

/// Q137 / C199 / C202: what an import skipped or failed is REPORTED, with the reason, on the
/// phone. The Mac twin (`SkriftDesktopTests/ImportReportTests.swift`) carries the same
/// pure-report table and the Mac ingest cases.
@MainActor
final class ImportReportTests: XCTestCase {
    override func setUp() async throws { ImportReportBridge.shared.dismiss() }
    override func tearDown() async throws { ImportReportBridge.shared.dismiss() }

    func testHeadlineAndLines() {
        var r = ImportReport(created: 2)
        XCTAssertFalse(r.hasProblems)
        XCTAssertNil(r.banner, "a clean import shows nothing: the new notes are the confirmation")
        XCTAssertEqual(r.headline, "Imported 2 notes")
        r.addSkipped("a.zip", "Skrift does not take .zip files")
        r.addFailed("v.mov", ImportReport.noAudioTrack)
        XCTAssertEqual(r.headline, "Imported 2 notes · skipped 1 · failed 1")
        XCTAssertEqual(r.bannerLines(), ["v.mov: Video had no audio track",
                                         "a.zip: Skrift does not take .zip files"], "failures first")
        XCTAssertNotNil(r.banner)
    }

    func testBannerLinesAreCapped() {
        var r = ImportReport()
        for i in 0..<7 { r.addSkipped("f\(i).zip", "no") }
        XCTAssertEqual(r.bannerLines(limit: 4).count, 5)
        XCTAssertEqual(r.bannerLines(limit: 4).last, "and 3 more")
        XCTAssertEqual(ImportReport().headline, "Nothing imported")
    }

    func testSkipReasonFollowsTheKind() {
        XCTAssertEqual(ImportReport.skipReason(forName: "x.zip", onMac: false), "Skrift does not take .zip files")
        XCTAssertEqual(ImportReport.skipReason(forName: "x", onMac: false),
                       "Skrift does not take files without an extension")
        XCTAssertEqual(ImportReport.skipReason(forName: "x.epub", onMac: false), ImportReport.book)
    }

    func testMergeAddsEverything() {
        var a = ImportReport(created: 1)
        var b = ImportReport(created: 2)
        b.addSkipped("s", "r")
        a.merge(b)
        XCTAssertEqual(a.created, 3)
        XCTAssertEqual(a.skipped.count, 1)
    }

    /// C199: a file Open-in cannot take used to vanish; now the list banner names it and why.
    func testUnsupportedFileIsReported() {
        AppURLHandler.handle(URL(fileURLWithPath: "/tmp/archive.zip"))
        let r = ImportReportBridge.shared.report
        XCTAssertEqual(r?.skipped, [.init(name: "archive.zip", reason: "Skrift does not take .zip files")])
        XCTAssertEqual(r?.created, 0)
    }

    /// An ePub / audiobook through Open-in is said to belong to the Books tab.
    func testBookFileIsSaidNotDropped() {
        AppURLHandler.handle(URL(fileURLWithPath: "/tmp/novel.epub"))
        XCTAssertEqual(ImportReportBridge.shared.report?.skipped.first?.reason, ImportReport.book)
    }

    /// A batch (the Files picker) is ONE report, and a deep link or empty report leaves it be.
    func testBatchIsOneReportAndDeepLinksChangeNothing() {
        AppURLHandler.handle(batch: [URL(fileURLWithPath: "/tmp/a.zip"), URL(fileURLWithPath: "/tmp/b.rar")])
        XCTAssertEqual(ImportReportBridge.shared.report?.skipped.map(\.name), ["a.zip", "b.rar"])
        AppURLHandler.handle(URL(string: "https://example.com")!)
        XCTAssertEqual(ImportReportBridge.shared.report?.skipped.count, 2, "a non-file URL reports nothing")
        ImportReportBridge.shared.dismiss()
        XCTAssertNil(ImportReportBridge.shared.report)
    }
}
