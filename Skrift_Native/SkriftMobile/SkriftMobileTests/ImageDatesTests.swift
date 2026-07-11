import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import SkriftMobile

/// A4: the EXIF taken-date read the share extension does on the ORIGINAL bytes
/// (the downsample re-encode strips metadata, so this is the only place it exists).
final class ImageDatesTests: XCTestCase {

    private func tinyJPEG() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }.jpegData(compressionQuality: 0.9)!
    }

    /// Bake an EXIF DateTimeOriginal into a JPEG via ImageIO (what a camera writes).
    private func jpegWithExif(_ stamp: String) -> Data {
        let base = tinyJPEG()
        let src = CGImageSourceCreateWithData(base as CFData, nil)!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)!
        let props: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: stamp]
        ]
        CGImageDestinationAddImageFromSource(dest, src, 0, props as CFDictionary)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    func testExifDateParsed() throws {
        let data = jpegWithExif("2026:07:04 19:21:03")
        let date = try XCTUnwrap(ImageDates.exifDate(from: data))
        // EXIF stamps are timezone-naive local time — compare local components.
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        XCTAssertEqual(c.year, 2026)
        XCTAssertEqual(c.month, 7)
        XCTAssertEqual(c.day, 4)
        XCTAssertEqual(c.hour, 19)
        XCTAssertEqual(c.minute, 21)
        XCTAssertEqual(c.second, 3)
    }

    func testNoExifYieldsNil() {
        XCTAssertNil(ImageDates.exifDate(from: tinyJPEG()), "renderer JPEG carries no taken-date")
        XCTAssertNil(ImageDates.exifDate(from: Data([0x00, 0x01])), "garbage bytes → nil")
    }
}
