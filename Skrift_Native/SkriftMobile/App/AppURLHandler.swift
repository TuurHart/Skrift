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

    // MARK: - Several files at once (C68 / C145)

    /// The audio files of a pick that are voice notes (not a `.skriftbook`, not a video).
    nonisolated static func audioClips(in urls: [URL]) -> [URL] {
        urls.filter { $0.isFileURL && !BookBundle.isBookBundle($0) && importKind(of: $0) == .audio }
    }

    /// Files that arrive TOGETHER (the Files importer's pick, an AirDrop / Open-in burst) go
    /// through here: 2+ voice notes raise the One-note / N-notes chooser (`AudioPickBridge`),
    /// anything else is handled file by file exactly as before.
    static func handle(batch urls: [URL]) {
        if AudioImportChoice.needsChoice(clipCount: audioClips(in: urls).count) {
            AudioPickBridge.shared.offer(urls)
        } else {
            var report = ImportReport()
            for url in urls { report.merge(route(url)) }
            ImportReportBridge.shared.post(report)
        }
    }

    // Open-in / AirDrop deliver one `onOpenURL` per file, back to back. Voice notes are held for
    // a beat so a burst of three arrives as ONE pick and meets the same chooser.
    private static var burst: [URL] = []
    private static var burstTask: Task<Void, Never>?
    static let burstWindow: Duration = .milliseconds(700)

    /// The `onOpenURL` door: collect voice notes into a burst; everything else goes straight in.
    static func receive(_ url: URL) {
        guard !audioClips(in: [url]).isEmpty else { handle(url); return }
        burst.append(url)
        burstTask?.cancel()
        burstTask = Task { @MainActor in
            try? await Task.sleep(for: burstWindow)
            guard !Task.isCancelled else { return }
            let urls = burst
            burst = []
            handle(batch: urls)
        }
    }

    /// Carry out the user's answer. `.oneNote` stitches the voice notes (oldest first, by the
    /// ONE bundle order `FilenameDate.chronologicalOrder`) through the shared `AudioClipMerge`
    /// into one transcribed memo; `.separateNotes` imports each. Files that are not voice notes
    /// in the pick are handled as ever. Returns the memo to jump to.
    @discardableResult
    static func resolve(_ urls: [URL], choice: AudioImportChoice, saver: MemoSaver? = nil) async -> UUID? {
        let saver = saver ?? MemoSaver()
        let clips = audioClips(in: urls)
        let clipSet = Set(clips)
        var jump: UUID?
        var report = ImportReport()
        defer { ImportReportBridge.shared.post(report) }
        for url in urls where !clipSet.contains(url) { report.merge(route(url)) }
        if choice.combines, clips.count > 1 {
            let staged = await Task.detached(priority: .userInitiated) { stageForMerge(clips) }.value
            if let id = saver.importAudioClips(from: staged.urls, recordedAt: staged.dates.first.flatMap { $0 },
                                               clipDates: staged.dates) {
                MemoOpenBridge.shared.open(id)
                jump = id
                report.created += 1
            } else {
                for url in clips { report.addFailed(url.lastPathComponent, ImportReport.unreadable) }
            }
        } else {
            for url in clips {
                if let id = saver.importAudio(from: url) {
                    MemoOpenBridge.shared.open(id); jump = id; report.created += 1
                } else {
                    report.addFailed(url.lastPathComponent, ImportReport.unreadable)
                }
            }
        }
        return jump
    }

    /// Copy the picks into app-owned temps (the merge deletes its sources, and a Files pick is
    /// the user's own file) in `chronologicalOrder`. Dates are read from the originals through
    /// the C70 ladder first.
    nonisolated static func stageForMerge(_ clips: [URL]) -> (urls: [URL], dates: [Date?]) {
        let scoped = clips.map { $0.startAccessingSecurityScopedResource() }
        defer { for (u, s) in zip(clips, scoped) where s { u.stopAccessingSecurityScopedResource() } }
        let dates = clips.map { FilenameDate.ladder(embedded: nil, fileAt: $0) }
        let run = UUID().uuidString
        var urls: [URL] = [], outDates: [Date?] = []
        for i in FilenameDate.chronologicalOrder(dates) {
            let src = clips[i]
            let ext = src.pathExtension.isEmpty ? "m4a" : src.pathExtension
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("files_import_\(run)_\(i).\(ext)")
            try? FileManager.default.removeItem(at: temp)
            if (try? FileManager.default.copyItem(at: src, to: temp)) != nil {
                urls.append(temp); outDates.append(dates[i])
            }
        }
        return (urls, outDates)
    }

    /// One incoming URL. What it did is posted to the list banner (`ImportReportBridge`).
    static func handle(_ url: URL) {
        ImportReportBridge.shared.post(route(url))
    }

    /// Carry out one URL and say what happened (C199, Q137): a file Skrift does not take, or
    /// one that could not be read, comes back as skipped / failed with the reason instead of
    /// vanishing. Deep links and book bundles are not notes, so they report nothing.
    private static func route(_ url: URL) -> ImportReport {
        var report = ImportReport()
        let name = url.lastPathComponent
        if url.isFileURL {
            // 📦 A book someone shared (AirDrop / Files / Messages). Checked FIRST:
            // a `.skriftbook` is a zip, and letting the audio branch below reason
            // about it would import the archive as a memo. Nothing lands in the
            // library here — the bridge shows the sheet and the user decides.
            if BookBundle.isBookBundle(url) {
                BookImportBridge.shared.offer(url)
                return report
            }
            // Land the user on the imported memo (A9): it relocates to the media's
            // embedded date, so without the jump it "vanishes" down the list — the
            // same rule the share-sheet drain path already follows.
            switch importKind(of: url) {
            case .video:
                // A video container (.mov/.mp4/…): strip the audio + grab a frame.
                // (A video the system cannot read, or one with no audio, still becomes a
                // visible FAILED note - C202 - so it counts as made here.)
                if let id = MemoSaver().importVideo(from: url) {
                    MemoOpenBridge.shared.open(id)
                    report.created += 1
                } else {
                    report.addFailed(name, ImportReport.unreadable)
                }
            case .audio:
                if let id = MemoSaver().importAudio(from: url) {
                    MemoOpenBridge.shared.open(id)
                    report.created += 1
                } else {
                    report.addFailed(name, ImportReport.unreadable)
                }
            case .image, .text, .document:
                if importAsCapture(url) { report.created += 1 }
                else { report.addFailed(name, ImportReport.unreadable) }
            case .book:
                // Books have their own door (the Books library): said, not dropped.
                report.addSkipped(name, ImportReport.book)
            case .none:
                report.addSkipped(name, ImportReport.skipReason(forName: name, onMac: false))
            }
            return report
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
        return report
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
