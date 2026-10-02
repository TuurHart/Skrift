import Foundation
import PDFKit
import AppKit

/// Q143: what the Mac review needs to draw a capture the way the phone does — every fact read
/// from data the Mac already holds (the metadata blob, the capture's working folder). Pure
/// reads, no SwiftUI, so the host-less test bundle can drive them.
extension PipelineFile {
    /// The typed thought that LEADS a non-capture note (a video's sheet text, a mixed share's
    /// chat text). Phone `MemoPageView` shows it above the transcript; it rides the synced
    /// metadata blob as `annotationText`. nil for a capture (there the annotation IS the body)
    /// and when blank.
    var annotationLead: String? {
        guard sourceType != .capture,
              let data = audioMetadataJSON,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = obj["annotationText"] as? String else { return nil }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// The capture's photos on disk, in manifest order — the files `UploadService.saveImages` /
    /// `MemoPhotoMaterializer` wrote under `images/`. Only the ones that exist.
    var captureImageURLs: [URL] {
        guard let dir = workingFolder?.appendingPathComponent("images", isDirectory: true) else { return [] }
        return VaultExporter.pictureManifest(imagesDir: dir)
            .map { dir.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// A shared link's thumbnail, when its FILE is in the capture's folder. `urlThumbnailUrl`
    /// holds a RELATIVE filename on the phone (a remote URL is a legacy value and never
    /// fetched — offline rule, same as the phone). The phone does not sync that file today, so
    /// this is nil until it does; the card then falls back to the globe tile.
    var captureThumbnailURL: URL? {
        guard let name = sharedContent?.urlThumbnailUrl?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty, !name.contains("://"), !name.contains("/"),
              let folder = workingFolder else { return nil }
        for dir in [folder, folder.appendingPathComponent("images", isDirectory: true)] {
            let url = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// The synced `.file` document under the capture folder's `files/` (the single file there).
    var captureDocumentURL: URL? {
        guard let dir = workingFolder?.appendingPathComponent("files", isDirectory: true) else { return nil }
        return (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }
}

/// The capture banner's sentence. It used to say "Enhancement-lite still ran: title, tags,
/// summary…" on every capture, which is false for a capture nobody rated (the Mac only picks up
/// a rated note) and for one whose polish has not landed yet.
enum CaptureBannerCopy {
    enum Polish: Equatable { case done, pending, unrated }

    static func polish(rated: Bool, enhanced: Bool) -> Polish {
        enhanced ? .done : (rated ? .pending : .unrated)
    }

    static func text(shared: ShareContentType?, polish: Polish) -> String {
        let head = "Capture — skipped transcription & diarization."
        let polishPhrase: String
        switch polish {
        case .done:
            polishPhrase = "Enhancement-lite ran: title, tags, summary + name-linking on your annotation."
        case .pending:
            polishPhrase = "Enhancement-lite has not run yet: title, tags and summary come when it does."
        case .unrated:
            polishPhrase = "Not rated, so it is not polished: rate it and the Mac adds a title, tags and summary."
        }
        let typePhrase: String
        switch shared {
        case .url:   typePhrase = "The URL exports to Obsidian intact."
        case .text:  typePhrase = "The snippet exports as a blockquote above your annotation."
        case .image: typePhrase = "The image is copied to your vault attachments folder."
        default:     typePhrase = "The shared content exports to Obsidian alongside your annotation."
        }
        return "\(head) \(polishPhrase) \(typePhrase)"
    }
}

/// Q143 / D126: the first page of a captured PDF, drawn inline (phone `PDFThumbnailLoader`
/// twin). PDFKit is a system framework; nothing is fetched.
enum CapturePDFPreview {
    struct Page {
        let image: NSImage
        let pageCount: Int
    }

    /// First page scaled to `maxWidth` points wide (never upscaled past 2x for sharpness).
    /// nil when the file is not a readable PDF.
    static func firstPage(at url: URL, maxWidth: CGFloat = 520) -> Page? {
        guard url.pathExtension.lowercased() == "pdf",
              let doc = PDFDocument(url: url), doc.pageCount > 0,
              let page = doc.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let w = min(maxWidth, bounds.width * 2)
        let size = CGSize(width: w, height: w * bounds.height / bounds.width)
        // Rendered at 2x so the card stays crisp on a retina display.
        let image = page.thumbnail(of: CGSize(width: size.width * 2, height: size.height * 2), for: .mediaBox)
        image.size = size
        return Page(image: image, pageCount: doc.pageCount)
    }

    static func pageCountLabel(_ n: Int) -> String { n == 1 ? "1 page" : "\(n) pages" }
}
