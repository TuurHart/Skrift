import Combine
import Foundation
import PDFKit
import SwiftData

/// Observable pending-share state for the UI (A14): non-zero while the drainer is
/// copying share-imports out of the inbox. `MemosListView` shows a small top pill —
/// before this, captures materialized with NO feedback until the drain finished.
@MainActor
final class CaptureDrainState: ObservableObject {
    static let shared = CaptureDrainState()
    @Published private(set) var pendingCount = 0
    func begin(_ n: Int) { pendingCount = n }
    func completeOne() { pendingCount = max(0, pendingCount - 1) }
    func end() { pendingCount = 0 }
}

/// Drains the CaptureInbox (written by the SkriftShare extension) into SwiftData
/// Memo objects.
///
/// **Crash-safety:** entries are deleted ONLY after the Memo is saved. If the process
/// dies between the save and the delete, the next drain re-creates the Memo. We dedup
/// with an explicit `repository.memo(id:)` check before inserting (below): when a memo
/// with the same UUID already exists we skip the insert and just delete the inbox entry.
/// (`Memo.id` is no longer `@Attribute(.unique)` — dropped for CloudKit-backed SwiftData
/// in standalone Phase 1; this explicit check is now the sole dedup.)
///
/// **Thread model:** main-actor for all SwiftData writes; the BLOB COPIES hop to a
/// background executor (`offMain`) so a big shared movie never hitches launch (A14).
@MainActor
enum CaptureInboxDrainer {

    /// Reentrancy guard: `drain` now suspends mid-loop (off-main copies), and launch
    /// + foreground-transition both fire it around the same moment — a second drain
    /// interleaving with the first would double-import the delete-first media types.
    private static var isDraining = false

    /// Run file copies on a background executor — the main actor only orchestrates.
    private static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .userInitiated) { work() }.value
    }

    /// HEAD sniff for extensionless PDF links (C5): true when the server says the
    /// resource is a PDF. The magic-byte check in `downloadPDF` stays the real gate.
    private static func headSaysPDF(_ remote: URL) async -> Bool {
        var request = URLRequest(url: remote)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return isPDFContentType((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"))
    }

    /// Pure content-type gate — "application/pdf" with any casing/parameters
    /// (arxiv sends "application/pdf; qs=0.001").
    nonisolated static func isPDFContentType(_ value: String?) -> Bool {
        guard let first = value?.lowercased().split(separator: ";").first else { return false }
        return first.trimmingCharacters(in: .whitespaces) == "application/pdf"
    }

    /// Download a remote PDF into the recordings dir (C5). True only when the fetch
    /// succeeded AND the payload really is a PDF (magic bytes — content-type headers
    /// lie). `file://` URLs work too (Files-app links / unit tests).
    private static func downloadPDF(from remote: URL, toRecordingsAs destName: String) async -> Bool {
        var request = URLRequest(url: remote)
        request.timeoutInterval = 20
        guard let (temp, response) = try? await URLSession.shared.download(for: request) else { return false }
        defer { try? FileManager.default.removeItem(at: temp) }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return false }
        guard let fh = try? FileHandle(forReadingFrom: temp) else { return false }
        let head = try? fh.read(upToCount: 5)
        try? fh.close()
        guard head?.starts(with: Data("%PDF".utf8)) == true else { return false }
        let destURL = AppPaths.recordingsDirectory.appendingPathComponent(destName)
        try? FileManager.default.removeItem(at: destURL)
        return (try? FileManager.default.copyItem(at: temp, to: destURL)) != nil
    }

    /// Convert each pending inbox entry to a Memo and save. Idempotent: safe to call
    /// on every foreground transition. Also resumes any dictation transcription a
    /// previous run never finished (crash / terminal failure recovery).
    ///
    /// Runs under a background-task assertion (Scribbel `ImportTranscriber` pattern):
    /// a user who opens Skrift after sharing and immediately switches away gets ~30s
    /// of grace to finish the copies + imports instead of suspending mid-drain. The
    /// crash-safe inbox (delete-after-save) remains the backstop if even that expires.
    static func drain(into repository: NotesRepository) async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }
        CaptureInbox.log = { DevLog.log($0) }   // tombstone diagnostics (app-side only)
        await BackgroundTask.run(name: "skrift.share-drain") {
            await drainCore(into: repository)
        }
    }

    private static func drainCore(into repository: NotesRepository) async {
        defer { CaptureDictation.resumePending(repository: repository) }
        // Surface any share-extension diagnostics in the app devlog (the
        // extension can't write devlog.txt itself — round-1 mic mystery).
        CaptureInbox.flushExtLog { DevLog.log($0) }

        // Every share jumps to its note on the next app-open (signed 2026-07-10,
        // mock share-ingest-wave1.html) — collect the last created memo and fire
        // ONE bridge request after the loop (the bridge keeps most-recent-wins).
        var openTarget: UUID?
        defer { if let openTarget { MemoOpenBridge.shared.open(openTarget) } }

        // Re-read until empty: entries shared WHILE a drain is suspended on a copy
        // are picked up in a follow-up pass. `processed` guards termination — an
        // entry that survives its delete (pathological) is attempted only once.
        var processed = Set<UUID>()
        while true {
            let pending = CaptureInbox.pendingEntries().filter { !processed.contains($0.0.id) }
            guard !pending.isEmpty else { break }
            CaptureDrainState.shared.begin(pending.count)
            for (entry, entryDir) in pending {
                processed.insert(entry.id)
                if let opened = await process(entry: entry, entryDir: entryDir, into: repository) {
                    openTarget = opened
                }
                CaptureDrainState.shared.completeOne()
            }
        }
        CaptureDrainState.shared.end()
    }

    /// Handle ONE inbox entry. Returns the created memo's id when the user should
    /// land on it (every share jumps to its note), nil when the entry was discarded.
    private static func process(entry: CaptureInboxEntry, entryDir: URL,
                                into repository: NotesRepository) async -> UUID? {
        let memoID = entry.id

        // Shared VIDEO → import as a normal voice memo (audio + a frame
        // thumbnail + transcribe), NOT a capture item. Copy it out of the
        // inbox, delete the entry FIRST (a re-drain must not double-import —
        // importVideo mints its OWN memo UUID, so the id-dup guard below
        // wouldn't catch it), then import from the app-owned temp.
        if entry.type == "video" {
            let src0 = CaptureInbox.videoURL(for: entry, entryDir: entryDir)
            DevLog.log("drain: video entry \(entry.id); src present=\(src0.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)")
            if let src = src0, FileManager.default.fileExists(atPath: src.path) {
                let ext = src.pathExtension.isEmpty ? "mov" : src.pathExtension
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("shared_import_\(entry.id.uuidString).\(ext)")
                // The movie copy is the drain's heaviest hitch — off-main (A14).
                let copied = await offMain { () -> Bool in
                    try? FileManager.default.removeItem(at: temp)
                    return (try? FileManager.default.copyItem(at: src, to: temp)) != nil
                }
                DevLog.log("drain: video copied=\(copied) → \(temp.lastPathComponent); deleting entry + importing")
                CaptureInbox.delete(entryDir: entryDir)
                // Land the user on the imported memo: it relocates to the
                // video's filming date, so otherwise it "vanishes" from the
                // top of the list (user-confirmed via DevLog 2026-06-14).
                if copied, let mid = MemoSaver(repository: repository).importVideo(from: temp) {
                    return mid
                }
            } else {
                DevLog.log("drain: video entry \(entry.id) — no src file, discarding")
                CaptureInbox.delete(entryDir: entryDir)
            }
            return nil
        }

        // Shared AUDIO (WhatsApp voice notes / Voice Memos / Files) → import as
        // a normal transcribed memo, NOT a capture item (the i4 fix — the url
        // branch used to win and save a LINK; a Files m4a became a dead file
        // card). One entry with N clip names = the B1 combine (clips merged in
        // order → one transcript); split notes arrive as N single-clip entries.
        // Same delete-first pattern as video: importAudioClips mints its own
        // memo UUID, so the id-dup guard below wouldn't catch a re-drain.
        if entry.type == "audio" {
            let srcs = CaptureInbox.audioURLs(for: entry, entryDir: entryDir)
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            DevLog.log("drain: audio entry \(entry.id); clips present=\(srcs.count)/\(entry.audioFileNames?.count ?? 0)")
            if !srcs.isEmpty {
                // Copy every clip to an app-owned temp BEFORE deleting the entry.
                let entryID = entry.id.uuidString
                let temps = await offMain { () -> [URL] in
                    var out: [URL] = []
                    for (i, src) in srcs.enumerated() {
                        let ext = src.pathExtension.isEmpty ? "m4a" : src.pathExtension
                        let temp = FileManager.default.temporaryDirectory
                            .appendingPathComponent("shared_import_\(entryID)_\(i).\(ext)")
                        try? FileManager.default.removeItem(at: temp)
                        if (try? FileManager.default.copyItem(at: src, to: temp)) != nil {
                            out.append(temp)
                        }
                    }
                    return out
                }
                // B3: bundled photos copy out WITH the clips (the entry dir is
                // deleted next; same crash-safe ordering as the clips).
                let imageSrcs = CaptureInbox.imageURLs(for: entry, entryDir: entryDir)
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
                let imageTemps = imageSrcs.isEmpty ? [] : await offMain { () -> [URL] in
                    var out: [URL] = []
                    for (i, src) in imageSrcs.enumerated() {
                        let temp = FileManager.default.temporaryDirectory
                            .appendingPathComponent("shared_import_img_\(entryID)_\(i).jpg")
                        try? FileManager.default.removeItem(at: temp)
                        if (try? FileManager.default.copyItem(at: src, to: temp)) != nil {
                            out.append(temp)
                        }
                    }
                    return out
                }
                // Oldest clip's original date (index-aligned array) → the memo's
                // recordedAt seed; the import upgrades to the embedded asset
                // date when one exists (round-1: memos dated to upload time).
                let clipDate = entry.audioRecordedAts?.first.flatMap { ISO8601.date(from: $0) }
                DevLog.log("drain: audio copied=\(temps.count) clip(s) + \(imageTemps.count) photo(s); dates=\(entry.audioRecordedAts ?? []); deleting entry + importing")
                CaptureInbox.delete(entryDir: entryDir)
                // E2: the sheet routed this ≥1h share to the Books tab — import as
                // an audiobook (clips = parts of ONE book). On failure fall through
                // to the memo import: the audio must never be lost.
                if entry.routeToBooks == true {
                    do {
                        let store = AudiobookLibraryStore.shared
                        let pending = try await AudiobookImporter.importBook(
                            from: temps, libraryDirectory: store.directory)
                        store.add(pending.book)
                        DevLog.log("drain: audio entry \(entry.id) → Books ('\(pending.book.title)')")
                        return nil   // a book, not a note — no jump target
                    } catch {
                        DevLog.log("drain: Books route FAILED (\(error)) — importing as memo instead")
                    }
                }
                if let mid = MemoSaver(repository: repository).importAudioClips(from: temps, recordedAt: clipDate) {
                    // B3: bundled photos land under the memo's own id — the manifest
                    // is set BEFORE the transcription result arrives, so the shared
                    // ImageMarkers pass drops [[img_NNN]] into the transcript exactly
                    // like a recorded memo's photos.
                    var savedNames: [String] = []
                    if !imageTemps.isEmpty {
                        let midString = mid.uuidString
                        savedNames = await offMain { () -> [String] in
                            var out: [String] = []
                            for (i, src) in imageTemps.enumerated() {
                                let name = "photo_\(midString)_\(String(format: "%03d", i + 1)).jpg"
                                let dest = AppPaths.recordingsDirectory.appendingPathComponent(name)
                                try? FileManager.default.removeItem(at: dest)
                                if (try? FileManager.default.copyItem(at: src, to: dest)) != nil {
                                    out.append(name)
                                }
                            }
                            return out
                        }
                    }
                    if let memo = repository.memo(id: mid) {
                        if !savedNames.isEmpty {
                            var meta = memo.metadata ?? MemoMetadata()
                            meta.imageManifest = savedNames.map { ImageManifestEntry(filename: $0, offsetSeconds: 0) }
                            memo.metadata = meta
                        }
                        // B3: the bundle's chat text leads the note as the annotation.
                        if let chat = entry.text, !chat.isEmpty { memo.annotationText = chat }
                        // The sheet's significance circles apply to the imported memo.
                        if entry.significance > 0 { memo.significance = entry.significance }
                        repository.save()
                    }
                    return mid
                }
            } else {
                DevLog.log("drain: audio entry \(entry.id) — no clip files, discarding")
                CaptureInbox.delete(entryDir: entryDir)
            }
            return nil
        }

        // Duplicate guard: if we already have this memo, just clean up.
        if repository.memo(id: memoID) != nil {
            CaptureInbox.delete(entryDir: entryDir)
            return nil
        }

        // Build the SharedContent from the inbox entry.
        guard let contentType = ShareContentType(rawValue: entry.type) else {
            // Unknown type — discard the entry rather than leaving it forever.
            CaptureInbox.delete(entryDir: entryDir)
            return nil
        }

        var sharedContent = SharedContent(
            type: contentType,
            url: entry.url,
            urlTitle: entry.urlTitle,
            text: entry.text,
            fileName: entry.imageFileName,
            mimeType: entry.mimeType
        )

        // C5: a URL that points AT a PDF (Safari shares the page URL, not the file) —
        // download it on drain (E4 policy: network in the app, never the extension)
        // and land it as a normal file capture. Detection: `.pdf` extension (fast
        // path), else a HEAD content-type sniff — arxiv-style links are
        // extensionless (`/pdf/2406.19741`, device round 2 2026-07-11). Any
        // failure falls back to the plain link card (the URL is never lost).
        if contentType == .url, let raw = entry.url, let remote = URL(string: raw) {
            let isPDF: Bool
            if remote.pathExtension.lowercased() == "pdf" {
                isPDF = true
            } else if remote.scheme?.hasPrefix("http") == true {
                isPDF = await headSaysPDF(remote)
            } else {
                isPDF = false
            }
            if isPDF {
                let destName = "file_\(memoID.uuidString).pdf"
                if await downloadPDF(from: remote, toRecordingsAs: destName) {
                    sharedContent = SharedContent(type: .file, filePath: destName,
                                                  fileName: remote.lastPathComponent,
                                                  mimeType: "application/pdf")
                    DevLog.log("drain: pdf-url \(entry.id) downloaded → \(destName)")
                } else {
                    DevLog.log("drain: pdf-url \(entry.id) download failed — keeping link card")
                }
            }
        }

        // A1/C4: enrich a link ON DRAIN (one GET, E4 policy): page title /
        // description / a locally-downloaded thumbnail → the rich card, plus the
        // article's readable text → sharedContent.text (searchable, offline; url
        // captures never render that field, so it stays search-side like A6).
        // Skipped when C5 already turned the link into a PDF; Maps links skip via
        // the D6 place match below (the place IS the enrichment).
        if sharedContent.type == .url, let raw = entry.url, let remote = URL(string: raw),
           PlaceLink.parse(raw) == nil,
           let enriched = await LinkEnrichment.enrich(url: remote, memoID: memoID) {
            if sharedContent.urlTitle?.isEmpty != false { sharedContent.urlTitle = enriched.title }
            sharedContent.urlDescription = enriched.descriptionText
            sharedContent.urlThumbnailUrl = enriched.thumbnailFile   // relative recordings name
            if sharedContent.text?.isEmpty != false { sharedContent.text = enriched.articleText }
            DevLog.log("drain: link enriched \(entry.id) title=\(enriched.title != nil) thumb=\(enriched.thumbnailFile != nil) article=\(enriched.articleText?.count ?? 0)ch")
        }

        // D6: an Apple/Google Maps share → a place-anchored note. The parsed name
        // + pin land in the memo's location metadata (the same chip + place-search
        // a recorded memo gets); the link card stays for opening Maps.
        var placeInfo: LocationInfo?
        if contentType == .url, let raw = entry.url, let place = PlaceLink.parse(raw) {
            placeInfo = LocationInfo(latitude: place.latitude, longitude: place.longitude,
                                     placeName: place.name)
            // The place name doubles as the card title when the source app gave none.
            if sharedContent.urlTitle?.isEmpty != false { sharedContent.urlTitle = place.name }
            DevLog.log("drain: maps url \(entry.id) → place '\(place.name ?? "unnamed")'")
        }

        // D4: a shared TEXT file (.md/.txt) becomes the note CONTENT, not a file
        // card — its text lands as the body (below any typed ramble); no document
        // blob is kept. Oversized or non-UTF-8 files stay documents (a novel-length
        // txt isn't a note).
        var textFileBody: String?
        if contentType == .file,
           let displayName = (entry.fileDisplayName ?? entry.fileName)?.lowercased(),
           displayName.hasSuffix(".md") || displayName.hasSuffix(".markdown") || displayName.hasSuffix(".txt"),
           let srcURL = CaptureInbox.fileURL(for: entry, entryDir: entryDir),
           FileManager.default.fileExists(atPath: srcURL.path) {
            let text = await offMain { () -> String? in
                guard let data = try? Data(contentsOf: srcURL), data.count <= 512_000 else { return nil }
                return String(data: data, encoding: .utf8)
            }
            if let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                textFileBody = trimmed
                sharedContent = SharedContent(type: .text,
                                              fileName: entry.fileDisplayName ?? entry.fileName)
                DevLog.log("drain: text file \(entry.id) → note body (\(trimmed.count) chars)")
            }
        }

        // File capture (e.g. a shared PDF): copy the document from the inbox into
        // the recordings dir under the memo UUID so it persists. We store the
        // RELATIVE filename in `filePath` (resolved against recordingsDirectory at
        // open time) so it survives reinstall — same rule as audio/photos.
        if contentType == .file, textFileBody == nil,
           let srcURL = CaptureInbox.fileURL(for: entry, entryDir: entryDir),
           FileManager.default.fileExists(atPath: srcURL.path) {
            let ext = (entry.fileName.map { ($0 as NSString).pathExtension } ?? "")
            let destName = "file_\(memoID.uuidString).\(ext.isEmpty ? "pdf" : ext)"
            let destURL = AppPaths.recordingsDirectory.appendingPathComponent(destName)
            let copied = await offMain { () -> Bool in
                do {
                    try? FileManager.default.removeItem(at: destURL)
                    try FileManager.default.copyItem(at: srcURL, to: destURL)
                    return true
                } catch {
                    print("[CaptureInboxDrainer] file copy failed: \(error)")
                    return false
                }
            }
            if copied {
                sharedContent = SharedContent(type: .file, filePath: destName,
                                              fileName: entry.fileDisplayName, mimeType: entry.mimeType)
            }
        }

        // A6: shared PDFs get their embedded text extracted on drain into
        // sharedContent.text → searchable like doc-scans (which OCR via the photo
        // pipeline). Covers the C5 download too. A scanned (image-only) PDF yields
        // nothing and stays findable by filename. Capped so a book-length PDF
        // doesn't bloat the synced record; nothing renders this text — the .file
        // detail card / inline PDF stays as is.
        if sharedContent.type == .file, let rel = sharedContent.filePath,
           rel.lowercased().hasSuffix(".pdf") {
            let pdfURL = AppPaths.recordingsDirectory.appendingPathComponent(rel)
            let extracted = await offMain { () -> String? in
                guard let doc = PDFDocument(url: pdfURL),
                      let s = doc.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !s.isEmpty else { return nil }
                return String(s.prefix(120_000))
            }
            if let extracted {
                sharedContent.text = extracted
                DevLog.log("drain: pdf text extracted for \(entry.id) (\(extracted.count) chars)")
            }
        }

        // For image captures, move the image(s) from the inbox to the recordings
        // directory under the memo's UUID before saving the Memo — a multi-photo
        // share (B2) always lands as ONE memo with an N-entry manifest. Manifest
        // entries use offsetSeconds 0 (the capture has no timeline).
        var imageManifest: [ImageManifestEntry]?
        if contentType == .image {
            let srcURLs = CaptureInbox.imageURLs(for: entry, entryDir: entryDir)
            let idString = memoID.uuidString
            let savedNames = await offMain { () -> [String] in
                var out: [String] = []
                for (i, srcURL) in srcURLs.enumerated() where FileManager.default.fileExists(atPath: srcURL.path) {
                    // Destination: recordings dir, photo_<memoUUID>_00N.<ext>
                    let ext = srcURL.pathExtension
                    let destName = "photo_\(idString)_\(String(format: "%03d", i + 1)).\(ext.isEmpty ? "jpg" : ext)"
                    let destURL = AppPaths.recordingsDirectory.appendingPathComponent(destName)
                    do {
                        if FileManager.default.fileExists(atPath: destURL.path) {
                            try FileManager.default.removeItem(at: destURL)
                        }
                        try FileManager.default.copyItem(at: srcURL, to: destURL)
                        out.append(destName)
                    } catch {
                        // Image copy failed — save the capture with whatever images
                        // landed rather than abandoning the whole entry.
                        print("[CaptureInboxDrainer] image copy failed: \(error)")
                    }
                }
                return out
            }
            let manifest = savedNames.map { ImageManifestEntry(filename: $0, offsetSeconds: 0) }
            if !manifest.isEmpty { imageManifest = manifest }
        }

        // Dictated voice note: move the audio to the app-owned pending spot
        // BEFORE the entry is deleted (crash between delete and transcription
        // must not lose the recording). The app transcribes it async after the
        // memo is saved; the memo shows .transcribing until the text lands.
        var hasDictation = false
        if let srcURL = CaptureInbox.dictationURL(for: entry, entryDir: entryDir),
           FileManager.default.fileExists(atPath: srcURL.path) {
            let destURL = CaptureDictation.pendingAudioURL(for: memoID)
            hasDictation = await offMain { () -> Bool in
                do {
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.copyItem(at: srcURL, to: destURL)
                    return true
                } catch {
                    // Copy failed — save the capture without the voice note rather
                    // than abandoning the whole entry (same policy as images).
                    print("[CaptureInboxDrainer] dictation copy failed: \(error)")
                    return false
                }
            }
        }

        // Parse the sharedAt timestamp using the app's canonical formatter
        // (fractional-seconds UTC, matching JavaScript Date.toISOString() and the
        // Mac contract). Fall back to now() if the string is malformed.
        // A4: image captures date to the photos' earliest EXIF taken-date when one
        // exists — mirrors video (filming date) and audio (clip date).
        let exifSeed = entry.imageRecordedAts?.compactMap { ISO8601.date(from: $0) }.min()
        let recordedAt = exifSeed ?? ISO8601.date(from: entry.sharedAt) ?? Date()

        // Build MemoMetadata when the capture carries any: an image manifest
        // (image captures) and/or a place (D6 Maps shares).
        var metadata: MemoMetadata?
        if imageManifest != nil || placeInfo != nil {
            var m = MemoMetadata()
            m.imageManifest = imageManifest
            m.location = placeInfo
            metadata = m
        }

        // Photos live IN the text like a recorded memo (round-2 device spec:
        // "look at my Monday 22:34 note — the pictures are in line; just do
        // that"): one [[img_NNN]] marker per photo appended to the annotation;
        // the capture renders through the normal note-body inline pipeline.
        var annotation = entry.annotationText?.isEmpty == false ? entry.annotationText! : ""
        // D4: the text file's content IS the note body, below the typed ramble.
        if let textFileBody {
            annotation = annotation.isEmpty ? textFileBody : annotation + "\n\n" + textFileBody
        }
        if let manifest = imageManifest, !manifest.isEmpty {
            let markers = (1...manifest.count)
                .map { "[[img_\(String(format: "%03d", $0))]]" }
                .joined(separator: "\n\n")
            annotation = annotation.isEmpty ? markers : annotation + "\n\n" + markers
        }

        let memo = Memo.make(
            id: memoID,
            audioFilename: "",          // no audio — the discriminator for capture items
            duration: 0,
            recordedAt: recordedAt,
            tags: [],
            syncStatus: .waiting,
            transcript: nil,
            // No ASR needed for the capture itself; a dictated voice note keeps
            // the memo .transcribing until its text lands (sync waits on .done).
            transcriptStatus: hasDictation ? .transcribing : .done,
            significance: entry.significance,
            metadata: metadata,
            sharedContent: sharedContent,
            annotationText: annotation.isEmpty ? nil : annotation
        )

        repository.insert(memo)
        // Delete only AFTER the insert+save (repository.insert calls save()).
        CaptureInbox.delete(entryDir: entryDir)

        if hasDictation {
            CaptureDictation.transcribe(memoID: memoID, repository: repository)
        }
        return memoID
    }
}
