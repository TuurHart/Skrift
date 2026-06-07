import XCTest
import Foundation

final class ImageMarkerReinsertTests: XCTestCase {

    func testExtractAnchorsStripsAndSavesContext() {
        let (stripped, nums, anchors) = ImageMarkerReinsert.extractAnchors("I went outside [[img_001]] and saw a bird")
        XCTAssertEqual(nums, [1])
        XCTAssertEqual(stripped, "I went outside and saw a bird")
        XCTAssertTrue(anchors[1]!.before.hasSuffix("outside"))
        XCTAssertTrue(anchors[1]!.after.hasPrefix("and saw"))
    }

    func testExtractAnchorsNoMarkers() {
        let (stripped, nums, anchors) = ImageMarkerReinsert.extractAnchors("just  text   here")
        XCTAssertEqual(nums, [])
        XCTAssertEqual(stripped, "just text here")   // whitespace collapsed
        XCTAssertTrue(anchors.isEmpty)
    }

    func testReinsertPlacesMarkerAfterBeforeAnchor() {
        let anchors = [1: ImageMarkerReinsert.Anchors(before: "went outside", after: "and saw")]
        let out = ImageMarkerReinsert.reinsert(text: "I went outside and saw a bird.", imgNums: [1], anchors: anchors)
        XCTAssertTrue(out.contains("[[img_001]]"))
        let marker = out.range(of: "[[img_001]]")!
        let outside = out.range(of: "outside")!
        let saw = out.range(of: "saw")!
        XCTAssertTrue(outside.upperBound <= marker.lowerBound)   // after "outside"
        XCTAssertTrue(marker.upperBound <= saw.lowerBound)       // before "saw"
    }

    func testReinsertPreservesMarkerOrder() {
        let anchors = [
            1: ImageMarkerReinsert.Anchors(before: "first part", after: "second"),
            2: ImageMarkerReinsert.Anchors(before: "second part", after: "third"),
        ]
        let out = ImageMarkerReinsert.reinsert(text: "first part second part third part", imgNums: [1, 2], anchors: anchors)
        let m1 = out.range(of: "[[img_001]]")!
        let m2 = out.range(of: "[[img_002]]")!
        XCTAssertTrue(m1.lowerBound < m2.lowerBound)
    }

    func testReinsertNoImagesReturnsInput() {
        XCTAssertEqual(ImageMarkerReinsert.reinsert(text: "unchanged", imgNums: [], anchors: [:]), "unchanged")
    }
}
