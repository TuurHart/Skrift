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
                } else if book.sourceKind == .pdf {
                    pdfPaper(width: geo.size.width)
                } else if book.sourceKind == .article {
                    articlePaper(width: geo.size.width)
                } else {
                    LinearGradient(
                        colors: Self.gradient(for: book),
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    if showsPlaceholderTitle {
                        drawnTitle(width: geo.size.width)
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

    /// Q356 (Q6 mock `.cv`): title + author at the bottom-left, the title in a bold serif (an
    /// episode's in heavy sans), the byline at 62% size and 80% opacity, warm off-white ink,
    /// 10% inset.
    private func drawnTitle(width w: CGFloat) -> some View {
        let text = BookCoverText.lines(for: book)
        let size = max(6, w / 11)
        let ink = Color(hex: 0xf4efe6)
        return VStack(alignment: .leading, spacing: max(1, w / 40)) {
            Spacer(minLength: 0)
            Text(text.title)
                .font(book.sourceKind == .episode
                      ? .system(size: size, weight: .heavy)
                      : .system(size: size, weight: .bold, design: .serif))
                .kerning(book.sourceKind == .episode ? -0.02 * size : 0)
                .lineLimit(4)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.leading)
            if let byline = text.byline {
                Text(byline)
                    .font(.system(size: size * 0.62))
                    .opacity(0.8)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(w / 10)
    }

    /// A PDF with no page-1 image (mock `.cv.pdf`): paper, the title at the top in sans, four
    /// faint text lines, a folded top-right corner.
    /// Q355 (mock Q351 `.cv.art`): warm paper, the site in small mono caps at the top, the title in
    /// a bold serif at the bottom.
    private func articlePaper(width w: CGFloat) -> some View {
        let dark = UITraitCollection.current.userInterfaceStyle == .dark
        let paper = Color(hex: dark ? 0x2a261d : 0xefe7d6)
        let ink = Color(hex: dark ? 0xefe4cc : 0x2a2418)
        let site = book.site ?? book.sourceURL.flatMap(URL.init(string:)).map(ArticleExtractor.site(of:)) ?? ""
        return VStack(alignment: .leading, spacing: 0) {
            if showsPlaceholderTitle {
                Text(site.uppercased())
                    .font(.system(size: max(5, w / 18), weight: .semibold, design: .monospaced))
                    .kerning(0.06 * max(5, w / 18))
                    .opacity(0.7)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(book.title)
                    .font(.system(size: max(6, w / 11), weight: .bold, design: .serif))
                    .lineLimit(4)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.leading)
            } else {
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(w / 10)
        .background(paper)
    }

    private func pdfPaper(width w: CGFloat) -> some View {
        let ink = Color(hex: 0x2b2b30)
        return ZStack(alignment: .topTrailing) {
            Color(hex: 0xf4f1ea)
            VStack(alignment: .leading, spacing: w * 0.06) {
                if showsPlaceholderTitle {
                    Text(book.title)
                        .font(.system(size: max(5, w / 13), weight: .bold))
                        .foregroundStyle(ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                }
                ForEach([0.9, 0.75, 0.85, 0.6], id: \.self) { f in
                    Capsule().fill(ink.opacity(0.25)).frame(width: w * 0.8 * f, height: max(1, w / 55))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(w / 10)
            Path { p in
                p.move(to: .zero); p.addLine(to: CGPoint(x: w * 0.22, y: w * 0.22)); p.addLine(to: CGPoint(x: 0, y: w * 0.22))
            }
            .fill(Color.black.opacity(0.18))
            .frame(width: w * 0.22, height: w * 0.22)
        }
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

/// Q356: the words the drawn cover carries (the mock's `.ct` + `.ca`). An episode shows its show
/// (the record's `author`) over "podcast", like the mock's "Het Uur · NRC · podcast"; a PDF only
/// its title; a book its title over its author.
struct BookCoverText: Equatable {
    let title: String
    let byline: String?

    static func lines(for book: Audiobook) -> BookCoverText {
        let author = book.author.trimmingCharacters(in: .whitespaces)
        switch book.sourceKind {
        case .episode: return BookCoverText(title: author.isEmpty ? book.title : author, byline: "podcast")
        case .pdf: return BookCoverText(title: book.title, byline: nil)
        case .book, .article: return BookCoverText(title: book.title, byline: author.isEmpty ? nil : author)
        }
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
