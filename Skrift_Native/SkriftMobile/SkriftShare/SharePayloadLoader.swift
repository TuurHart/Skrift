import Foundation
import UniformTypeIdentifiers
import UIKit

/// The resolved content of the share action, ready to display in the sheet.
/// Only the fields relevant to the type are populated.
struct SharePayload {
    var type: ShareContentType
    var url: String?
    /// Page title from the share item's `attributedContentText` (no network fetch).
    var urlTitle: String?
    var text: String?
    /// JPEG or PNG data for image captures (loaded from the item provider).
    var imageData: Data?
    var imageFileName: String?
    var mimeType: String?
    /// A shared movie was detected (Photos/Files). When true the host skips the
    /// annotation sheet and imports it as a normal voice memo. `videoURL` is the
    /// extension-temp copy of the movie (nil if the copy failed → host cancels).
    var isVideo: Bool = false
    var videoURL: URL?
    /// A shared document (e.g. a PDF) was detected. The host skips the annotation
    /// sheet and persists it as a `.file` capture (the user can ramble on it later
    /// in the memo detail). `fileURL` is the extension-temp copy; `fileName` is the
    /// original display name (e.g. "report.pdf").
    var fileURL: URL?
    var fileName: String?
}

/// Loads a `SharePayload` from the extension context's input items.
///
/// Priority: URL > image > text. The extension handles one item at a time
/// (activation rule: max 1 of each type), so the first matching provider wins.
///
/// **No network fetch** — `urlTitle` comes only from the item's `attributedContentText`
/// (Safari/Chrome supply the page title there). If unavailable, we show the domain.
enum SharePayloadLoader {

    @MainActor
    static func load(from context: NSExtensionContext?) async -> SharePayload {
        guard let context,
              let item = context.inputItems.first as? NSExtensionItem
        else { return SharePayload(type: .text) }

        let attachments = item.attachments ?? []

        // 1. URL
        if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            return await loadURL(from: provider, item: item)
        }
        // 2. Video (movie) — shared from Photos/Files. Checked before image so a
        //    video's poster frame doesn't get mistaken for an image capture.
        if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.movie.identifier) }) {
            return await loadVideo(from: provider)
        }
        // 3. Image
        if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            return await loadImage(from: provider)
        }
        // 4. Plain text
        if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            return await loadText(from: provider)
        }
        // 5. Document (PDF or any other file) — shared from Files/Books/etc. Checked
        //    last: url/movie/image/text are more specific. A PDF conforms to
        //    public.data but none of those, so it falls through to here.
        if let provider = attachments.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.data.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) {
            return await loadFile(from: provider)
        }

        return SharePayload(type: .text)
    }

    // MARK: - File (PDF / document)

    /// Copy a shared document out of the provider's transient storage into our own
    /// temp (like `loadVideo` — the provided URL is valid only inside the closure).
    /// We copy the FILE (no in-memory load) so a large PDF can't blow the extension's
    /// memory ceiling. The host persists it as a `.file` capture.
    private static func loadFile(from provider: NSItemProvider) async -> SharePayload {
        // Prefer a concrete data-bearing type (PDF/etc.), not a url/text alias.
        let typeID = provider.registeredTypeIdentifiers.first {
            guard let t = UTType($0) else { return false }
            return t.conforms(to: .data) && !t.conforms(to: .url) && !t.conforms(to: .text)
        } ?? UTType.pdf.identifier
        let result: (url: URL, name: String)? = await withCheckedContinuation { cont in
            provider.loadFileRepresentation(forTypeIdentifier: typeID) { url, _ in
                guard let url else { cont.resume(returning: nil); return }
                let name = url.lastPathComponent
                let ext = url.pathExtension.isEmpty ? "pdf" : url.pathExtension
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("shared_\(UUID().uuidString).\(ext)")
                do {
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.copyItem(at: url, to: dest)
                    cont.resume(returning: (dest, name))
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
        guard let result else { return SharePayload(type: .text) }
        let mime = UTType(filenameExtension: result.url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return SharePayload(type: .file, mimeType: mime, fileURL: result.url, fileName: result.name)
    }

    // MARK: - Video

    /// Copy a shared movie out of the provider's transient storage into our own
    /// temp (the provided URL is valid only inside the load closure). The host
    /// writes it to the App Group inbox; the main app imports it on drain. We copy
    /// the FILE (no in-memory load) so a large movie can't blow the extension's
    /// memory ceiling. `isVideo` is set even on copy failure so the host cancels
    /// (rather than showing the annotation sheet for a movie).
    private static func loadVideo(from provider: NSItemProvider) async -> SharePayload {
        let typeID = provider.registeredTypeIdentifiers.first {
            UTType($0)?.conforms(to: .movie) == true
        } ?? UTType.movie.identifier
        let tempURL: URL? = await withCheckedContinuation { cont in
            provider.loadFileRepresentation(forTypeIdentifier: typeID) { url, _ in
                guard let url else { cont.resume(returning: nil); return }
                let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("shared_\(UUID().uuidString).\(ext)")
                do {
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.copyItem(at: url, to: dest)
                    cont.resume(returning: dest)
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
        return SharePayload(type: .file, isVideo: true, videoURL: tempURL)
    }

    // MARK: - URL

    private static func loadURL(from provider: NSItemProvider, item: NSExtensionItem) async -> SharePayload {
        let url = await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { data, _ in
                cont.resume(returning: data as? URL)
            }
        }
        guard let url else { return SharePayload(type: .url) }

        // Try to extract the page title. Safari and Chrome store it in the first item's
        // `attributedContentText` when using the standard share extension mechanism.
        // We don't fall back to a network fetch — that would require networking
        // entitlements and the user's consent.
        var title: String?
        if let attributed = item.attributedContentText?.string, !attributed.isEmpty {
            title = attributed
        } else if let plain = item.attributedTitle?.string, !plain.isEmpty {
            title = plain
        }

        return SharePayload(
            type: .url,
            url: url.absoluteString,
            urlTitle: title
        )
    }

    // MARK: - Image

    private static func loadImage(from provider: NSItemProvider) async -> SharePayload {
        // Try PNG first, then fallback to generic image type.
        let typeID: String
        if provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
            typeID = UTType.png.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) {
            typeID = UTType.jpeg.identifier
        } else {
            typeID = UTType.image.identifier
        }

        let rawData: Data? = await withCheckedContinuation { cont in
            provider.loadDataRepresentation(forTypeIdentifier: typeID) { data, _ in
                cont.resume(returning: data)
            }
        }

        guard let rawData else { return SharePayload(type: .image) }

        // Normalise to JPEG for consistent storage (UIImage decode + re-encode).
        // Falls back to the original bytes if the UIImage round-trip fails.
        let (jpegData, mimeType): (Data, String)
        if let img = UIImage(data: rawData),
           let jpeg = img.jpegData(compressionQuality: 0.85) {
            jpegData = jpeg
            mimeType = "image/jpeg"
        } else {
            jpegData = rawData
            mimeType = typeID.contains("png") ? "image/png" : "image/jpeg"
        }

        let ext = mimeType == "image/png" ? "png" : "jpg"
        let fileName = "capture_\(UUID().uuidString).\(ext)"

        return SharePayload(
            type: .image,
            imageData: jpegData,
            imageFileName: fileName,
            mimeType: mimeType
        )
    }

    // MARK: - Text

    private static func loadText(from provider: NSItemProvider) async -> SharePayload {
        let text: String? = await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { data, _ in
                cont.resume(returning: data as? String)
            }
        }
        return SharePayload(type: .text, text: text)
    }
}
