import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Q136 (C77, C72, C73, D19): the ONE import layer's network, PDF and place seams, SHARED by
/// the phone's share drain and the Mac's drop. Each is a protocol so a test injects a stub and
/// nothing ever touches the network in a unit test; the live conformers are one line each.
///
/// Pure parsing lives in `HTMLMeta` and `PlaceLink` (also Shared). This file adds the fetch
/// seam, the one "link → card" routine both apps run, and the small rules that decide what a
/// shared file becomes.

// MARK: - Fetch seam

/// What a fetch returned. `data` is empty for a HEAD.
struct LinkFetchResponse: Sendable, Equatable {
    var data: Data
    var statusCode: Int
    var contentType: String

    init(data: Data = Data(), statusCode: Int = 200, contentType: String = "") {
        self.data = data
        self.statusCode = statusCode
        self.contentType = contentType
    }
}

/// One GET (or HEAD), no JS, no cookies: the only network a link import makes (C72).
protocol LinkFetching: Sendable {
    /// nil on any transport failure or a non-2xx status.
    func fetch(_ url: URL, method: String, timeout: TimeInterval) async -> LinkFetchResponse?
}

struct URLSessionLinkFetcher: LinkFetching {
    func fetch(_ url: URL, method: String = "GET", timeout: TimeInterval = 12) async -> LinkFetchResponse? {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return LinkFetchResponse(data: data, statusCode: http.statusCode,
                                 contentType: http.value(forHTTPHeaderField: "Content-Type") ?? "")
    }
}

// MARK: - PDF text seam

/// Embedded text of a PDF on disk. The phone runs it on drain, the Mac on drop; the same
/// extraction (`PDFTextExtract`) so a PDF is as searchable on either.
protocol PDFTextExtracting: Sendable {
    func text(of url: URL) -> String?
}

struct PDFKitTextExtractor: PDFTextExtracting {
    func text(of url: URL) -> String? { PDFTextExtract.text(of: url) }
}

// MARK: - Link → card

/// A shared link's page, parsed ONCE into a card (C72, A1/C4). The thumbnail is the
/// downsampled JPEG BYTES (the caller decides where they live: the phone's recordings dir,
/// the Mac's capture folder), so the card stays offline-safe.
enum LinkCard {
    struct Result: Equatable, Sendable {
        var title: String?
        var descriptionText: String?
        var thumbnailJPEG: Data?
        var articleText: String?
    }

    /// nil when the URL isn't http(s), the fetch fails, or the payload isn't HTML.
    static func enrich(url remote: URL, fetcher: any LinkFetching) async -> Result? {
        guard remote.scheme?.lowercased().hasPrefix("http") == true else { return nil }
        guard let page = await fetcher.fetch(remote, method: "GET", timeout: 12),
              page.contentType.lowercased().contains("html") else { return nil }
        let html = String(decoding: page.data.prefix(2_000_000), as: UTF8.self)
        let meta = HTMLMeta.parse(html, baseURL: remote)

        var thumb: Data?
        if let imgURL = meta.imageURL, let img = await fetcher.fetch(imgURL, method: "GET", timeout: 10) {
            thumb = downsampledJPEG(from: img.data)
        }
        return Result(title: meta.title, descriptionText: meta.description,
                      thumbnailJPEG: thumb, articleText: meta.articleText)
    }

    /// ≤ `maxPixel` px on the long edge (a card thumb, not a photo). nil when `data` is not an image.
    static func downsampledJPEG(from data: Data, maxPixel: CGFloat = 640) -> Data? {
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

    /// C72: a page with no title is titled by its HOST (`example.com`), never the raw URL.
    /// A leading `www.` is dropped. nil when the URL has no host.
    static func hostTitle(_ url: URL) -> String? {
        guard var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    // MARK: PDF links (C73)

    /// "application/pdf" with any casing/parameters (arxiv sends "application/pdf; qs=0.001").
    static func isPDFContentType(_ value: String?) -> Bool {
        guard let first = value?.lowercased().split(separator: ";").first else { return false }
        return first.trimmingCharacters(in: .whitespaces) == "application/pdf"
    }

    /// Magic bytes, because content-type headers lie. The real gate for a PDF download.
    static func isPDFData(_ data: Data) -> Bool { data.starts(with: Data("%PDF".utf8)) }

    /// Does this http(s) link point AT a PDF? `.pdf` extension (fast path), else a HEAD
    /// content-type sniff, since arxiv-style links are extensionless.
    static func pointsAtPDF(_ remote: URL, fetcher: any LinkFetching) async -> Bool {
        if remote.pathExtension.lowercased() == "pdf" { return true }
        guard remote.scheme?.lowercased().hasPrefix("http") == true,
              let head = await fetcher.fetch(remote, method: "HEAD", timeout: 10) else { return false }
        return isPDFContentType(head.contentType)
    }

    /// The PDF's bytes, only when the payload really is a PDF. nil otherwise (the caller keeps
    /// the plain link card: the URL is never lost).
    static func downloadPDF(_ remote: URL, fetcher: any LinkFetching) async -> Data? {
        guard let got = await fetcher.fetch(remote, method: "GET", timeout: 20), isPDFData(got.data) else { return nil }
        return got.data
    }
}

// MARK: - Text files (D4 / D22)

enum SharedTextFile {
    /// Largest text file that becomes a note body (a novel-length .txt stays a document).
    static let byteCap = 512_000

    /// The trimmed UTF-8 body of a shared `.txt` / `.md`, or nil when it is oversized,
    /// non-UTF-8 or blank (the caller then keeps it as a file capture).
    static func body(of data: Data) -> String? {
        guard data.count <= byteCap, let s = String(data: data, encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
