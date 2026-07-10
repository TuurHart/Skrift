import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit

/// One shared audio clip (of possibly several — A11 multi-select).
struct SharedAudioItem {
    var url: URL
    /// Best-effort clip length for the card label; nil when unreadable (ogg-opus).
    var duration: TimeInterval?
    /// Best-effort original recording moment (file date) — drives the
    /// oldest→newest combine order. nil when the provider strips dates.
    var recordedAt: Date?
}

/// One shared image (of possibly several), already downsampled + JPEG-normalised.
struct SharedImageItem {
    var data: Data
    var fileName: String
    var mimeType: String
}

/// The resolved content of the share action, ready to display in the sheet.
/// Only the fields relevant to the type are populated.
struct SharePayload {
    var type: ShareContentType
    var url: String?
    /// Page title from the share item's `attributedContentText` (no network fetch).
    var urlTitle: String?
    var text: String?
    /// Image captures (1..N — multiple photos ALWAYS combine into one note, B2).
    var imageItems: [SharedImageItem] = []
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
    /// Shared AUDIO was detected (WhatsApp voice note / Voice Memos / Files).
    /// The sheet shows a slim audio card — NO ramble UI (signed 2026-07-10: the
    /// voice note IS the content; append inside the note later). 2+ clips add
    /// the 1-or-N chooser (B1). On save the host writes `"audio"` inbox entries;
    /// the main app imports them as transcribed memos (never a link or file
    /// card — the i4 fix). `audioItems` are extension-temp copies, ordered
    /// oldest→newest when clip dates are readable.
    var isAudio: Bool = false
    var audioItems: [SharedAudioItem] = []
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

        // 1. Audio — checked FIRST. A WhatsApp voice note exposes BOTH an audio
        //    file and a URL representation, so the url branch used to win and the
        //    share saved a LINK (bug i4, root-caused 2026-07-07). Anything
        //    conforming to public.audio is an audio import, full stop. ALL audio
        //    attachments are collected (A11 multi-select — activation allows 10).
        let audioProviders = attachments.filter { $0.hasItemConformingToTypeIdentifier(UTType.audio.identifier) }
        if !audioProviders.isEmpty {
            return await loadAudio(from: audioProviders)
        }
        // 2. URL
        if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            return await loadURL(from: provider, item: item)
        }
        // 3. Video (movie) — shared from Photos/Files. Checked before image so a
        //    video's poster frame doesn't get mistaken for an image capture.
        if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.movie.identifier) }) {
            return await loadVideo(from: provider)
        }
        // 4. Image(s) — multiple photos always combine into ONE note (B2).
        let imageProviders = attachments.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        if !imageProviders.isEmpty {
            return await loadImages(from: imageProviders)
        }
        // 5. Plain text
        if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            return await loadText(from: provider)
        }
        // 6. Document (PDF or any other file) — shared from Files/Books/etc. Checked
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

    // MARK: - Audio

    /// Copy each shared audio clip out of its provider's transient storage into
    /// our own temp (same rationale as `loadVideo` — file copy, never an
    /// in-memory load). Duration is read best-effort for the card labels; an
    /// unreadable container (e.g. ogg-opus from some messengers) just shows no
    /// duration — the import itself still proceeds and the transcriber/Mac
    /// handles or fails that memo honestly downstream. Clips are ordered
    /// oldest→newest when every clip carries a readable file date (a forwarded
    /// WhatsApp thread reads chronologically); otherwise provider order is kept.
    private static func loadAudio(from providers: [NSItemProvider]) async -> SharePayload {
        var items: [SharedAudioItem] = []
        for provider in providers {
            let typeID = provider.registeredTypeIdentifiers.first {
                UTType($0)?.conforms(to: .audio) == true
            } ?? UTType.audio.identifier
            let copied: (url: URL, date: Date?)? = await withCheckedContinuation { cont in
                provider.loadFileRepresentation(forTypeIdentifier: typeID) { url, _ in
                    guard let url else { cont.resume(returning: nil); return }
                    // Original file date, read BEFORE the copy (best-effort order key).
                    let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
                    let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
                    let dest = FileManager.default.temporaryDirectory
                        .appendingPathComponent("shared_\(UUID().uuidString).\(ext)")
                    do {
                        try? FileManager.default.removeItem(at: dest)
                        try FileManager.default.copyItem(at: url, to: dest)
                        cont.resume(returning: (dest, date))
                    } catch {
                        cont.resume(returning: nil)
                    }
                }
            }
            guard let copied else { continue }
            var duration: TimeInterval?
            if let f = try? AVAudioFile(forReading: copied.url) {
                duration = Double(f.length) / f.fileFormat.sampleRate
            }
            items.append(SharedAudioItem(url: copied.url, duration: duration, recordedAt: copied.date))
        }
        // Oldest → newest, only when EVERY clip has a date (a partial sort would
        // scramble the provider order, which is the next-best signal).
        if items.count > 1, items.allSatisfy({ $0.recordedAt != nil }) {
            items.sort { ($0.recordedAt ?? .distantPast) < ($1.recordedAt ?? .distantPast) }
        }
        return SharePayload(type: .file, isAudio: true, audioItems: items)
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

    // MARK: - Image(s)

    /// Load every shared image, DOWNSAMPLED via ImageIO (max 2048 px, EXIF
    /// orientation baked in) — a full `UIImage(data:)` decode of a 48 MP shot
    /// would blow the extension's ~120 MB ceiling, and a multi-select multiplies
    /// that. Normalised to JPEG 0.85 for consistent storage. Unreadable images
    /// are skipped; multiple photos always combine into ONE note (B2).
    private static func loadImages(from providers: [NSItemProvider]) async -> SharePayload {
        var items: [SharedImageItem] = []
        for provider in providers {
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
            guard let rawData, let jpeg = downsampledJPEG(from: rawData) else { continue }
            items.append(SharedImageItem(
                data: jpeg,
                fileName: "capture_\(UUID().uuidString).jpg",
                mimeType: "image/jpeg"
            ))
        }
        return SharePayload(type: .image, imageItems: items, mimeType: items.isEmpty ? nil : "image/jpeg")
    }

    /// ImageIO thumbnail decode: never inflates the full-resolution bitmap
    /// (kCGImageSourceThumbnailMaxPixelSize caps the decode) and bakes the EXIF
    /// orientation in (WithTransform). Falls back to the raw bytes → nil only
    /// when the data isn't an image at all.
    private static func downsampledJPEG(from data: Data, maxPixel: CGFloat = 2048) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.85)
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
