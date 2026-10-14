import AVFoundation
import Foundation
import ImageIO
import PDFKit
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
    /// Q94 / C70: the file's ORIGINAL name (provider file name or suggestedName) - the
    /// shared `FilenameDate` ladder dates the clip from it. nil when unknown.
    var originalName: String? = nil
    /// Q94: position in the user's selection (the provider order = chat order).
    var selectionIndex: Int? = nil
}

/// One shared image (of possibly several), already downsampled + JPEG-normalised.
struct SharedImageItem {
    var data: Data
    var fileName: String
    var mimeType: String
    /// EXIF taken-date, read from the ORIGINAL bytes before the downsample
    /// re-encode stripped it (A4). nil = no metadata (screenshots, chat images).
    var recordedAt: Date?
    /// Q94 / C70: original filename / suggestedName - a Signal JPEG has no EXIF but a dated name.
    var originalName: String? = nil
    /// Q94: position in the user's selection.
    var selectionIndex: Int? = nil
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
    /// A shared movie was detected (Photos/Files). E1 (Wave 2, mock m1): the host
    /// shows the SLIM SHEET (preview + typed thought + significance) — no longer a
    /// silent import. `videoURL` is the extension-temp copy.
    /// Duration/filmed-date are best-effort reads for the preview card.
    var isVideo: Bool = false
    var videoURL: URL?
    var videoDuration: TimeInterval?
    var videoFilmedAt: Date?
    /// The shared movie's size, for the C63/C148 "over 200 MB, the movie is not kept" line.
    var videoBytes: Int64?
    /// A shared document (e.g. a PDF) was detected. E1 (mock m2): gets the slim
    /// sheet too. `fileURL` is the extension-temp copy; `fileName` the display
    /// name; pages/size feed the preview card (pages nil for non-PDFs).
    var fileURL: URL?
    var fileName: String?
    var filePageCount: Int?
    var fileSizeBytes: Int64?
    /// Shared AUDIO was detected (WhatsApp voice note / Voice Memos / Files).
    /// The sheet shows a slim audio card — NO ramble UI (signed 2026-07-10: the
    /// voice note IS the content; append inside the note later). 2+ clips add
    /// the 1-or-N chooser (B1). On save the host writes `"audio"` inbox entries;
    /// the main app imports them as transcribed memos (never a link or file
    /// card — the i4 fix). `audioItems` are extension-temp copies, ordered
    /// oldest→newest when clip dates are readable.
    var isAudio: Bool = false
    var audioItems: [SharedAudioItem] = []
    /// C146: the shared document is a book (`IngressDispatch.Plan.bookFile`) — a `.skriftbook`
    /// (or an `.m4b` / `.epub` that arrived as plain data). `fileURL` / `fileName` carry it; the
    /// host hands it to the app's book importer with no sheet, never a file card.
    var isBook: Bool = false
    /// C127: the share's bytes (`ShareFingerprint`), nil for a link or a text. The host looks it
    /// up in the `ShareLedger` before the sheet and records it on save.
    var fingerprint: String?
}

/// What the share extension shows for a share: the sheet, or an honest no (C75).
enum ShareLoad {
    case sheet(SharePayload)
    /// The dispatcher refused: nothing Skrift imports arrived.
    case unsupported
    /// A file the share carried could not be read out of its provider.
    case failed(String)
}

/// Loads the share from the extension context's input items.
///
/// Q439 / C238 / C67: this file only READS providers. Every provider of every extension item
/// is resolved (its types, its file copied out under a unique temp name, its inline text or
/// URL), and the ONE shared `IngressDispatch` decides what the share is and what it keeps. No
/// per-type branching lives here any more; the plan is mapped back to the temp copies.
///
/// **No network fetch** — the page title comes only from the item's `attributedContentText`
/// (Safari/Chrome supply it there). If unavailable, the sheet shows the domain.
enum SharePayloadLoader {

    /// One provider as read: the dispatcher's view of it, plus what the plan maps back to.
    private struct Resolved {
        var provider: IngressDispatch.Provider
        /// Selection position: item order, then provider order (C67, C125).
        var index: Int
        /// The extension-temp copy of a file provider (`provider.file` is its name).
        var fileURL: URL?
        /// The file's original name (provider file name / suggestedName), for dates and display.
        var originalName: String?
        /// The original file's date, read before the copy.
        var fileDate: Date?
        /// A loaded picture (`provider.file` is its key name).
        var image: SharedImageItem?
        /// The provider carried a file that could not be read.
        var failed = false
    }

    @MainActor
    static func load(from context: NSExtensionContext?) async -> ShareLoad {
        let items = (context?.inputItems ?? []).compactMap { $0 as? NSExtensionItem }
        // C67: ALL items, ALL providers, in selection order.
        var flat: [NSItemProvider] = []
        var shape: [[Int]] = []
        for item in items {
            let providers = item.attachments ?? []
            shape.append(Array(flat.count..<(flat.count + providers.count)))
            flat += providers
        }
        var slots: [Resolved?] = Array(repeating: nil, count: flat.count)
        await withTaskGroup(of: (Int, Resolved).self) { group in
            for (i, provider) in flat.enumerated() {
                group.addTask { (i, await resolve(provider, index: i)) }
            }
            for await (i, r) in group { slots[i] = r }
        }
        let resolved = slots.compactMap { $0 }
        let dispatchItems = zip(items, shape).map { item, indices in
            IngressDispatch.Item(providers: indices.map { resolved[$0].provider },
                                 title: item.attributedContentText?.string.nonEmpty ?? item.attributedTitle?.string)
        }
        let outcome = IngressDispatch.dispatch(dispatchItems)
        let byName = Dictionary(resolved.compactMap { r in r.provider.file.map { ($0, r) } },
                                uniquingKeysWith: { a, _ in a })

        let load: ShareLoad
        var kept: Set<URL> = []
        switch outcome {
        case .refuse:
            load = resolved.contains(where: \.failed) ? .failed("The share couldn't be read.") : .unsupported
        case .plan(let plan):
            var payload = await payload(for: plan, byName: byName)
            payload.fingerprint = fingerprint(of: payload, texts: plan.texts)
            for u in [payload.videoURL, payload.fileURL].compactMap({ $0 }) + payload.audioItems.map(\.url) {
                kept.insert(u)
            }
            load = .sheet(payload)
        }
        // Copies the plan did not keep (a movie beside a link, a document beside a clip): drop.
        for r in resolved { if let u = r.fileURL, !kept.contains(u) { try? FileManager.default.removeItem(at: u) } }
        return load
    }

    // MARK: - Fingerprint (C127)

    /// The kept bytes of a file-carrying share, plus its texts (a new caption on the same photo is
    /// a new share). nil for a link or a text share, and for a book (the book importer has its
    /// own "Already in your books").
    private static func fingerprint(of payload: SharePayload, texts: [String]) -> String? {
        guard !payload.isBook else { return nil }
        let files = payload.audioItems.map(\.url) + [payload.videoURL, payload.fileURL].compactMap { $0 }
        let pictures = payload.imageItems.map(\.data)
        guard !files.isEmpty || !pictures.isEmpty else { return nil }
        return ShareFingerprint.of(files: files, datas: pictures + texts.map { Data($0.utf8) })
    }

    // MARK: - Plan → payload

    private static func payload(for plan: IngressDispatch.Plan, byName: [String: Resolved]) async -> SharePayload {
        let text = plan.texts.isEmpty ? nil : plan.texts.joined(separator: "\n\n")
        let pictures = plan.pictures.compactMap { byName[$0]?.image }
        switch plan.kind {
        case .audio:
            var clips: [SharedAudioItem] = plan.clips.compactMap { name in
                guard let r = byName[name], let url = r.fileURL else { return nil }
                return SharedAudioItem(url: url, duration: (try? AVAudioFile(forReading: url))?.seconds,
                                       recordedAt: r.fileDate, originalName: r.originalName,
                                       selectionIndex: r.index)
            }
            // Oldest → newest via the STABLE order helper (equal WhatsApp temp dates keep the
            // chat order). Q94 / C70: a filename date outranks the file date.
            let order = CaptureInbox.stableClipOrder(
                dates: clips.map { FilenameDate.ladder(embedded: nil, filename: $0.originalName, fileDate: $0.recordedAt) })
            clips = order.map { clips[$0] }
            return SharePayload(type: .file, text: text, imageItems: pictures, isAudio: true, audioItems: clips)
        case .url:
            return SharePayload(type: .url, url: plan.url, urlTitle: plan.title)
        case .text:
            return SharePayload(type: .text, url: plan.url, urlTitle: plan.title, text: text)
        case .image:
            // Positions count pictures only (one picture note, B2).
            let items = pictures.enumerated().map { i, p in var p = p; p.selectionIndex = i; return p }
            return SharePayload(type: .image, text: text, imageItems: items, mimeType: items.first?.mimeType)
        case .movie:
            guard let url = plan.file.flatMap({ byName[$0]?.fileURL }) else { return SharePayload(type: .file) }
            // E1 preview-card metadata (mock m1) — best-effort, nil on odd containers.
            var duration: TimeInterval?
            var filmedAt: Date?
            let asset = AVURLAsset(url: url)
            if let d = try? await asset.load(.duration) {
                let secs = CMTimeGetSeconds(d)
                if secs.isFinite, secs > 0 { duration = secs }
            }
            if let item = (try? await asset.load(.creationDate)) ?? nil {
                filmedAt = (try? await item.load(.dateValue)) ?? nil
            }
            return SharePayload(type: .file, text: text, isVideo: true, videoURL: url,
                                videoDuration: duration, videoFilmedAt: filmedAt,
                                videoBytes: VideoKeep.byteCount(of: url))
        case .document:
            guard let r = plan.file.flatMap({ byName[$0] }), let url = r.fileURL else { return SharePayload(type: .file) }
            if plan.bookFile != nil {
                // C146 (Q440): the book route sits inside the document branch, as ImportKinds
                // splits it for a Mac drop. A book goes to the book importer, never a file card.
                return SharePayload(type: .file, fileURL: url, fileName: r.originalName ?? url.lastPathComponent,
                                    isBook: true)
            }
            let ext = url.pathExtension.lowercased()
            let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
            // E1 preview-card metadata (mock m2): page count for PDFs, size for all.
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64
            let pages = ext == "pdf" ? PDFDocument(url: url)?.pageCount : nil
            return SharePayload(type: .file, text: text, mimeType: mime, fileURL: url,
                                fileName: r.originalName ?? url.lastPathComponent,
                                filePageCount: pages, fileSizeBytes: size)
        }
    }

    // MARK: - Reading one provider

    /// Read one provider for the dispatcher. Which representation is read is a loading choice
    /// (a file for media and documents, the value for a link or a text), never a routing one:
    /// a file always arrives under its real extension, so `IngressDispatch` routes an odd-UTI
    /// voice note (Signal `.aac`, Telegram `.ogg`) as audio by its name (D7, C69).
    private static func resolve(_ provider: NSItemProvider, index: Int) async -> Resolved {
        let utis = provider.registeredTypeIdentifiers
        var r = Resolved(provider: .init(uti: utis), index: index)
        func conforms(_ t: UTType) -> Bool { provider.hasItemConformingToTypeIdentifier(t.identifier) }

        if conforms(.audio) || conforms(.movie) {
            let want: UTType = conforms(.audio) ? .audio : .movie
            let typeID = utis.first { UTType($0)?.conforms(to: want) == true } ?? want.identifier
            adopt(await copyFile(provider, typeID: typeID, defaultExt: want == .audio ? "m4a" : "mov"), into: &r)
        } else if conforms(.image) {
            if let image = await loadImage(from: provider, index: index) {
                r.image = image
                r.provider.file = image.fileName
                r.originalName = image.originalName
            } else {
                r.failed = true
            }
        } else if conforms(.url), !conforms(.fileURL) {
            r.provider.url = await withCheckedContinuation { cont in
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { data, _ in
                    cont.resume(returning: (data as? URL)?.absoluteString)
                }
            }
        } else if conforms(.plainText) {
            // Selected text arrives as a String; a text FILE (.txt / .md from Files) as its file
            // URL, copied out INSIDE the closure (the URL is transient) — a document (D4).
            let suggested = provider.suggestedName
            let value: (text: String?, copy: Copied?) = await withCheckedContinuation { cont in
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { data, _ in
                    switch data {
                    case let s as String: cont.resume(returning: (s, nil))
                    case let d as Data: cont.resume(returning: (String(data: d, encoding: .utf8), nil))
                    case let u as URL: cont.resume(returning: (nil, copyOut(u, suggested: suggested, defaultExt: "txt")))
                    default: cont.resume(returning: (nil, nil))
                    }
                }
            }
            r.provider.text = value.text
            if value.copy != nil || value.text == nil {
                adopt(value.copy, into: &r)
            }
        } else if conforms(.pdf) || conforms(.data) || conforms(.fileURL) {
            // A document (PDF or any other file) from Files / Books: a concrete data type,
            // never a url / text alias.
            let typeID = utis.first {
                guard let t = UTType($0) else { return false }
                return t.conforms(to: .data) && !t.conforms(to: .url) && !t.conforms(to: .text)
            } ?? UTType.pdf.identifier
            adopt(await copyFile(provider, typeID: typeID, defaultExt: "pdf"), into: &r)
        }
        return r
    }

    private typealias Copied = (url: URL, name: String?, date: Date?)

    /// A provider's file copy becomes its dispatcher name; no copy is a failed read.
    private static func adopt(_ copied: Copied?, into r: inout Resolved) {
        guard let copied else { r.failed = true; return }
        r.fileURL = copied.url
        r.provider.file = copied.url.lastPathComponent   // unique, real extension
        r.originalName = copied.name
        r.fileDate = copied.date
    }

    /// Copy a provider's file out of its transient storage (valid only inside the closure) into
    /// our own temp — a file copy, never an in-memory load, so a large movie or PDF can't blow
    /// the extension's memory ceiling.
    private static func copyFile(_ provider: NSItemProvider, typeID: String, defaultExt: String) async -> Copied? {
        let suggested = provider.suggestedName
        return await withCheckedContinuation { cont in
            provider.loadFileRepresentation(forTypeIdentifier: typeID) { url, _ in
                cont.resume(returning: url.flatMap { copyOut($0, suggested: suggested, defaultExt: defaultExt) })
            }
        }
    }

    /// The copy itself. Q94: the ORIGINAL name and file date are read BEFORE the copy renames it
    /// `shared_<uuid>` (Q134: the shared file-date rung, earlier of creation / modification).
    private static func copyOut(_ url: URL, suggested: String?, defaultExt: String) -> Copied? {
        let name = FilenameDate.bestName([url.lastPathComponent, suggested])
        let date = FilenameDate.fileDate(of: url)
        let ext = url.pathExtension.isEmpty ? defaultExt : url.pathExtension
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("shared_\(UUID().uuidString).\(ext)")
        try? FileManager.default.removeItem(at: dest)
        guard (try? FileManager.default.copyItem(at: url, to: dest)) != nil else { return nil }
        return (dest, name, date)
    }

    // MARK: - Image(s)

    /// Load every shared image (see `loadImage`). Q57/C218: each provider loads CONCURRENTLY,
    /// results landing in a slot array keyed by original index — provider order survives
    /// regardless of completion order.
    static func loadImages(from providers: [NSItemProvider], positions: [Int]? = nil) async -> SharePayload {
        var slots: [SharedImageItem?] = Array(repeating: nil, count: providers.count)
        await withTaskGroup(of: (Int, SharedImageItem?).self) { group in
            for (i, provider) in providers.enumerated() {
                group.addTask { (i, await loadImage(from: provider, index: positions?[i] ?? i)) }
            }
            for await (i, item) in group { slots[i] = item }
        }
        let items = slots.compactMap { $0 }
        return SharePayload(type: .image, imageItems: items, mimeType: items.first?.mimeType)
    }

    /// One shared image, DOWNSAMPLED via ImageIO (max 2048 px, EXIF orientation baked in) — a
    /// full `UIImage(data:)` decode of a 48 MP shot would blow the extension's ~120 MB ceiling,
    /// and a multi-select multiplies that. Normalised by the shared `ImageNormalise` (C74 / D17):
    /// PNG stays PNG, a GIF is kept byte-for-byte, HEIC/TIFF/BMP become JPEG 0.9. nil when
    /// unreadable.
    private static func loadImage(from provider: NSItemProvider, index: Int) async -> SharedImageItem? {
        let typeID: String
        if provider.hasItemConformingToTypeIdentifier(UTType.gif.identifier) {
            typeID = UTType.gif.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
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
        guard let rawData, let norm = ImageNormalise.normalise(rawData) else { return nil }
        return SharedImageItem(
            data: norm.data,
            fileName: "capture_\(UUID().uuidString).\(norm.ext)",
            mimeType: norm.mime,
            recordedAt: ImageDates.exifDate(from: rawData),   // BEFORE the re-encode (A4)
            originalName: FilenameDate.bestName([provider.suggestedName]),   // Q94 / C70
            selectionIndex: index
        )
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
