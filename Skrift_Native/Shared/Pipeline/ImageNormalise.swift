import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The ONE rule for a picture entering the app (C74 / D17, Q135). Shared: the phone's share
/// extension + Open-in path and the Mac's ingest all go through it, so a picture is stored the
/// same way wherever it came from.
///
/// - GIF: kept byte-for-byte (Obsidian animates it; the app shows frame one). Never resized.
/// - PNG: stays PNG. Longest side <= 2048 -> the original bytes; larger -> downsampled, PNG again.
/// - JPEG / WebP: the original bytes when <= 2048; larger -> downsampled JPEG 0.9.
/// - HEIC / HEIF / TIFF / BMP (anything else ImageIO can read): JPEG 0.9, downsampled when larger.
/// A downsample uses an ImageIO thumbnail decode (never the full bitmap; the extension has a
/// ~120 MB ceiling) with the EXIF orientation baked in. Metadata reads (the date) must happen on
/// the ORIGINAL bytes, before this runs.
enum ImageNormalise {

    static let maxPixel = 2048
    static let jpegQuality = 0.9

    struct Result: Equatable {
        var data: Data
        /// File extension without the dot: "png", "gif", "jpg", "webp".
        var ext: String
        var mime: String
    }

    /// nil when the bytes are not an image ImageIO can read.
    static func normalise(_ data: Data, maxPixel: Int = ImageNormalise.maxPixel) -> Result? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let uti = CGImageSourceGetType(src) as String?,
              let type = UTType(uti),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return nil }
        let w = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let tooBig = max(w, h) > maxPixel

        if type.conforms(to: .gif) { return Result(data: data, ext: "gif", mime: "image/gif") }
        if type.conforms(to: .png) {
            if !tooBig { return Result(data: data, ext: "png", mime: "image/png") }
            return downsampled(src, maxPixel: min(maxPixel, max(w, h)), as: .png).map { Result(data: $0, ext: "png", mime: "image/png") }
        }
        if !tooBig, type.conforms(to: .jpeg) { return Result(data: data, ext: "jpg", mime: "image/jpeg") }
        if !tooBig, type == .webP { return Result(data: data, ext: "webp", mime: "image/webp") }
        // HEIC / TIFF / BMP, or a JPEG / WebP above the cap -> JPEG 0.9 at <= maxPixel.
        return downsampled(src, maxPixel: min(maxPixel, max(w, h)), as: .jpeg).map { Result(data: $0, ext: "jpg", mime: "image/jpeg") }
    }

    /// The same, straight from a file (the Mac drop).
    static func normalise(fileAt url: URL, maxPixel: Int = ImageNormalise.maxPixel) -> Result? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return normalise(data, maxPixel: maxPixel)
    }

    private static func downsampled(_ src: CGImageSource, maxPixel: Int, as type: UTType) -> Data? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        let props: CFDictionary? = type == .jpeg
            ? [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary : nil
        CGImageDestinationAddImage(dest, cg, props)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
