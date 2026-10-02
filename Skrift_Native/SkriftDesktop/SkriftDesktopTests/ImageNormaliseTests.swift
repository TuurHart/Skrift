import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import SkriftDesktop

/// C74 / D17 (Q135): a picture entering the app. PNG stays PNG, a GIF is kept byte-for-byte,
/// the longest side is capped at 2048 (a downsample only when larger), HEIC/TIFF/BMP -> JPEG 0.9.
/// The same file runs in the phone's SkriftMobileTests (shared source, one rule).
final class ImageNormaliseTests: XCTestCase {

    private func cgImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        return ctx.makeImage()!
    }

    private func encode(_ images: [CGImage], as type: UTType) -> Data {
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, images.count, nil)!
        for img in images { CGImageDestinationAddImage(dest, img, nil) }
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    private func size(of data: Data) -> (w: Int, h: Int)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (w, h)
    }

    private func isPNG(_ d: Data) -> Bool { d.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) }
    private func isJPEG(_ d: Data) -> Bool { d.prefix(3) == Data([0xFF, 0xD8, 0xFF]) }

    func testLargePNGStaysPNGDownsampledTo2048() throws {
        let png = encode([cgImage(width: 3000, height: 1500)], as: .png)
        let r = try XCTUnwrap(ImageNormalise.normalise(png))
        XCTAssertEqual(r.ext, "png")
        XCTAssertEqual(r.mime, "image/png")
        XCTAssertTrue(isPNG(r.data), "a PNG must not be re-encoded to JPEG")
        let s = try XCTUnwrap(size(of: r.data))
        XCTAssertEqual(max(s.w, s.h), 2048)
        XCTAssertEqual(s.w, 2048)
        XCTAssertEqual(s.h, 1024, "aspect ratio kept")
    }

    func testSmallPNGIsByteIdentical() throws {
        let png = encode([cgImage(width: 640, height: 480)], as: .png)
        let r = try XCTUnwrap(ImageNormalise.normalise(png))
        XCTAssertEqual(r.ext, "png")
        XCTAssertEqual(r.data, png, "no downsample, no re-encode at <= 2048")
    }

    func testGIFStaysByteIdentical() throws {
        // Two frames at 3000 px: even an oversized GIF is kept whole (Obsidian animates it).
        let frame = cgImage(width: 3000, height: 100)
        let gif = encode([frame, frame], as: .gif)
        XCTAssertEqual(gif.prefix(3), Data("GIF".utf8))
        let r = try XCTUnwrap(ImageNormalise.normalise(gif))
        XCTAssertEqual(r.ext, "gif")
        XCTAssertEqual(r.mime, "image/gif")
        XCTAssertEqual(r.data, gif)
    }

    func testTIFFBecomesJPEG() throws {
        let tiff = encode([cgImage(width: 400, height: 300)], as: .tiff)
        let r = try XCTUnwrap(ImageNormalise.normalise(tiff))
        XCTAssertEqual(r.ext, "jpg")
        XCTAssertEqual(r.mime, "image/jpeg")
        XCTAssertTrue(isJPEG(r.data))
        let s = try XCTUnwrap(size(of: r.data))
        XCTAssertEqual(s.w, 400, "a small image is never upscaled")
    }

    func testSmallJPEGUntouchedLargeJPEGDownsampled() throws {
        let small = encode([cgImage(width: 800, height: 600)], as: .jpeg)
        XCTAssertEqual(ImageNormalise.normalise(small)?.data, small)
        let big = encode([cgImage(width: 4000, height: 3000)], as: .jpeg)
        let r = try XCTUnwrap(ImageNormalise.normalise(big))
        XCTAssertTrue(isJPEG(r.data))
        let s = try XCTUnwrap(size(of: r.data))
        XCTAssertEqual(max(s.w, s.h), 2048)
    }

    func testNotAnImageIsNil() {
        XCTAssertNil(ImageNormalise.normalise(Data("hello".utf8)))
    }
}
