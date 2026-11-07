import XCTest

/// Q554: a commit never changes the order of the pictures, videos and files the user placed.
/// Tuur (Dev 205 recording, 241-243 s): photo, library photo, file read photo, file, library photo
/// right after Done. Every case is the phone editor's commit
/// (`BodyV2.committed`, `keepOwnParagraphs`, edited) over the text the editor held.
final class BodyCommitKeepsBlockOrderTests: XCTestCase {

    private func commit(_ text: String, pictures: Int, source: BodyV2.Source = .speech) -> String {
        let manifest = (0..<pictures).map { ImageManifestEntry(filename: "photo_\($0 + 1).jpg", offsetSeconds: 0) }
        return BodyV2.committed(BodyV2.Input(text: text, manifest: manifest, source: source,
                                             userEdited: true, keepOwnParagraphs: true))
    }

    /// The failing shape. One picture glued to the line above makes the commit lift EVERY picture
    /// run; `lift` then joined `mid` and `[[file_001]]` into one line with a space, so the two
    /// pictures that stood before the file were put after it.
    /// before: "Wor\nType\n[[img_001]]\n\nmid\n\n[[img_002]]\n\n[[img_003]]\n\n[[file_001]]"
    /// after, was: "Wor\nType\n\n[[img_001]]\n\nmid\n\n[[file_001]]\n\n[[img_002]]\n\n[[img_003]]"
    func testAGluedPictureElsewhereDoesNotMovePicturesPastTheFile() {
        let stored = commit("Wor\nType\n[[img_001]]\n\nmid\n\n[[img_002]]\n\n[[img_003]]\n\n[[file_001]]\n\n", pictures: 3)
        XCTAssertEqual(stored, "Wor\nType\n\n[[img_001]]\n\nmid\n\n[[img_002]]\n\n[[img_003]]\n\n[[file_001]]")
    }

    func testAFileThenAPhotoKeepsTheirOrder() {
        let stored = commit("Hello\n[[img_001]]\n\nmid\n\n[[file_001]]\n\n[[img_002]]\n\n", pictures: 2)
        XCTAssertEqual(stored, "Hello\n\n[[img_001]]\n\nmid\n\n[[file_001]]\n\n[[img_002]]")
    }

    func testAVideoBetweenPhotosStaysBetween() {
        let stored = commit("Hi\n[[img_001]]\n\nmid\n\n[[img_002]]\n\n[[vid_001]]\n\n[[img_003]]", pictures: 3)
        XCTAssertEqual(stored, "Hi\n\n[[img_001]]\n\nmid\n\n[[img_002]]\n\n[[vid_001]]\n\n[[img_003]]")
    }

    func testAFileGluedToTheTextNextToAPictureStaysPut() {
        // no blank line at all around the run: " " used to join the file marker to the prose
        let stored = commit("One\nTwo[[img_001]][[file_001]]\n[[img_002]]\n\nend", pictures: 2)
        let order = BodyV2.markerSequence(in: stored)
        XCTAssertEqual(order, ["[[img_001]]", "[[file_001]]", "[[img_002]]"], stored)
    }

    /// Marker numbers not in reading order (a redo can leave the manifest that way): the pictures
    /// stand as the user placed them, not sorted by number.
    /// before: "A\n[[img_003]]\n\n[[img_002]]\n\n[[img_001]]\n\nB"
    /// after, was: "A\n\n[[img_001]]\n\n[[img_002]]\n\n[[img_003]]\n\nB"
    func testMarkerNumbersOutOfReadingOrderKeepTheirPlaces() {
        let stored = commit("A\n[[img_003]]\n\n[[img_002]]\n\n[[img_001]]\n\nB", pictures: 3)
        XCTAssertEqual(stored, "A\n\n[[img_003]]\n\n[[img_002]]\n\n[[img_001]]\n\nB")
    }

    func testOutOfOrderNumbersWithAFileBetween() {
        let stored = commit("A\n[[img_002]]\n\nmid\n\n[[file_001]]\n\n[[img_001]]\n\n", pictures: 2)
        XCTAssertEqual(BodyV2.markerSequence(in: stored), ["[[img_002]]", "[[file_001]]", "[[img_001]]"], stored)
    }

    /// The same rule at the one-time migration's `markersMoved` (it lifts and builds too).
    func testMigrationMoveKeepsOutOfOrderNumbers() {
        let moved = BodyNormaliseMigration.markersMoved("A\n[[img_002]]\n\n[[img_001]]\n\nB", manifestCount: 2)
        XCTAssertEqual(BodyV2.markerSequence(in: moved), ["[[img_002]]", "[[img_001]]"], moved)
    }

    /// Typed words never change: a clean body comes back unchanged.
    func testACleanBodyIsUnchanged() {
        let clean = "Wor\nType\n\n[[img_001]]\n\n[[img_002]]\n\n[[file_001]]"
        XCTAssertEqual(commit(clean, pictures: 2), clean)
    }
}
