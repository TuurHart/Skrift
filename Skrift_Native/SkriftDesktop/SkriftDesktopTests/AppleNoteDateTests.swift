import XCTest
import SwiftData

/// Q141 / C76 / D18: an Apple Note import is dated by the note's OWN creation date when the
/// export carries one, else it is date-unknown — never the import moment, and never the export
/// folder's file dates (all export-time).
@MainActor
final class AppleNoteDateTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("q141_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: PipelineFile.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func local(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
        return Calendar.current.date(from: c)!
    }

    private func ingest(_ body: String, name: String = "Note A.md") async throws -> PipelineFile {
        let url = dir.appendingPathComponent(name)
        try Data(body.utf8).write(to: url)
        // The export folder's own file dates are export-time: a date read from THEM must not count.
        let created = try await IngestService(outputDir: dir.appendingPathComponent("out"))
            .ingest(localURLs: [url], into: try context())
        return try XCTUnwrap(created.first)
    }

    // MARK: - the export carries no date (the built-in Markdown export)

    func testNoDateInTheExportIsDateUnknownNeverTheImportMoment() async throws {
        let before = Date()
        let pf = try await ingest("# Tram idea\n\nglaze as a map\n")
        XCTAssertEqual(pf.uploadedAt, MemoDate.unknown, "no creation date → the unknown sentinel")
        XCTAssertTrue(MemoDate.isUnknown(pf.uploadedAt))
        XCTAssertLessThan(pf.uploadedAt, before.addingTimeInterval(-86_400 * 365), "nowhere near the import moment")
        XCTAssertEqual(MemoDate.label(pf.uploadedAt), "Date unknown")
        XCTAssertEqual(MemoDate.group(pf.uploadedAt), "Date unknown")
    }

    func testTheExportFolderFileDatesDoNotDateTheNote() async throws {
        let url = dir.appendingPathComponent("Old.md")
        try Data("# Old\n\nbody\n".utf8).write(to: url)
        let aged = local(2019, 3, 4, 5, 6, 7)
        try FileManager.default.setAttributes([.creationDate: aged, .modificationDate: aged], ofItemAtPath: url.path)
        let pf = try XCTUnwrap(try await IngestService(outputDir: dir.appendingPathComponent("out"))
            .ingest(localURLs: [url], into: try context()).first)
        XCTAssertEqual(pf.uploadedAt, MemoDate.unknown, "file dates are export time, not the note's")
    }

    // MARK: - the export carries one

    func testFrontMatterCreatedDatesTheNote() async throws {
        let pf = try await ingest("---\ncreated: 2026-09-14T10:15:30\ntags: [a]\n---\n# Caldo verde\n\nsoup\n")
        XCTAssertEqual(pf.uploadedAt, local(2026, 9, 14, 10, 15, 30))
        XCTAssertFalse(MemoDate.isUnknown(pf.uploadedAt))
    }

    func testFrontMatterISOWithZoneKeepsTheInstant() async throws {
        let pf = try await ingest("---\nCreation Date: \"2026-09-14T10:15:30Z\"\n---\n# T\n\nb\n")
        XCTAssertEqual(pf.uploadedAt, ISO8601DateFormatter().date(from: "2026-09-14T10:15:30Z"))
    }

    func testCreatedLineAtTheTopDatesTheNote() async throws {
        let pf = try await ingest("# Pastéis\n\nCreated: 2026-01-02 08:30\n\nrecipe\n")
        XCTAssertEqual(pf.uploadedAt, local(2026, 1, 2, 8, 30, 0))
    }

    func testParserShapes() {
        XCTAssertEqual(IngestService.appleNoteCreationDate("created: 2026-05-06\n# T"), local(2026, 5, 6, 0, 0, 0))
        XCTAssertEqual(IngestService.appleNoteCreationDate("Created: Monday, 14 September 2026 at 10:00:00\n"),
                       local(2026, 9, 14, 10, 0, 0))
        XCTAssertNil(IngestService.appleNoteCreationDate("# T\n\nno date here\n"))
        XCTAssertNil(IngestService.appleNoteCreationDate("# T\n\nCreated: yesterday-ish\n"), "unparseable → unknown")
        // A "created" line deep in the body is prose, not metadata.
        let deep = (0..<20).map { _ in "line" }.joined(separator: "\n") + "\nCreated: 2026-05-06\n"
        XCTAssertNil(IngestService.appleNoteCreationDate(deep))
    }

    func testUnknownLabelNeverReadsAsARealDay() {
        XCTAssertEqual(MemoDate.label(MemoDate.unknown), "Date unknown")
        XCTAssertNotEqual(MemoDate.label(Date()), "Date unknown")
        XCTAssertTrue(MemoDate.unknown < Date(timeIntervalSince1970: 86_400), "sorts last in a newest-first list")
    }
}
