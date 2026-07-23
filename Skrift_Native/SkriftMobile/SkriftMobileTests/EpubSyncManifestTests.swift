import XCTest
@testable import SkriftMobile

/// The attached-text (ePub) sync manifest — `"<index>:<byteSize>:<filename>"`
/// joined with "|". It doubles as the change-signature, so its round-trip has to
/// survive the filenames people actually have (spaces, colons, dots).
final class EpubSyncManifestTests: XCTestCase {

    func testManifestRoundTripsNamesInOrder() {
        let names = ["The Odyssey.epub", "Iliad.epub"]
        let m = AudiobookCloudSync.epubManifest(names: names, sizes: [1_234_567, 42])
        let back = AudiobookCloudSync.epubNames(fromManifest: m)
        XCTAssertEqual(back.map(\.filename), names)
        XCTAssertEqual(back.map(\.index), [0, 1])
    }

    func testFilenameWithColonSurvives() {
        // Filename sits LAST in each entry precisely so a ":" inside it is safe.
        let names = ["Homer: The Odyssey.epub"]
        let m = AudiobookCloudSync.epubManifest(names: names, sizes: [10])
        XCTAssertEqual(AudiobookCloudSync.epubNames(fromManifest: m).map(\.filename), names)
    }

    func testSizeChangeChangesTheSignature() {
        // Re-attaching a different file under the same name must re-upload.
        let a = AudiobookCloudSync.epubManifest(names: ["b.epub"], sizes: [10])
        let b = AudiobookCloudSync.epubManifest(names: ["b.epub"], sizes: [11])
        XCTAssertNotEqual(a, b)
    }

    func testAddingATextChangesTheSignature() {
        let one = AudiobookCloudSync.epubManifest(names: ["a.epub"], sizes: [10])
        let two = AudiobookCloudSync.epubManifest(names: ["a.epub", "b.epub"], sizes: [10, 20])
        XCTAssertNotEqual(one, two)
        XCTAssertEqual(AudiobookCloudSync.epubNames(fromManifest: two).count, 2)
    }

    func testEmptyAndMalformedManifestsYieldNothing() {
        XCTAssertTrue(AudiobookCloudSync.epubNames(fromManifest: "").isEmpty)
        XCTAssertTrue(AudiobookCloudSync.epubNames(fromManifest: "nonsense").isEmpty)
        XCTAssertTrue(AudiobookCloudSync.epubNames(fromManifest: "x:1:a.epub").isEmpty)  // bad index
    }

    func testNoAttachedTextsIsAnEmptySignature() {
        XCTAssertEqual(AudiobookCloudSync.epubManifest(names: [], sizes: []), "")
    }
}
