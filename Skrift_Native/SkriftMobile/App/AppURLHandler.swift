import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Routes incoming URLs to the right action:
/// - a shared audio file ("Open in Skrift" / Share Sheet / the Files picker) → import as a memo
/// - a shared VIDEO file → extract audio + a frame thumbnail → import as a memo
/// - a picture, a text/markdown file or a PDF → a capture, through the same inbox the share
///   extension writes (so the drain, not a second importer, makes the note)
/// - the `skrift://record` deep link → start recording (wired in 8d)
/// - the `skrift://newnote` deep link → open the quick-note screen (Q7)
///
/// What a file IS comes from `ImportKinds` (C238): Open-in, the share extension, the Files
/// picker and the Mac ingest read ONE extension list (C199: Open-in accepts what the share
/// sheet accepts).
@MainActor
enum AppURLHandler {
    /// The kind a file URL resolves to — the one the Mac's `IngestService.importKind(of:)`
    /// returns for the same name (`ImportKindsTests`, both targets).
    nonisolated static func importKind(of url: URL) -> ImportKinds.Kind? { ImportKinds.kind(of: url) }

    static func handle(_ url: URL) {
        if url.isFileURL {
            // 📦 A book someone shared (AirDrop / Files / Messages). Checked FIRST:
            // a `.skriftbook` is a zip, and letting the audio branch below reason
            // about it would import the archive as a memo. Nothing lands in the
            // library here — the bridge shows the sheet and the user decides.
            if BookBundle.isBookBundle(url) {
                BookImportBridge.shared.offer(url)
                return
            }
            // Land the user on the imported memo (A9): it relocates to the media's
            // embedded date, so without the jump it "vanishes" down the list — the
            // same rule the share-sheet drain path already follows.
            switch importKind(of: url) {
            case .video:
                // A video container (.mov/.mp4/…): strip the audio + grab a frame.
                if let id = MemoSaver().importVideo(from: url) {
                    MemoOpenBridge.shared.open(id)
                }
            case .audio:
                if let id = MemoSaver().importAudio(from: url) {
                    MemoOpenBridge.shared.open(id)
                }
            case .image, .text, .document:
                importAsCapture(url)
            case .book, .none:
                break   // books have their own door (the Books library); anything else is not ours
            }
            return
        }
        // skrift://record (Lock Screen widget / Siri / any deep link) → start a
        // recording via the same bridge the Record App Intent uses.
        if url.scheme == "skrift", url.host == "record" {
            RecordingIntentBridge.shared.requestStart()
        }
        // skrift://newnote (Lock Screen widget) → open the quick-note screen
        // via the same bridge the New Note App Intent uses (C112).
        if url.scheme == "skrift", url.host == "newnote" {
            QuickNoteBridge.shared.requestNew()
        }
    }

    // MARK: - Pictures, text and PDFs

    /// Write the file as a capture-inbox entry — the shape the share extension writes for the
    /// same file — then drain it. Returns false when the file could not be read or written.
    @discardableResult
    static func importAsCapture(_ url: URL) -> Bool {
        guard let kind = importKind(of: url), [.image, .text, .document].contains(kind) else { return false }
        // Files from outside the sandbox arrive security-scoped.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        let id = UUID()
        let sharedAt = ISO8601.string(from: Date())
        let name = url.lastPathComponent
        let wrote: Bool
        if kind == .image {
            guard let raw = try? Data(contentsOf: url), let jpeg = downsampledJPEG(from: raw) else { return false }
            let fileName = "capture_\(id.uuidString).jpg"
            let taken = ImageDates.exifDate(from: raw).map { ISO8601.string(from: $0) } ?? ""
            let entry = CaptureInboxEntry(
                id: id, type: "image", url: nil, urlTitle: nil, text: nil,
                imageFileName: fileName, mimeType: "image/jpeg", annotationText: nil,
                significance: 0, sharedAt: sharedAt,
                imageFileNames: [fileName],
                imageRecordedAts: [taken],
                imageOriginalNames: [name],
                imageSelectionPositions: [0])
            wrote = CaptureInbox.write(entry, imageDatas: [jpeg])
        } else {
            let ext = url.pathExtension.isEmpty ? "pdf" : url.pathExtension
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let entry = CaptureInboxEntry(
                id: id, type: "file", url: nil, urlTitle: nil, text: nil,
                imageFileName: nil, mimeType: mime, annotationText: nil,
                significance: 0, sharedAt: sharedAt,
                fileName: "file_\(id.uuidString).\(ext)", fileDisplayName: name)
            wrote = CaptureInbox.write(entry, fileSourceURL: url)
        }
        if wrote { Task { await CaptureInboxDrainer.drain(into: NotesRepository.shared) } }
        return wrote
    }

    /// ImageIO thumbnail decode (never inflates the full bitmap), EXIF orientation baked in —
    /// the bounds the share extension's loader uses.
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
}
