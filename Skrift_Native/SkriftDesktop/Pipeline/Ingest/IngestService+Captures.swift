import Foundation
import SwiftData

/// Q136 (C77, C72, C73, D19, D22): the Mac side of what the phone's share drain makes of a
/// text file, a PDF and a link. The same `SharedContent` shape, the same working-folder layout
/// a phone capture materializes into (`capture_<id>/files/file_<id>.pdf`, the thumbnail beside
/// it) and the same title ladder (`NoteTitle`), so a Mac drop and a phone share of the same
/// thing are the same note kind with the same title.
extension IngestService {

    /// An http(s) URL (a link dragged in from a browser), as opposed to a file.
    static func isWebURL(_ url: URL) -> Bool {
        guard !url.isFileURL, let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    // MARK: - Text file → text capture (D22)

    /// A dropped `.txt`: the file's text IS the body of a text capture, no document kept. An
    /// oversized, non-UTF-8 or blank file stays a document capture, as on the phone.
    func ingestTextCapture(_ url: URL, into context: ModelContext) async throws -> PipelineFile {
        let body = await Task.detached(priority: .userInitiated) { () -> String? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return SharedTextFile.body(of: data)
        }.value
        guard let body else { return try await ingestDocumentCapture(url, into: context) }
        return try await makeCapture(shared: SharedContent(type: .text, fileName: url.lastPathComponent),
                                     body: body, location: nil, document: nil, thumbnail: nil,
                                     into: context)
    }

    // MARK: - PDF / other document → file capture (C73)

    /// A dropped document: copied under the capture's `files/` (the Mac opens the real file),
    /// and a PDF's embedded text goes in `sharedContent.text` so it is searchable. A scanned
    /// PDF has no text and stays findable by its name.
    func ingestDocumentCapture(_ url: URL, into context: ModelContext) async throws -> PipelineFile {
        let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
        let ext = url.pathExtension.lowercased()
        let mime = ext == "pdf" ? "application/pdf" : (ext == "txt" ? "text/plain" : "application/octet-stream")
        return try await makeCapture(
            shared: SharedContent(type: .file, fileName: url.lastPathComponent, mimeType: mime),
            body: "", location: nil, document: (data, ext.isEmpty ? "pdf" : ext), thumbnail: nil,
            into: context)
    }

    // MARK: - Web link → link capture (C72, D6, C5)

    /// A dragged-in link, run through the phone's routine: a Maps share → a place; a link that
    /// points AT a PDF → the downloaded file (magic-byte check) with its text; anything else →
    /// one GET for title / description / thumbnail / article text. A failed fetch keeps a bare
    /// link card titled by its HOST, never the raw URL (C72). There is no retry on the Mac.
    func ingestLink(_ url: URL, into context: ModelContext) async throws -> PipelineFile? {
        guard Self.isWebURL(url) else { return nil }
        let raw = url.absoluteString
        var shared = SharedContent(type: .url, url: raw)
        var location: LocationInfo?
        var document: (data: Data, ext: String)?
        var thumbnail: Data?

        if let place = PlaceLink.parse(raw) {
            location = LocationInfo(latitude: place.latitude, longitude: place.longitude, placeName: place.name)
            shared.urlTitle = place.name
        } else {
            if await LinkCard.pointsAtPDF(url, fetcher: linkFetcher),
               let pdf = await LinkCard.downloadPDF(url, fetcher: linkFetcher) {
                document = (pdf, "pdf")
                shared = SharedContent(type: .file, fileName: url.lastPathComponent, mimeType: "application/pdf")
            }
            if shared.type == .url, let card = await LinkCard.enrich(url: url, fetcher: linkFetcher) {
                shared.urlTitle = card.title
                shared.urlDescription = card.descriptionText
                shared.text = card.articleText
                thumbnail = card.thumbnailJPEG
            }
        }
        if shared.type == .url, shared.urlTitle?.trimmingCharacters(in: .whitespaces).isEmpty != false {
            shared.urlTitle = LinkCard.hostTitle(url)
        }
        return try await makeCapture(shared: shared, body: "", location: location, document: document,
                                     thumbnail: thumbnail, into: context)
    }

    // MARK: - The capture row

    /// Writes one capture's working folder and inserts its row: `sharedContent` + the body in
    /// the metadata blob (what a phone capture's synced blob carries), the body as the
    /// transcript (so transcription is `.done`, there is nothing to hear), unrated (D159).
    private func makeCapture(shared initial: SharedContent, body: String, location: LocationInfo?,
                             document: (data: Data, ext: String)?, thumbnail: Data?,
                             into context: ModelContext) async throws -> PipelineFile {
        let id = UUID().uuidString
        let folder = outputDir.appendingPathComponent("capture_\(id)", isDirectory: true)
        var shared = initial
        let extractor = pdfExtractor
        let written = try await Task.detached(priority: .userInitiated) { () -> (filePath: String?, text: String?, thumb: String?) in
            let fm = FileManager.default
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var filePath: String?, text: String?, thumb: String?
            if let document {
                // The phone's own names: `file_<id>.<ext>` is `filePath`, the asset filename.
                let name = "file_\(id).\(document.ext)"
                let dir = folder.appendingPathComponent("files", isDirectory: true)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let dest = dir.appendingPathComponent(name)
                try document.data.write(to: dest)
                filePath = name
                if document.ext == "pdf" { text = extractor.text(of: dest) }
            }
            if let thumbnail {
                let name = "linkthumb_\(id).jpg"
                if (try? thumbnail.write(to: folder.appendingPathComponent(name))) != nil { thumb = name }
            }
            return (filePath, text, thumb)
        }.value
        if let p = written.filePath { shared.filePath = p }
        if let t = written.text { shared.text = t }
        if let th = written.thumb { shared.urlThumbnailUrl = th }

        var meta: [String: Any] = [:]
        if let enc = try? JSONEncoder().encode(shared),
           let obj = try? JSONSerialization.jsonObject(with: enc) { meta["sharedContent"] = obj }
        meta["annotationText"] = body
        if let location, let enc = try? JSONEncoder().encode(location),
           let obj = try? JSONSerialization.jsonObject(with: enc) { meta["location"] = obj }

        let pf = PipelineFile(id: id, filename: "capture_\(id)", path: folder.path,
                              size: body.utf8.count, sourceType: .capture)
        pf.audioMetadataJSON = try? JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys])
        pf.transcript = body
        pf.transcribeStatus = .done
        pf.isLocalRecording = isLocalRecording
        pf.isLocalImport = !isLocalRecording
        context.insert(pf)
        return pf
    }
}
