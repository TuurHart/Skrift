import XCTest

/// Q445 (C55, C56, C130, C193): a note whose body OPENS with a picture (`pic-at-start` in the
/// corpus) keeps its frontmatter. v1 ran the Q13 body fallback over the whole compiled markdown,
/// so the closing `---` was read as the sentence before the marker and fused onto the first
/// sentence; the file lost `skriftID`/`skriftHash` and was no longer recognised as ours.
final class PicAtStartExportTests: XCTestCase {
    private var work: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("q445-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
    }

    private func noteWithPicture(title: String, body: String, destination: NoteDestination) throws -> PipelineFile {
        let folder = work.appendingPathComponent("note-\(UUID().uuidString)")
        let imagesDir = folder.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try Data([7]).write(to: imagesDir.appendingPathComponent("img_001.jpg"))
        try JSONEncoder().encode([ImageManifestEntry(filename: "img_001.jpg", offsetSeconds: 0)])
            .write(to: folder.appendingPathComponent("image_manifest.json"))
        let audio = folder.appendingPathComponent("original.m4a")
        try Data([1, 2, 3]).write(to: audio)
        let pf = PipelineFile(id: UUID().uuidString, filename: "memo.m4a", path: audio.path, size: 3, sourceType: .audio)
        pf.enhancedTitle = title
        pf.destination = destination
        pf.sanitised = body
        return pf
    }

    private func settings() -> AppSettings {
        var s = AppSettings.default
        s.noteFolder = work.appendingPathComponent("vault").path
        s.portfolioRoot = work.appendingPathComponent("portfolio").path
        return s
    }

    private func assertFrontmatterIntact(_ md: String, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let lines = md.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "---", "\(label): opens with a fence", file: file, line: line)
        XCTAssertTrue(lines.dropFirst().contains("---"), "\(label): the closing --- is on its own line:\n\(md)", file: file, line: line)
        guard let fm = VaultStamp.frontmatter(md) else {
            return XCTFail("\(label): the frontmatter does not parse:\n\(md)", file: file, line: line)
        }
        XCTAssertNotNil(VaultStamp.value(of: VaultStamp.idKey, in: fm), "\(label): skriftID", file: file, line: line)
        XCTAssertFalse((VaultStamp.value(of: VaultStamp.hashKey, in: fm) ?? "").isEmpty, "\(label): skriftHash", file: file, line: line)
        XCTAssertFalse(md.contains("--- "), "\(label): nothing fused onto the fence", file: file, line: line)
    }

    func testBodyOpeningWithAPictureKeepsItsFrontmatterOnBothProfiles() throws {
        let body = "[[img_001]] This is what the blue looks like at cone five.\n\nThen a second thought."
        for (destination, label) in [(NoteDestination.personal, "vault"), (.portfolio, "portfolio")] {
            let pf = try noteWithPicture(title: "Blue Glaze", body: body, destination: destination)
            let r = try VaultExporter.export(pf, settings: settings())
            let md = try String(contentsOf: r.markdownURL, encoding: .utf8)
            assertFrontmatterIntact(md, label)
            XCTAssertTrue(md.contains("This is what the blue looks like at cone five."), "\(label): words kept")
            XCTAssertFalse(md.contains("[[img_"), "\(label): no literal marker")
            // The picture still sits ahead of its sentence, as its own paragraph.
            let embed = destination == .portfolio ? "![](" : "![["
            let parts = md.components(separatedBy: "\n---\n")
            XCTAssertEqual(parts.count, 2, "\(label): exactly one closing fence")
            XCTAssertTrue(parts.last?.trimmingCharacters(in: .newlines).hasPrefix(embed) == true,
                          "\(label): the body opens with the picture:\n\(md)")
        }
    }

    func testExportingTwiceWritesNothingTheSecondTime() throws {
        // C55: the stamp survives, so the second export is recognised as ours and unchanged.
        let pf = try noteWithPicture(title: "Again", body: "[[img_001]] Opening line.", destination: .personal)
        let first = try VaultExporter.export(pf, settings: settings())
        let second = try VaultExporter.export(pf, settings: settings())
        XCTAssertEqual(first.markdownURL, second.markdownURL, "one file, not a collision copy")
        if case .unchanged = second.outcome {} else { XCTFail("second export should be unchanged, got \(second.outcome)") }
    }
}
