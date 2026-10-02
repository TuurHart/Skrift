import XCTest

/// Q154 (C57, C196, R51): picture markers become embeds the SAME way on both exporters,
/// through the one shared `ExportProfile.convertPictureMarkers`. A portfolio note gets
/// `![](x)`, a vault note `![[x]]`; NNN resolves through the manifest; a dangling marker
/// (no entry, no file) is dropped, never printed. The phone runs a twin class of this name.
final class ExportImageMarkerParityTests: XCTestCase {
    private var work: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("q154-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
    }

    // MARK: - The shared converter

    func testSharedConverterWritesEachProfilesSyntax() {
        let md = "Look [[img_001]] here."
        let vault = ExportProfile.obsidian.convertPictureMarkers(md, manifest: ["a.jpg"], stem: "Trip")
        XCTAssertEqual(vault.markdown, "Look ![[Trip_001.jpg]] here.")
        let portfolio = ExportProfile.portfolio.convertPictureMarkers(md, manifest: ["a.jpg"], stem: "trip")
        XCTAssertEqual(portfolio.markdown, "Look ![](trip_001.jpg) here.")
        XCTAssertEqual(portfolio.placed, [PlacedPicture(source: "a.jpg", embedName: "trip_001.jpg")])
    }

    func testSharedConverterDropsADanglingMarker() {
        let r = ExportProfile.obsidian.convertPictureMarkers("A [[img_001]] B [[img_002]] C",
                                                             manifest: ["a.png"], stem: "N")
        XCTAssertEqual(r.markdown, "A ![[N_001.png]] B  C")
        XCTAssertEqual(r.placed.map(\.source), ["a.png"])
    }

    func testSharedConverterDropsAMarkerItCannotPlace() {
        let r = ExportProfile.portfolio.convertPictureMarkers("A [[img_001]] B", manifest: ["a.png"],
                                                              stem: "n") { _, _ in nil }
        XCTAssertEqual(r.markdown, "A  B")
        XCTAssertTrue(r.placed.isEmpty)
    }

    // MARK: - The Mac exporter

    /// A note folder with `images/` + `image_manifest.json`, the shape every Mac ingest writes.
    private func noteFolder(images: [String: Data], manifest: [String]?) throws -> URL {
        let folder = work.appendingPathComponent("note-\(UUID().uuidString)")
        let imagesDir = folder.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        for (name, data) in images { try data.write(to: imagesDir.appendingPathComponent(name)) }
        if let manifest {
            let entries = manifest.map { ImageManifestEntry(filename: $0, offsetSeconds: 0) }
            try JSONEncoder().encode(entries).write(to: folder.appendingPathComponent("image_manifest.json"))
        }
        let audio = folder.appendingPathComponent("original.m4a")
        try Data([1, 2, 3]).write(to: audio)
        return audio
    }

    private func vaultSettings() -> AppSettings {
        var s = AppSettings.default
        s.noteFolder = work.appendingPathComponent("vault").path
        s.portfolioRoot = work.appendingPathComponent("portfolio").path
        return s
    }

    func testMacPortfolioNoteGetsPlainMarkdownImage() throws {
        let audio = try noteFolder(images: ["img_001.jpg": Data([7])], manifest: ["img_001.jpg"])
        let pf = PipelineFile(id: UUID().uuidString, filename: "memo.m4a", path: audio.path, size: 3, sourceType: .audio)
        pf.enhancedTitle = "Lamp Idea"
        pf.destination = .idea
        pf.sanitised = "Sketch: [[img_001]] done."

        let r = try VaultExporter.export(pf, settings: vaultSettings())
        let md = try String(contentsOf: r.markdownURL, encoding: .utf8)
        let stem = r.markdownURL.deletingPathExtension().lastPathComponent
        XCTAssertTrue(md.contains("![](\(stem)_001.jpg)"), "portfolio embed must be ![](x): \(md)")
        XCTAssertFalse(md.contains("![["), "no wiki embed in a portfolio note")
        XCTAssertFalse(md.contains("[[img_"), "no literal marker")
        XCTAssertEqual(r.imageCount, 1)
        let beside = r.markdownURL.deletingLastPathComponent().appendingPathComponent("\(stem)_001.jpg")
        XCTAssertEqual(try Data(contentsOf: beside), Data([7]), "the picture sits beside the note")
    }

    func testMacMissingFileLeavesNothing() throws {
        // The manifest names two pictures; only the first reached the Mac.
        let audio = try noteFolder(images: ["img_001.jpg": Data([1])], manifest: ["img_001.jpg", "img_002.jpg"])
        let pf = PipelineFile(id: UUID().uuidString, filename: "memo.m4a", path: audio.path, size: 3, sourceType: .audio)
        pf.enhancedTitle = "Trip"
        pf.sanitised = "One [[img_001]] two [[img_002]] three [[img_009]] end."

        let r = try VaultExporter.export(pf, settings: vaultSettings())
        let md = try String(contentsOf: r.markdownURL, encoding: .utf8)
        XCTAssertTrue(md.contains("![[Trip_001.jpg]]"))
        XCTAssertFalse(md.contains("[[img_"), "a dangling marker is dropped, never printed: \(md)")
        XCTAssertFalse(md.contains("Trip_002"), "no embed for a picture that is not there")
        XCTAssertFalse(md.contains("Trip_009"))
        XCTAssertEqual(r.imageCount, 1)
    }

    func testMacNoteWithoutAnImagesFolderDropsItsMarker() throws {
        let folder = work.appendingPathComponent("bare")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let audio = folder.appendingPathComponent("original.m4a")
        try Data([1]).write(to: audio)
        let pf = PipelineFile(id: UUID().uuidString, filename: "memo.m4a", path: audio.path, size: 1, sourceType: .audio)
        pf.enhancedTitle = "Bare"
        pf.sanitised = "Before [[img_001]] after."

        let r = try VaultExporter.export(pf, settings: vaultSettings())
        let md = try String(contentsOf: r.markdownURL, encoding: .utf8)
        XCTAssertFalse(md.contains("[[img_"), "dangling marker printed: \(md)")
        XCTAssertEqual(r.imageCount, 0)
    }

    func testMacResolvesThroughTheManifestNotTheFilename() throws {
        // The manifest's FIRST entry is `b.jpg` — the phone's rule (N-th manifest entry) wins
        // over a filename or sort-order guess.
        let audio = try noteFolder(images: ["a.jpg": Data([0xA]), "b.jpg": Data([0xB])], manifest: ["b.jpg", "a.jpg"])
        let pf = PipelineFile(id: UUID().uuidString, filename: "memo.m4a", path: audio.path, size: 3, sourceType: .audio)
        pf.enhancedTitle = "Order"
        pf.sanitised = "[[img_001]]"

        let r = try VaultExporter.export(pf, settings: vaultSettings())
        let img = work.appendingPathComponent("vault/Skrift/Images/Order_001.jpg")
        XCTAssertEqual(try Data(contentsOf: img), Data([0xB]))
        XCTAssertEqual(r.imageCount, 1)
    }

    /// The Mac's converter writes exactly what the shared one does for the same note.
    func testMacConverterMatchesTheSharedConverter() throws {
        let audio = try noteFolder(images: ["p1.png": Data([1]), "p2.jpg": Data([2])], manifest: ["p1.png", "p2.jpg"])
        let imagesDir = audio.deletingLastPathComponent().appendingPathComponent("images")
        let md = "x [[img_002]] y [[img_001]] z [[img_003]]."
        for profile in [ExportProfile.obsidian, .portfolio] {
            let att = work.appendingPathComponent("att-\(UUID().uuidString)")
            let (mac, copied) = VaultExporter.convertImageMarkers(md, imagesDir: imagesDir, safe: "S",
                                                                  into: att, id: UUID(), profile: profile)
            let shared = profile.convertPictureMarkers(md, manifest: ["p1.png", "p2.jpg"], stem: "S")
            XCTAssertEqual(mac, shared.markdown)
            XCTAssertEqual(copied, 2)
        }
    }
}
