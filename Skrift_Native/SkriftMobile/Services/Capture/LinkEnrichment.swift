import Foundation

/// A1/C4: fetch a shared link's page ONCE on drain (E4 policy — network in the
/// app, never the extension) and turn it into a rich card (title · description ·
/// LOCAL thumbnail, offline-safe) plus the article's readable text (searchable).
/// No AI, just parsing. Q136: the routine itself is `LinkCard` (Shared, so the Mac's
/// drop runs the SAME one); this wrapper only decides where the thumbnail file lives.
enum LinkEnrichment {
    struct Result: Equatable {
        var title: String?
        var descriptionText: String?
        /// Relative filename in the recordings dir (downloaded + downsampled og:image).
        var thumbnailFile: String?
        var articleText: String?
    }

    /// nil when the URL isn't http(s), the fetch fails, or the payload isn't HTML.
    static func enrich(url remote: URL, memoID: UUID,
                       fetcher: any LinkFetching = URLSessionLinkFetcher()) async -> Result? {
        guard let card = await LinkCard.enrich(url: remote, fetcher: fetcher) else { return nil }
        var thumbFile: String?
        if let jpeg = card.thumbnailJPEG {
            // og:image → recordings dir as `linkthumb_<memo>.jpg`.
            let name = "linkthumb_\(memoID.uuidString).jpg"
            let dest = AppPaths.recordingsDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            if (try? jpeg.write(to: dest)) != nil { thumbFile = name }
        }
        return Result(title: card.title, descriptionText: card.descriptionText,
                      thumbnailFile: thumbFile, articleText: card.articleText)
    }
}
