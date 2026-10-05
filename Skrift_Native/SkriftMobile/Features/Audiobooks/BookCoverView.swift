import SwiftUI
import UIKit
import ImageIO

/// A book's cover: the file's embedded artwork when present, else a stable
/// gradient placeholder with the (uppercased) title — exactly the mock's
/// placeholder idiom. The caller frames + clips it.
struct BookCoverView: View {
    let book: Audiobook
    /// Hide the placeholder title text below this edge length (mini-player thumb).
    var showsPlaceholderTitle = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = BookCoverCache.image(for: book, points: max(geo.size.width, geo.size.height)) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: Self.gradient(for: book),
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    if showsPlaceholderTitle {
                        Text(book.title.uppercased())
                            .font(.system(size: max(6, geo.size.width / 8), weight: .bold))
                            .kerning(0.3)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                            .minimumScaleFactor(0.5)
                            .foregroundStyle(.white.opacity(0.88))
                            .padding(geo.size.width / 10)
                    }
                }
                // The mock's subtle top sheen.
                LinearGradient(
                    colors: [.white.opacity(0.14), .clear],
                    startPoint: .top, endPoint: .center
                )
            }
        }
        .accessibilityHidden(true)
    }

    /// Deterministic gradient per book (stable across launches).
    private static func gradient(for book: Audiobook) -> [Color] {
        let palettes: [[UInt32]] = [
            [0x3b4ce0, 0x7c6bf5],
            [0x0e7490, 0x164e63],
            [0xb45309, 0x7c2d12],
            [0x166534, 0x14532d],
            [0x9d174d, 0x581c87],
        ]
        let index = StableHash.index(book.id.uuidString, count: palettes.count)
        return palettes[index].map { Color(hex: $0) }
    }
}

/// Tiny main-actor cover cache so list rows don't re-decode JPEGs per render.
///
/// Q317 (D-B3 / I5): covers are stored at whatever size the file embeds (1400-3000 px,
/// ~23-36 MB decoded) but drawn at 34-300 pt. The cache now holds an ImageIO THUMBNAIL at
/// the smallest size tier that covers the display size (decoded straight to that size, never
/// the full bitmap), keyed by book + tier, with a byte cost limit.
@MainActor
enum BookCoverCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 48 * 1024 * 1024
        return c
    }()

    /// Longest-edge pixel tiers; a request rounds UP to one so near sizes share an entry.
    static let tiers = [128, 256, 512, 1024]

    /// The tier (longest edge, px) for a view `points` wide at the screen scale.
    static func tier(forPoints points: CGFloat) -> Int {
        let px = Int((max(1, points) * UIScreen.main.scale).rounded(.up))
        return tiers.first { $0 >= px } ?? tiers[tiers.count - 1]
    }

    private static func key(_ id: UUID, _ tier: Int) -> NSString { "\(id.uuidString)|\(tier)" as NSString }

    /// The cover at `maxPixel` longest edge (a tier value), or nil with no cover on disk.
    static func image(for book: Audiobook, maxPixel: Int = tiers[tiers.count - 1]) -> UIImage? {
        guard book.hasCover else { return nil }
        let k = key(book.id, maxPixel)
        if let hit = cache.object(forKey: k) { return hit }
        guard let url = AudiobookLibraryStore.shared.coverURL(of: book),
              let image = downsampled(at: url, maxPixel: maxPixel) else { return nil }
        cache.setObject(image, forKey: k, cost: Int(image.size.width * image.scale * image.size.height * image.scale) * 4)
        return image
    }

    /// The cover sized for a view `points` across.
    static func image(for book: Audiobook, points: CGFloat) -> UIImage? {
        image(for: book, maxPixel: tier(forPoints: points))
    }

    /// ImageIO thumbnail: decodes straight to `maxPixel`, honouring EXIF orientation.
    nonisolated static func downsampled(at url: URL, maxPixel: Int) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Drop a book's cached cover (after "Edit book details" replaces the
    /// art on disk) so the next render re-decodes the new file.
    static func invalidate(_ id: UUID) {
        for t in tiers { cache.removeObject(forKey: key(id, t)) }
    }
}
