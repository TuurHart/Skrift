import XCTest
@testable import SkriftMobile

/// Q154 (C57, C196, R51): the phone's `convertPhotoMarkers` is the shared
/// `ExportProfile.convertPictureMarkers` — a portfolio note gets `![](x)`, a vault note
/// `![[x]]`, a dangling marker leaves nothing. The Mac runs a twin class of this name.
final class ExportImageMarkerParityTests: XCTestCase {
    private let manifest = [ImageManifestEntry(filename: "a.jpg", offsetSeconds: 0),
                            ImageManifestEntry(filename: "b.png", offsetSeconds: 4)]

    func testPortfolioNoteGetsPlainMarkdownImage() {
        let (out, resolved) = ObsidianPublisher.convertPhotoMarkers(
            "Sketch [[img_001]] done.", manifest: manifest, stem: "lamp-idea", profile: .portfolio)
        XCTAssertEqual(out, "Sketch ![](lamp-idea_001.jpg) done.")
        XCTAssertEqual(resolved.map(\.1), ["lamp-idea_001.jpg"])
    }

    func testVaultNoteGetsWikiEmbed() {
        let (out, _) = ObsidianPublisher.convertPhotoMarkers(
            "Sketch [[img_002]] done.", manifest: manifest, stem: "Lamp", profile: .obsidian)
        XCTAssertEqual(out, "Sketch ![[Lamp_002.png]] done.")
    }

    func testMissingFileLeavesNothing() {
        let (out, resolved) = ObsidianPublisher.convertPhotoMarkers(
            "A [[img_003]] B", manifest: manifest, stem: "N", profile: .portfolio)
        XCTAssertEqual(out, "A  B")
        XCTAssertTrue(resolved.isEmpty)
    }

    func testPhoneMatchesTheSharedConverter() {
        let md = "x [[img_002]] y [[img_001]] z [[img_009]]."
        for profile in [ExportProfile.obsidian, .portfolio] {
            let (phone, resolved) = ObsidianPublisher.convertPhotoMarkers(md, manifest: manifest, stem: "S", profile: profile)
            let shared = profile.convertPictureMarkers(md, manifest: manifest.map(\.filename), stem: "S")
            XCTAssertEqual(phone, shared.markdown)
            XCTAssertEqual(resolved.map(\.0), shared.placed.map(\.source))
            XCTAssertEqual(resolved.map(\.1), shared.placed.map(\.embedName))
        }
    }
}
