import SwiftUI
import UIKit

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
                if let image = BookCoverCache.image(for: book) {
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
        let index = abs(book.id.uuidString.hashValue) % palettes.count
        return palettes[index].map { Color(hex: $0) }
    }
}

/// Tiny main-actor cover cache so list rows don't re-decode JPEGs per render.
@MainActor
enum BookCoverCache {
    private static let cache = NSCache<NSUUID, UIImage>()

    static func image(for book: Audiobook) -> UIImage? {
        guard book.hasCover else { return nil }
        if let hit = cache.object(forKey: book.id as NSUUID) { return hit }
        guard let url = AudiobookLibraryStore.shared.coverURL(of: book),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: book.id as NSUUID)
        return image
    }

    /// Drop a book's cached cover (after "Edit book details" replaces the
    /// art on disk) so the next render re-decodes the new file.
    static func invalidate(_ id: UUID) {
        cache.removeObject(forKey: id as NSUUID)
    }
}
