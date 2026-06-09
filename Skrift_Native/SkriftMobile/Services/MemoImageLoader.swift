import UIKit
import ImageIO

/// Loads a DOWNSAMPLED `UIImage` for a memo photo, sized to how it's displayed, and
/// caches it. Decoding a multi-megapixel photo at full resolution on the main thread
/// is what made a note with an image render orders of magnitude slower (the "600× with
/// a picture" problem) and the page-swipe / significance-slider lag — ImageIO thumbnail
/// generation decodes straight to the target size instead.
enum MemoImageLoader {
    private static let cache = NSCache<NSString, UIImage>()

    /// A downsampled image whose largest side is ~`maxWidth` points (× screen scale),
    /// cached by path+size. Returns nil if the file is missing/unreadable.
    static func thumbnail(at url: URL, maxWidth: CGFloat) -> UIImage? {
        let maxPixel = max(1, Int(maxWidth * UIScreen.main.scale))
        let key = "\(url.path)|\(maxPixel)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,      // honour EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,            // decode now, off the draw path
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        cache.setObject(image, forKey: key, cost: cg.width * cg.height * 4)
        return image
    }
}
