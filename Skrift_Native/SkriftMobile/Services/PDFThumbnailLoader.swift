import PDFKit
import UIKit

/// First-page thumbnail + page count for the INLINE PDF block (signed-off
/// mock `pdf-inline-capture.html` variant A — "text, PDF, text"). Cached by
/// path+mtime+size so a markup save-back or a re-scan re-renders (the same
/// self-invalidation as `MemoImageLoader`).
enum PDFThumbnailLoader {
    final class Entry {
        let image: UIImage
        let pageCount: Int
        init(image: UIImage, pageCount: Int) { self.image = image; self.pageCount = pageCount }
    }

    private static let cache = NSCache<NSString, Entry>()

    static func firstPage(at url: URL, maxWidth: CGFloat) -> Entry? {
        let maxPixel = max(1, Int(maxWidth * UIScreen.main.scale))
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        let key = "\(url.path)|\(mtime?.timeIntervalSince1970 ?? 0)|\(maxPixel)" as NSString
        if let hit = cache.object(forKey: key) { return hit }

        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .cropBox)
        let scale = CGFloat(maxPixel) / max(1, bounds.width)
        let size = CGSize(width: CGFloat(maxPixel), height: max(1, bounds.height * scale))
        let entry = Entry(image: page.thumbnail(of: size, for: .cropBox), pageCount: doc.pageCount)
        cache.setObject(entry, forKey: key,
                        cost: Int(size.width * size.height) * 4)
        return entry
    }
}
