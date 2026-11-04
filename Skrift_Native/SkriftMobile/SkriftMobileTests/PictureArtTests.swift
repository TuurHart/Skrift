import XCTest
import UIKit
@testable import SkriftMobile

/// Q545 (D224): the shared painter draws a photo at the rule's size, whole, small or large.
final class PictureArtTests: XCTestCase {

    private func source(_ w: CGFloat, _ h: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { ctx in
            UIColor.systemTeal.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    func testSmallPicturesAreAThirdOfTheColumnOnTheLongestSide() {
        XCTAssertEqual(NoteAttachmentArt.picture(source(300, 200), size: .small, column: 362).size, CGSize(width: 121, height: 80))
        XCTAssertEqual(NoteAttachmentArt.picture(source(300, 400), size: .small, column: 362).size, CGSize(width: 90, height: 121))
    }

    func testLargePicturesFillTheColumnAndTallOnesAreNotCapped() {
        XCTAssertEqual(NoteAttachmentArt.picture(source(300, 200), size: .large, column: 362).size, CGSize(width: 362, height: 241))
        XCTAssertEqual(NoteAttachmentArt.picture(source(300, 400), size: .large, column: 362).size, CGSize(width: 362, height: 483))
    }

    func testTheCornersAreRoundedAndTheMiddleIsThePicture() throws {
        let img = NoteAttachmentArt.picture(source(300, 200), size: .small, column: 362)
        let cg = try XCTUnwrap(img.cgImage)
        var px = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                          bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        func alpha(_ x: Int, _ y: Int) -> UInt8 { px[(y * cg.width + x) * 4 + 3] }
        XCTAssertEqual(alpha(0, 0), 0, "the corner is cut away")
        XCTAssertEqual(alpha(cg.width / 2, cg.height / 2), 255, "the middle is the photo")
    }
}
