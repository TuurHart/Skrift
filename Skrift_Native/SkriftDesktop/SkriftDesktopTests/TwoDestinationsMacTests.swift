import XCTest
import Foundation

/// Q338 / D189 on the Mac: Personal or Portfolio, with idea / inspiration / project as plain
/// tags. The Mac exporter writes `<root>/_inbox/<slug>.md` with its media beside it and the
/// preset tags in `tags:`; the credit need keys on the inspiration tag; the portfolio profile has
/// no `summary:`; the stored values from the four-destination era decode as Portfolio + a tag.
/// The phone runs `TwoDestinationsTests` for the same rules.
final class TwoDestinationsMacTests: XCTestCase {
    private var work: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("q338-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: work) }

    private func settings() -> AppSettings {
        var s = AppSettings.default
        s.noteFolder = work.appendingPathComponent("vault").path
        s.portfolioRoot = work.appendingPathComponent("portfolio").path
        return s
    }

    private func row(tags: [String], destination: NoteDestination = .portfolio) throws -> PipelineFile {
        let folder = work.appendingPathComponent("note-\(UUID().uuidString)")
        let imagesDir = folder.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try Data([7]).write(to: imagesDir.appendingPathComponent("img_001.jpg"))
        let entries = [ImageManifestEntry(filename: "img_001.jpg", offsetSeconds: 0)]
        try JSONEncoder().encode(entries).write(to: folder.appendingPathComponent("image_manifest.json"))
        let audio = folder.appendingPathComponent("original.m4a")
        try Data([1, 2, 3]).write(to: audio)
        let pf = PipelineFile(id: UUID().uuidString, filename: "memo.m4a", path: audio.path, size: 3, sourceType: .audio)
        pf.enhancedTitle = "The bench outside Café Garrett"
        pf.enhancedSummary = "A bench worth copying."
        pf.sanitised = "A bench made of an oak slab. [[img_001]]"
        pf.destination = destination
        pf.tags = tags
        return pf
    }

    func testTwoDestinationsAndTheInboxFolder() {
        XCTAssertEqual(NoteDestination.allCases, [.personal, .portfolio])
        XCTAssertEqual(NoteDestination.portfolio.portfolioFolder, "_inbox")
        XCTAssertEqual(PortfolioTagPresets.all, ["idea", "inspiration", "project"])
    }

    func testOldStoredValuesDecodeAsPortfolioPlusThatTag() throws {
        for old in ["idea", "inspiration", "project"] {
            XCTAssertEqual(NoteDestination.decode(old).destination, .portfolio)
            XCTAssertEqual(NoteDestination.decode(old).legacyTag, old)
        }
        XCTAssertEqual(NoteDestination.decode("garbage").destination, .personal)

        let pf = try row(tags: ["lisbon"])
        pf.destinationRaw = "inspiration"
        XCTAssertEqual(pf.destination, .portfolio)
        XCTAssertTrue(pf.adoptLegacyDestination())
        XCTAssertEqual(pf.destinationRaw, "portfolio")
        XCTAssertEqual(pf.tags, ["lisbon", "inspiration"])
        XCTAssertFalse(pf.adoptLegacyDestination(), "idempotent")
    }

    func testMacPortfolioNoteLandsInInboxWithMediaBesideAndPresetTags() throws {
        let pf = try row(tags: ["idea", "inspiration"])
        let r = try VaultExporter.export(pf, settings: settings())

        let inbox = work.appendingPathComponent("portfolio/_inbox")
        XCTAssertEqual(r.markdownURL.deletingLastPathComponent().standardizedFileURL.path,
                       inbox.standardizedFileURL.path)
        XCTAssertEqual(r.markdownURL.lastPathComponent, "the-bench-outside-cafe-garrett.md")
        let beside = ["the-bench-outside-cafe-garrett.m4a", "the-bench-outside-cafe-garrett_001.jpg"]
        for name in beside {
            XCTAssertTrue(FileManager.default.fileExists(atPath: inbox.appendingPathComponent(name).path), name)
        }
        for gone in ["_ideas", "_inspiration", "_projects"] {
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: work.appendingPathComponent("portfolio/\(gone)").path), gone)
        }
        let md = try String(contentsOf: r.markdownURL, encoding: .utf8)
        XCTAssertTrue(md.contains("tags:\n  - idea\n  - inspiration"), md)
        XCTAssertTrue(md.contains("![](the-bench-outside-cafe-garrett_001.jpg)"), md)
    }

    func testCreditKeysOnTheInspirationTagAlone() throws {
        for (tags, wants) in [(["inspiration"], true), (["Inspiration", "idea"], true),
                              (["idea"], false), (["project"], false), ([], false)] as [([String], Bool)] {
            let pf = try row(tags: tags)
            let md = Compiler.compile(file: pf, author: "Me", date: "2026-10-11", profile: .portfolio)
            XCTAssertEqual(md.contains("  - credit"), wants, "tags \(tags)")
        }
    }

    func testPortfolioProfileHasNoSummaryButTheVaultKeepsIt() throws {
        let pf = try row(tags: ["idea"])
        let portfolio = Compiler.compile(file: pf, author: "Me", date: "2026-10-11", profile: .portfolio)
        XCTAssertFalse(portfolio.contains("summary:"), portfolio)
        let vault = Compiler.compile(file: pf, author: "Me", date: "2026-10-11", profile: .obsidian)
        XCTAssertTrue(vault.contains("summary: \"A bench worth copying.\""), vault)
    }

    func testAnOldStoredIdeaStillCompilesWithItsTag() throws {
        let pf = try row(tags: ["lisbon"])
        pf.destinationRaw = "idea"
        let md = Compiler.compile(file: pf, author: "Me", date: "2026-10-11", profile: .portfolio)
        XCTAssertTrue(md.contains("tags:\n  - lisbon\n  - idea"), md)
    }
}
