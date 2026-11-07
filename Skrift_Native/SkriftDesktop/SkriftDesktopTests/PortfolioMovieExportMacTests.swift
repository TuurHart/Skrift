import XCTest
import Foundation

/// Q557 (D227): the Mac is the only Portfolio exporter, so the Mac owns what the deleted phone
/// `PortfolioExportTests` held. A Portfolio note with a kept movie writes the `.mov` beside the
/// note in `_inbox/`; a note whose movie is not on this Mac still exports its text; the portfolio
/// is not a vault (no `Skrift`, `Images`, `Recordings` folders); a portfolio note carries
/// `capture:` + `voice:` and never `source:`, `type:` or `author:` (SPEC C130); a typed note says
/// `voice: written`. Real `VaultExporter.export` calls on temp folders only.
final class PortfolioMovieExportMacTests: XCTestCase {
    private var work: URL!
    private var portfolio: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("q557-\(UUID().uuidString)")
        portfolio = work.appendingPathComponent("portfolio")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: work) }

    private func settings() -> AppSettings {
        var s = AppSettings.default
        s.noteFolder = work.appendingPathComponent("vault").path
        s.portfolioRoot = portfolio.path
        s.authorName = "Tiuri Hartog"
        return s
    }

    /// A Portfolio audio note whose working folder holds `original.m4a`, plus `source.mov` when
    /// `movie` is non-nil (what `IngestService` leaves beside the extracted audio of a video).
    private func videoRow(movie: Data?) throws -> PipelineFile {
        let folder = work.appendingPathComponent("note-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let audio = folder.appendingPathComponent("original.m4a")
        try Data([1, 2, 3]).write(to: audio)
        if let movie { try movie.write(to: folder.appendingPathComponent("source.mov")) }
        let pf = PipelineFile(id: UUID().uuidString, filename: "IMG_0042.mov", path: audio.path, size: 3,
                              sourceType: .audio)
        pf.enhancedTitle = "The bench outside Café Garrett"
        pf.sanitised = "A bench made of an oak slab."
        pf.destination = .portfolio
        return pf
    }

    private func exists(_ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: portfolio.appendingPathComponent(rel).path)
    }

    func testKeptMovieLandsBesideTheNoteInInbox() throws {
        let bytes = Data((0..<64).map { UInt8($0) })
        let pf = try videoRow(movie: bytes)
        let r = try VaultExporter.export(pf, settings: settings())

        let inbox = portfolio.appendingPathComponent("_inbox")
        XCTAssertEqual(r.markdownURL.deletingLastPathComponent().standardizedFileURL.path,
                       inbox.standardizedFileURL.path)
        XCTAssertEqual(r.markdownURL.lastPathComponent, "the-bench-outside-cafe-garrett.md")
        let mov = inbox.appendingPathComponent("the-bench-outside-cafe-garrett.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: mov.path), "movie beside the note")
        XCTAssertEqual(try Data(contentsOf: mov), bytes, "the kept movie's own bytes, not a stub")
    }

    func testNoteWhoseMovieIsNotOnThisMacStillExportsItsText() throws {
        let pf = try videoRow(movie: nil)
        let r = try VaultExporter.export(pf, settings: settings())

        XCTAssertTrue(exists("_inbox/the-bench-outside-cafe-garrett.md"))
        let md = try String(contentsOf: r.markdownURL, encoding: .utf8)
        XCTAssertTrue(md.contains("A bench made of an oak slab."), md)
        XCTAssertFalse(exists("_inbox/the-bench-outside-cafe-garrett.mov"), "no movie to copy, none invented")
        let all = (FileManager.default.enumerator(atPath: portfolio.path)?.allObjects as? [String]) ?? []
        XCTAssertTrue(all.filter { $0.hasSuffix(".mov") }.isEmpty, "\(all)")
    }

    func testThePortfolioIsNotAVault() throws {
        let pf = try videoRow(movie: Data([9, 9, 9]))
        _ = try VaultExporter.export(pf, settings: settings())

        for unwanted in ["Skrift", "Images", "Recordings",
                         "_inbox/Skrift", "_inbox/Images", "_inbox/Recordings"] {
            XCTAssertFalse(exists(unwanted), "the portfolio is not a vault: found \(unwanted)")
        }
        // The audio rides beside the note too, same basename.
        XCTAssertTrue(exists("_inbox/the-bench-outside-cafe-garrett.m4a"))
    }

    /// SPEC C130: a portfolio note WRITES `capture:` and `voice:`; it never writes `source:`,
    /// `type:` or `author:`. (Q557's brief said "no `capture:` key"; C130 and the code say the
    /// opposite, so this asserts the spec.)
    func testFrontmatterKeysOfAPortfolioNote() throws {
        let pf = try videoRow(movie: Data([9]))
        let r = try VaultExporter.export(pf, settings: settings())
        let md = try String(contentsOf: r.markdownURL, encoding: .utf8)
        let lines = md.components(separatedBy: "\n")

        XCTAssertTrue(lines.contains { $0.hasPrefix("capture: ") }, md)
        XCTAssertTrue(lines.contains { $0.hasPrefix("voice: ") }, md)
        for key in ["source:", "type:", "author:", "summary:"] {
            XCTAssertFalse(lines.contains { $0.hasPrefix(key) }, "\(key) must not be written\n\(md)")
        }
        XCTAssertFalse(md.contains("![["), "a vault-relative embed does not travel")
    }

    func testAVoiceMemoSaysCaptureVoiceMemo() throws {
        let pf = try videoRow(movie: nil)
        pf.filename = "memo.m4a"
        let r = try VaultExporter.export(pf, settings: settings())
        let md = try String(contentsOf: r.markdownURL, encoding: .utf8)
        XCTAssertTrue(md.contains("\ncapture: Voice-memo\n"), md)
    }

    /// A typed note was never spoken: `voice: written`, and the exported file says so on disk.
    func testTypedPortfolioNoteSaysVoiceWritten() throws {
        let marker = try JSONSerialization.data(withJSONObject: ["mediaSource": "typed"], options: [.sortedKeys])
        let memo = Memo(recordedAt: Date(), title: "Lamp parts", transcript: "Buy the brass fittings.",
                        transcriptStatus: .done, significance: 0.5, metadataData: marker)
        let pf = MemoNoteProjection.file(for: memo)
        pf.destination = .portfolio
        let r = try VaultExporter.export(pf, settings: settings())

        let md = try String(contentsOf: r.markdownURL, encoding: .utf8)
        XCTAssertTrue(md.contains("\nvoice: written\n"), md)
        XCTAssertTrue(md.contains("\ncapture: Typed-note\n"), md)
        XCTAssertEqual(r.markdownURL.deletingLastPathComponent().lastPathComponent, "_inbox")
    }
}
