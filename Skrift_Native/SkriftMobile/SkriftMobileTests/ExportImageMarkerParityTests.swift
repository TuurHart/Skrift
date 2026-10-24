import XCTest
@testable import SkriftMobile

/// Q154 (C57, C196, R51): the phone converts picture markers through export v2's one converter
/// (`ExportV2.convertPictures`) — a portfolio note gets `![](x)`, a vault note `![[x]]`, a
/// dangling marker leaves nothing. The Mac runs a twin class of this name.
final class ExportImageMarkerParityTests: XCTestCase {
    private let manifest = [ImageManifestEntry(filename: "a.jpg", offsetSeconds: 0),
                            ImageManifestEntry(filename: "b.png", offsetSeconds: 4)]

    func testPortfolioNoteGetsPlainMarkdownImage() {
        let (out, resolved) = ExportV2Test.convertPictures(
            "Sketch [[img_001]] done.", manifest: manifest, stem: "lamp-idea", profile: .portfolio)
        XCTAssertEqual(out, "Sketch ![](lamp-idea_001.jpg) done.")
        XCTAssertEqual(resolved.map(\.1), ["lamp-idea_001.jpg"])
    }

    func testVaultNoteGetsWikiEmbed() {
        let (out, _) = ExportV2Test.convertPictures(
            "Sketch [[img_002]] done.", manifest: manifest, stem: "Lamp", profile: .obsidian)
        XCTAssertEqual(out, "Sketch ![[Lamp_002.png]] done.")
    }

    func testMissingFileLeavesNothing() {
        let (out, resolved) = ExportV2Test.convertPictures(
            "A [[img_003]] B", manifest: manifest, stem: "N", profile: .portfolio)
        XCTAssertEqual(out, "A  B")
        XCTAssertTrue(resolved.isEmpty)
    }
}
