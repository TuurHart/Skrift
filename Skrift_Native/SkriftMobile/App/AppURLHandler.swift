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
            for url in urls { handle(url) }
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
        for url in urls where !clipSet.contains(url) { handle(url) }
        if choice.combines, clips.count > 1 {
            let staged = await Task.detached(priority: .userInitiated) { stageForMerge(clips) }.value
            if let id = saver.importAudioClips(from: staged.urls, recordedAt: staged.dates.first.flatMap { $0 },
                                               clipDates: staged.dates) {
                MemoOpenBridge.shared.open(id)
                jump = id
            }
        } else {
            for url in clips {
                if let id = saver.importAudio(from: url) { MemoOpenBridge.shared.open(id); jump = id }
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
            guard let raw = try? Data(contentsOf: url), let norm = ImageNormalise.normalise(raw) else { return false }
            let fileName = "capture_\(id.uuidString).\(norm.ext)"
            let taken = ImageDates.exifDate(from: raw).map { ISO8601.string(from: $0) } ?? ""
            let entry = CaptureInboxEntry(
                id: id, type: "image", url: nil, urlTitle: nil, text: nil,
                imageFileName: fileName, mimeType: norm.mime, annotationText: nil,
                significance: 0, sharedAt: sharedAt,
                imageFileNames: [fileName],
                imageRecordedAts: [taken],
                imageOriginalNames: [name],
                imageSelectionPositions: [0])
            wrote = CaptureInbox.write(entry, imageDatas: [norm.data])
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

}
