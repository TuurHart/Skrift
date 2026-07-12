import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A1/C4: fetch a shared link's page ONCE on drain (E4 policy — network in the
/// app, never the extension) and turn it into a rich card (title · description ·
/// LOCAL thumbnail, offline-safe) plus the article's readable text (searchable).
/// No AI, just parsing — the pure HTML work lives in `HTMLMeta` (host-tested).
enum LinkEnrichment {
    struct Result: Equatable {
        var title: String?
        var descriptionText: String?
        /// Relative filename in the recordings dir (downloaded + downsampled og:image).
        var thumbnailFile: String?
        var articleText: String?
    }

    /// nil when the URL isn't http(s), the fetch fails, or the payload isn't HTML.
    static func enrich(url remote: URL, memoID: UUID) async -> Result? {
        guard remote.scheme?.hasPrefix("http") == true else { return nil }
        var request = URLRequest(url: remote)
        request.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard contentType.contains("html") else { return nil }

        let html = String(decoding: data.prefix(2_000_000), as: UTF8.self)
        let meta = HTMLMeta.parse(html, baseURL: remote)

        var thumbFile: String?
        if let imgURL = meta.imageURL {
            thumbFile = await downloadThumbnail(from: imgURL, memoID: memoID)
        }
        return Result(title: meta.title, descriptionText: meta.description,
                      thumbnailFile: thumbFile, articleText: meta.articleText)
    }

    /// og:image → recordings dir as `linkthumb_<memo>.jpg`, ImageIO-downsampled
    /// (≤640 px — a card thumb, not a photo). nil on any failure.
    private static func downloadThumbnail(from remote: URL, memoID: UUID) async -> String? {
        var request = URLRequest(url: remote)
        request.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let jpeg = downsampledJPEG(from: data) else { return nil }
        let name = "linkthumb_\(memoID.uuidString).jpg"
        let dest = AppPaths.recordingsDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        guard (try? jpeg.write(to: dest)) != nil else { return nil }
        return name
    }

    private static func downsampledJPEG(from data: Data, maxPixel: CGFloat = 640) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}

/// Pure HTML extraction — regex-grade on purpose (C4: "no AI, just parsing").
/// Good enough for og-tagged pages and article-shaped bodies; anything weirder
/// degrades to nil and the card stays as it was.
enum HTMLMeta {
    struct Parsed: Equatable {
        var title: String?
        var description: String?
        var imageURL: URL?
        var articleText: String?
    }

    static func parse(_ html: String, baseURL: URL?) -> Parsed {
        let cleaned = strippingBlocks(html, tags: ["script", "style", "noscript", "svg"])

        let title = firstNonEmpty(
            metaContent(cleaned, key: "og:title"),
            metaContent(cleaned, key: "twitter:title"),
            tagText(cleaned, tag: "title")
        ).map(decodeEntities)

        let description = firstNonEmpty(
            metaContent(cleaned, key: "og:description"),
            metaContent(cleaned, key: "twitter:description"),
            metaContent(cleaned, key: "description")
        ).map(decodeEntities)

        var imageURL: URL?
        if let raw = firstNonEmpty(metaContent(cleaned, key: "og:image"),
                                   metaContent(cleaned, key: "twitter:image")),
           let resolved = URL(string: decodeEntities(raw), relativeTo: baseURL)?.absoluteURL,
           resolved.scheme?.hasPrefix("http") == true {
            imageURL = resolved
        }

        return Parsed(title: title, description: description,
                      imageURL: imageURL, articleText: articleText(from: cleaned))
    }

    /// Readable article text: prefer <article> scope (else <body>), join the
    /// <p> blocks' text. A page without a real paragraph run (< 3 paragraphs or
    /// < 400 chars) yields nil — landing/app pages shouldn't become "articles".
    static func articleText(from html: String) -> String? {
        let scope = tagText(html, tag: "article", keepInnerHTML: true)
            ?? tagText(html, tag: "body", keepInnerHTML: true)
            ?? html
        let deChromed = strippingBlocks(scope, tags: ["nav", "header", "footer", "aside", "form", "figure"])

        var paragraphs: [String] = []
        let ns = deChromed as NSString
        guard let rx = try? NSRegularExpression(pattern: "<p\\b[^>]*>(.*?)</p>",
                                                options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        for m in rx.matches(in: deChromed, range: NSRange(location: 0, length: ns.length)) {
            let inner = ns.substring(with: m.range(at: 1))
            let text = decodeEntities(strippingTags(inner))
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count >= 40 { paragraphs.append(text) }   // skip captions/buttons
        }
        let joined = paragraphs.joined(separator: "\n\n")
        guard paragraphs.count >= 3, joined.count >= 400 else { return nil }
        return String(joined.prefix(60_000))
    }

    // MARK: - Small extractors

    /// `<meta property|name="key" content="…">` — either attribute order, both quote styles.
    static func metaContent(_ html: String, key: String) -> String? {
        let k = NSRegularExpression.escapedPattern(for: key)
        let patterns = [
            "<meta[^>]*(?:property|name)\\s*=\\s*[\"']\(k)[\"'][^>]*content\\s*=\\s*[\"']([^\"']*)[\"']",
            "<meta[^>]*content\\s*=\\s*[\"']([^\"']*)[\"'][^>]*(?:property|name)\\s*=\\s*[\"']\(k)[\"']",
        ]
        for p in patterns {
            if let rx = try? NSRegularExpression(pattern: p, options: .caseInsensitive) {
                let ns = html as NSString
                if let m = rx.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) {
                    let v = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !v.isEmpty { return v }
                }
            }
        }
        return nil
    }

    /// Inner content of the first `<tag>…</tag>`. `keepInnerHTML` false → tags
    /// stripped + entities decoded (for <title>).
    static func tagText(_ html: String, tag: String, keepInnerHTML: Bool = false) -> String? {
        guard let rx = try? NSRegularExpression(pattern: "<\(tag)\\b[^>]*>(.*?)</\(tag)>",
                                                options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let ns = html as NSString
        guard let m = rx.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let inner = ns.substring(with: m.range(at: 1))
        if keepInnerHTML { return inner }
        let text = decodeEntities(strippingTags(inner))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Remove `<tag …>…</tag>` blocks wholesale (script/style/nav/…).
    static func strippingBlocks(_ html: String, tags: [String]) -> String {
        var out = html
        for tag in tags {
            if let rx = try? NSRegularExpression(pattern: "<\(tag)\\b[^>]*>.*?</\(tag)>",
                                                 options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                out = rx.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length),
                                                  withTemplate: " ")
            }
        }
        // HTML comments can hide half a page from the paragraph scan.
        if let rx = try? NSRegularExpression(pattern: "<!--.*?-->", options: .dotMatchesLineSeparators) {
            out = rx.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length),
                                              withTemplate: " ")
        }
        return out
    }

    static func strippingTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    /// The common named entities + numeric forms — enough for titles/articles.
    static func decodeEntities(_ s: String) -> String {
        var out = s
        let named: [String: String] = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                                       "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&mdash;": "—",
                                       "&ndash;": "–", "&hellip;": "…", "&rsquo;": "’", "&lsquo;": "‘",
                                       "&rdquo;": "”", "&ldquo;": "“"]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        // Numeric: &#8217; and &#x2019;
        if let rx = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let ns = out as NSString
            var result = out
            for m in rx.matches(in: out, range: NSRange(location: 0, length: ns.length)).reversed() {
                let isHex = ns.substring(with: m.range(at: 1)).lowercased() == "x"
                let digits = ns.substring(with: m.range(at: 2))
                if let code = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                    result = (result as NSString).replacingCharacters(in: m.range, with: String(Character(scalar)))
                }
            }
            return result
        }
        return out
    }

    private static func firstNonEmpty(_ vals: String?...) -> String? {
        for v in vals { if let v, !v.trimmingCharacters(in: .whitespaces).isEmpty { return v } }
        return nil
    }
}
