import Foundation
import SwiftData
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import os

/// Desktop-side ingest for locally-picked files/folders (the +Upload button and
/// drag-drop). Mirrors `UploadService`'s on-disk layout — one `<id>_<filename>/`
/// folder per note with `original.<ext>` — so desktop and phone ingest produce
/// identical PipelineFiles. Pure (FileManager + ModelContext, no engines) so it
/// unit-tests host-less.
struct IngestService: Sendable {
    var outputDir: URL = AppPaths.audioOutputDirectory

    /// These files were RECORDED on this Mac, not imported — stamped onto every row this
    /// service creates.
    ///
    /// It has to be set HERE, at construction, and not by the caller afterwards. The reconcile
    /// sweep fetches local rows on its own schedule and authors a Memo for any that lack one,
    /// authoring it unrated (D159); inserted-but-unsaved rows are already visible to that
    /// fetch, and this function awaits detached file work, so the sweep genuinely does reach a
    /// new row mid-ingest. Stamping after `ingest` returns loses that race — measured, twice,
    /// on real takes (2026-07-28).
    var isLocalRecording: Bool = false

    private static let log = Logger(subsystem: "com.skrift.desktop", category: "ingest")

    /// The kind a file URL resolves to - the one the phone's `AppURLHandler.importKind(of:)`
    /// returns for the same name (`ImportKindsTests`, both targets). C238: one list.
    static func importKind(of url: URL) -> ImportKinds.Kind? { ImportKinds.kind(of: url) }

    static let supportedAudio: Set<String> = ImportKinds.audioExtensions.union(["mp4", "mov"])

    /// Video containers we accept: strip the audio track to an `original.m4a` and feed
    /// the normal audio pipeline (e.g. a self-recorded "life advice" clip). Note
    /// `mp4`/`mov` ALSO appear in `supportedAudio` — those container extensions are
    /// probed for a video track first (`ingestFile`) and only fall back to plain audio
    /// when audio-only, so an audio-only `.mp4`/`.m4a-in-mov` is never mis-extracted.
    static let supportedVideo: Set<String> = ImportKinds.videoExtensions

    /// ASYNC: heavy file work (copies, container probes, the video-audio export)
    /// runs on detached tasks; only the SwiftData inserts run on the caller's
    /// (main) actor. The old fully-synchronous form froze the UI for the whole
    /// video export when invoked from drag-drop / open-panel handlers.
    ///
    /// What an ingest did with a drop: the rows it made, and every file it could NOT turn into a
    /// note (unsupported type, vanished before the copy, a picture that would not copy). A file
    /// is in exactly one of the two, or is the inside of a folder / bundle that was consumed -
    /// never in neither (Q92: a picture dropped with five clips used to disappear without a
    /// row or a message).
    struct IngestReport {
        var created: [PipelineFile] = []
        var skipped: [URL] = []
        /// Ids of the rows that are N clips stitched into one (C124). Their date is the first
        /// clip's message time, never the stitched file's own embedded date.
        var merged: Set<String> = []
        /// Why a skipped file was skipped, when the default (by its kind) is not the whole
        /// story: a picture or a `.txt` found INSIDE a dropped folder is a supported type, and
        /// saying "unsupported" would lie.
        var reasons: [URL: String] = [:]
        /// Rows made for a file that was taken but could not be imported (a video with no audio
        /// track): they are in `created` too, as failed notes the list shows.
        var failed: [ImportReport.Problem] = []

        /// The one report both apps show (C199 / C202): `created` counts only the rows that
        /// are not failures.
        var importReport: ImportReport {
            var r = ImportReport(created: created.count - failed.count)
            for url in skipped {
                r.addSkipped(url.lastPathComponent,
                             reasons[url] ?? (FileManager.default.fileExists(atPath: url.path)
                                ? ImportReport.skipReason(forName: url.lastPathComponent, onMac: true)
                                : ImportReport.vanished))
            }
            r.failed = failed
            return r
        }

        /// Add a row an ingest made; a failed-import row (`IngestService.isFailedImport`) is
        /// recorded as a failure too.
        mutating func add(_ pf: PipelineFile) {
            created.append(pf)
            if IngestService.isFailedImport(pf) {
                failed.append(.init(name: pf.filename, reason: pf.enhancedTitle ?? ImportReport.noAudioTrack))
            }
        }
    }

    /// `combineAudio` is the answer to the C68 chooser ("One note"): when true and TWO OR
    /// MORE plain-audio clips arrive together, they are stitched in FILENAME-TIME order (C70,
    /// chat order; the given order when a name carries no date) into ONE `original.m4a` by the
    /// phone's own `AudioClipMerge`, so the pipeline sees one row and runs ONE transcription
    /// pass. The merged note takes the slot of the first clip; anything else in the same drop (a
    /// markdown note, a video, a folder) is ingested as before. The default is `false`, so
    /// callers that never ask (the `-runfile` harness) keep today's one-row-per-file behaviour.
    ///
    /// PICTURES (C68, C12): a mixed bundle is ONE note. With the clips merged, or with exactly
    /// one clip (nothing to ask), every picture rides along as an `images/img_NNN` + manifest
    /// entry at the moment its filename time sits in the clip sequence, so the transcript pass
    /// writes it as its own paragraph there. With "N notes" (several clips, not combined) or no
    /// clip at all, the pictures become ONE note of their own (C68: N photos, one note). The
    /// ordering and placement are `MixedBundle`'s, shared with the phone.
    @discardableResult
    func ingest(localURLs: [URL], combineAudio: Bool = false, into context: ModelContext) async throws -> [PipelineFile] {
        let report = try await ingestReport(localURLs: localURLs, combineAudio: combineAudio, into: context)
        for url in report.skipped {
            Self.log.error("not imported: \(url.lastPathComponent, privacy: .public)")
        }
        return report.created
    }

    /// `ingest`, plus the files that did not become a note (see `IngestReport`).
    func ingestReport(localURLs: [URL], combineAudio: Bool = false, into context: ModelContext) async throws -> IngestReport {
        var report = IngestReport()
        let clips = Self.audioClips(in: localURLs)
        let pictures = localURLs.filter { Self.isPicture($0) }
        let clipSet = Set(clips.map(\.standardizedFileURL))
        let pictureSet = Set(pictures.map(\.standardizedFileURL))
        let merging = combineAudio && clips.count >= 2
        let bundling = !pictures.isEmpty && !clips.isEmpty && (merging || clips.count == 1)

        // Order + place BEFORE any row exists, from the drop's own order and filename times.
        var composition: MixedBundle.Composition?
        if merging || bundling {
            let items: [MixedBundle.Item] = localURLs.compactMap { url in
                let key = url.standardizedFileURL
                if clipSet.contains(key) {
                    return .init(url: url, kind: .clip, date: Self.importDate(of: url, kind: .clip))
                }
                if bundling, pictureSet.contains(key) {
                    return .init(url: url, kind: .picture, date: Self.importDate(of: url, kind: .picture))
                }
                return nil
            }
            var durations: [URL: Double] = [:]
            if bundling {
                durations = try await Self.offMain {
                    Dictionary(clips.map { ($0, Self.audioSeconds(of: $0)) }, uniquingKeysWith: { a, _ in a })
                }
            }
            composition = MixedBundle.compose(items) { durations[$0] ?? 0 }
        }

        var bundleDone = false, pictureNoteDone = false
        for url in localURLs {
            let key = url.standardizedFileURL
            if let composition, clipSet.contains(key) {
                guard !bundleDone else { continue }
                bundleDone = true
                let pf = try await ingestClips(composition.clips, into: context)
                if composition.clips.count > 1 { report.merged.insert(pf.id) }
                report.skipped += try await attachPictures(composition.pictures, to: pf)
                report.add(pf)
                continue
            }
            if pictureSet.contains(key) {
                if bundling { continue }          // consumed by the bundle above
                guard !pictureNoteDone else { continue }
                pictureNoteDone = true
                let (pf, failed) = try await ingestPictureNote(pictures, into: context)
                report.skipped += failed
                if let pf { report.add(pf) }
                continue
            }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
                report.skipped.append(url); continue
            }
            if isDir.boolValue {
                let folder = try await ingestFolder(url, into: context)
                for pf in folder.created { report.add(pf) }
                report.skipped += folder.skipped.map(\.url)
                for (u, why) in folder.skipped { report.reasons[u] = why }
            } else if let pf = try await ingestFile(url, into: context) {
                report.add(pf)
            } else {
                report.skipped.append(url)
            }
        }
        try context.save()
        return report
    }

    /// The clips as ONE note: a lone clip is copied as it is; several are stitched in order.
    private func ingestClips(_ clips: [URL], into context: ModelContext) async throws -> PipelineFile {
        clips.count == 1 ? try await ingestAudio(clips[0], into: context)
                         : try await ingestMergedAudio(clips, into: context)
    }

    static func audioSeconds(of url: URL) -> Double {
        guard let f = try? AVAudioFile(forReading: url), f.fileFormat.sampleRate > 0 else { return 0 }
        return Double(f.length) / f.fileFormat.sampleRate
    }

    static func isPicture(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return false }
        return MixedBundle.isPictureName(url)
    }

    /// Write `placements` into `folder/images/img_NNN.<ext>` + `image_manifest.json` (the shape
    /// phone uploads and video ingest write, so `[[img_NNN]]` markers land at the transcript pass
    /// and the exporter embeds the files). Returns the pictures that could not be copied;
    /// numbering counts only the ones that were, so a marker always has its file.
    private func writePictures(_ placements: [MixedBundle.Placement], into folder: URL) async throws -> [URL] {
        guard !placements.isEmpty else { return [] }
        return try await Self.offMain { () -> [URL] in
            let fm = FileManager.default
            let dir = folder.appendingPathComponent("images", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            var entries: [ImageManifestEntry] = []
            var failed: [URL] = []
            for p in placements {
                let n = entries.count + 1
                // C74 / D17 (Q135): the shared normaliser — PNG stays PNG, GIF kept byte-for-byte,
                // longest side <= 2048, HEIC/TIFF/BMP -> JPEG 0.9. Undecodable -> copied as-is.
                let name: String
                var ok = false
                if let norm = ImageNormalise.normalise(fileAt: p.url) {
                    name = String(format: "img_%03d.", n) + norm.ext
                    ok = (try? norm.data.write(to: dir.appendingPathComponent(name))) != nil
                } else {
                    // Undecodable: a format we convert (HEIC/TIFF/BMP) is a failure, as before;
                    // any other extension is copied as-is.
                    let ext = p.url.pathExtension.lowercased()
                    name = String(format: "img_%03d.", n) + (ext == "jpeg" ? "jpg" : ext)
                    if !MixedBundle.convertToJPEGExtensions.contains(ext) {
                        ok = (try? fm.copyItem(at: p.url, to: dir.appendingPathComponent(name))) != nil
                    }
                }
                if ok { entries.append(ImageManifestEntry(filename: name, offsetSeconds: p.offsetSeconds)) }
                else { failed.append(p.url) }
            }
            if !entries.isEmpty {
                let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
                try enc.encode(entries).write(to: folder.appendingPathComponent("image_manifest.json"))
            }
            return failed
        }
    }

    /// A bundle's pictures go in the audio note's own working folder (next to `original.m4a`).
    private func attachPictures(_ placements: [MixedBundle.Placement], to pf: PipelineFile) async throws -> [URL] {
        guard !placements.isEmpty else { return [] }
        return try await writePictures(placements, into: URL(fileURLWithPath: pf.path).deletingLastPathComponent())
    }

    /// Pictures with no clip to ride on become ONE note whose body is one picture paragraph each
    /// (C68, C12/C13). A capture-shaped working folder, like a phone image share; the body is
    /// already text, so there is nothing to transcribe.
    private func ingestPictureNote(_ pictures: [URL], into context: ModelContext) async throws -> (PipelineFile?, [URL]) {
        let ordered = MixedBundle.ordered(pictures.map {
            MixedBundle.Item(url: $0, kind: .picture, date: Self.importDate(of: $0, kind: .picture))
        })
        let id = UUID().uuidString
        let folderName = "capture_\(id)"
        let folder = outputDir.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let failed = try await writePictures(ordered.map { MixedBundle.Placement(url: $0.url, offsetSeconds: 0) },
                                             into: folder)
        let written = ordered.count - failed.count
        guard written > 0 else {
            try? FileManager.default.removeItem(at: folder)
            return (nil, failed)
        }
        // C74: the earliest picture's ladder date (EXIF → filename → file date), else now.
        let recorded = ordered.compactMap(\.date).min() ?? Date()
        let pf = PipelineFile(id: id, filename: folderName, path: folder.path, size: 0, sourceType: .capture,
                              uploadedAt: recorded)
        pf.transcript = MixedBundle.pictureOnlyBody(count: written)
        pf.transcribeStatus = .done
        pf.isLocalRecording = isLocalRecording
        pf.isLocalImport = !isLocalRecording
        context.insert(pf)
        return (pf, failed)
    }

    /// The plain-audio clips among `urls`, in the given order: real files with an audio
    /// extension, minus containers that actually carry a video track (those are C68 "video"
    /// and follow the video path). Folders and notes are not voice notes.
    static func audioClips(in urls: [URL]) -> [URL] {
        urls.filter { isAudioClip($0) }
    }

    static func isAudioClip(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return false }
        let ext = url.pathExtension.lowercased()
        guard supportedAudio.contains(ext) else { return false }
        if supportedVideo.contains(ext), hasVideoTrack(url) { return false }
        return true
    }

    /// N clips → ONE audio PipelineFile: merged in order to `original.m4a`, named and dated
    /// from the FIRST clip (the date ladder is C70's, same as a single import).
    private func ingestMergedAudio(_ clips: [URL], into context: ModelContext) async throws -> PipelineFile {
        let first = clips[0]
        let filename = first.lastPathComponent
        let id = UUID().uuidString
        let (folder, _) = try makeFolder(id: id, filename: filename)
        let dest = folder.appendingPathComponent("original.m4a")
        do {
            try await Self.offMain {
                try AudioClipMerge.merge(sources: clips, to: dest) { Self.log.error("\($0, privacy: .public)") }
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)   // no half-made working folder
            throw error
        }
        let size = ((try? FileManager.default.attributesOfItem(atPath: dest.path))?[.size] as? Int) ?? 0
        // Q134 / C124: the FIRST clip's own bundle date (its name, then its file date) — the same
        // value it was ordered by and that its manifest entry carries. No embedded date: the
        // stitched file's is the stitch moment (ArrivalPath never backfills a merged row), and the
        // phone's `importAudioClipsAsync` no longer lets the first clip's override it either.
        let recorded = Self.importDate(of: first, kind: .clip) ?? Date()
        // C124 / D35: each clip's start in the merged audio + its own message time, kept beside
        // the audio. The transcript pass turns the starts into paragraph breaks; the times are
        // never shown in the body.
        try await writeClipManifest(clips, into: folder)
        let pf = PipelineFile(id: id, filename: filename, path: dest.path, size: size,
                              sourceType: .audio, uploadedAt: recorded)
        pf.isLocalRecording = isLocalRecording
        pf.isLocalImport = !isLocalRecording
        context.insert(pf)
        return pf
    }

    static let clipManifestName = "clip_manifest.json"

    private func writeClipManifest(_ clips: [URL], into folder: URL) async throws {
        try await Self.offMain {
            let manifest = MixedBundle.clipManifest(
                clips: clips, dates: { Self.importDate(of: $0, kind: .clip) },
                clipDuration: { Self.audioSeconds(of: $0) })
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
            try enc.encode(manifest).write(to: folder.appendingPathComponent(Self.clipManifestName))
        }
    }

    /// The paragraph-break moments of a merged note, from its `clip_manifest.json` (empty for
    /// anything that is not one).
    static func clipStarts(forAudioAt path: String) -> [Double] {
        guard !path.isEmpty else { return [] }
        let url = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent(clipManifestName)
        guard let data = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode([MixedBundle.ClipEntry].self, from: data) else { return [] }
        return MixedBundle.breakStarts(m)
    }

    /// Run throwing file work on a detached task so a slow copy never parks the
    /// caller's actor.
    private static func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try work() }.value
    }

    /// A single file → one PipelineFile (audio, video, or Apple-Note markdown).
    /// Unsupported types are skipped (returns nil). A video container is probed for
    /// an actual video track: if present, its audio is extracted; if absent (an
    /// audio-only `.mp4`/`.mov`), it's ingested as plain audio.
    func ingestFile(_ url: URL, into context: ModelContext) async throws -> PipelineFile? {
        let ext = url.pathExtension.lowercased()
        if Self.supportedVideo.contains(ext),
           await Task.detached(operation: { Self.hasVideoTrack(url) }).value {
            do { return try await ingestVideo(url, into: context) }
            catch VideoIngestError.noAudioTrack {
                // C202: a silent video is a visible failed note, like the phone's.
                return try await ingestFailedVideo(url, title: ImportReport.noAudioTrack, into: context)
            }
        }
        // C238: dispatch on the ONE shared kind. A `.video` that carried no video track gets
        // here as an audio-only container (`supportedAudio` holds mp4/mov for exactly that).
        switch ImportKinds.kind(forExtension: ext) {
        case .audio, .video:
            return Self.supportedAudio.contains(ext) ? try await ingestAudio(url, into: context) : nil
        case .text: return try await ingestNote(url, into: context)
        // Pictures are bundled before this point; a PDF / book has no Mac ingest yet (the
        // drop reports it as skipped, never silently).
        case .image, .document, .book, .none: return nil
        }
    }

    private func ingestAudio(_ url: URL, into context: ModelContext) async throws -> PipelineFile {
        let filename = url.lastPathComponent
        let id = UUID().uuidString
        let (folder, _) = try makeFolder(id: id, filename: filename)
        var ext = url.pathExtension
        if ext.isEmpty { ext = "m4a" }
        let dest = folder.appendingPathComponent("original.\(ext)")
        let size = try await Self.offMain {
            try FileManager.default.copyItem(at: url, to: dest)
            return ((try? FileManager.default.attributesOfItem(atPath: dest.path))?[.size] as? Int) ?? 0
        }
        // Baseline date: a date in the filename (WhatsApp/Signal/recorder names),
        // else the source file's creation date (right for fresh memos), else now. The
        // app then backfills the EMBEDDED recording date (AudioMetadata) when present,
        // which is correct even for copied/ported Apple recordings.
        let recorded = FilenameDate.ladder(embedded: nil, fileAt: url) ?? Date()
        let pf = PipelineFile(id: id, filename: filename, path: dest.path, size: size,
                              sourceType: .audio, uploadedAt: recorded)
        pf.isLocalRecording = isLocalRecording
        pf.isLocalImport = !isLocalRecording
        context.insert(pf)
        return pf
    }

    /// A video file → strip its audio track to `original.m4a` and produce a `.audio`
    /// PipelineFile so the rest of the pipeline (transcribe/enhance/export) is
    /// unchanged. The recording date comes from the VIDEO's embedded creation date
    /// (survives the copy) or a date in the filename, NOT the import time. The movie
    /// itself is kept in the working folder as `source.<ext>` (local disk only, never a
    /// `MemoAsset`), for the portfolio export.
    private func ingestVideo(_ url: URL, into context: ModelContext) async throws -> PipelineFile {
        let filename = url.lastPathComponent
        let id = UUID().uuidString
        let (folder, _) = try makeFolder(id: id, filename: filename)
        let dest = folder.appendingPathComponent("original.m4a")

        try await Self.extractAudio(from: url, to: dest)

        // KEEP THE MOVIE (2026-08-28). Until now the source video was consumed for its audio,
        // its first frame and its date, then dropped — on the Mac and the phone both. Tuur:
        // *"I may send a video about a project to a friend… I speak very animated, that is
        // gold… I wanna be able to put that in my portfolio vault but with transcription, so
        // Claude can take parts from it for my website."* You cannot pull a snippet from a
        // file nobody kept.
        //
        // It lives in the WORKING FOLDER beside `original.m4a`, which is local disk — NOT a
        // `MemoAsset`, so it never enters SwiftData or CloudKit and never syncs. That is the
        // line Tuur drew when he cut video storage ("no dont store videos, just skip them"):
        // the objection was hundreds of MB per clip in his iCloud account, not a file on the
        // machine that already has it. Only the PORTFOLIO export copies it out; the vault
        // never sees it.
        let sourceExt = url.pathExtension.isEmpty ? "mov" : url.pathExtension
        let kept = folder.appendingPathComponent("source." + sourceExt)
        do {
            try await Self.offMain { try FileManager.default.copyItem(at: url, to: kept) }
        } catch {
            // A missing movie costs a snippet, never the note — the audio is already extracted.
            Self.log.error("keeping the source video failed for \(filename, privacy: .public): \(String(describing: error), privacy: .public)")
        }
        let size = ((try? FileManager.default.attributesOfItem(atPath: dest.path))?[.size] as? Int) ?? 0

        // One representative frame → `images/img_001.jpg` + `image_manifest.json`
        // (offsetSeconds 0) — the same on-disk shape phone uploads write — so the
        // existing `[[img_001]]` marker pipeline shows the frame in review and
        // exports it. Mirrors the phone's video import (`MemoSaver.processVideo`).
        // A failed grab never fails the ingest (the audio is the point) but is logged.
        do {
            try await Self.offMain { try Self.writeVideoThumbnail(from: url, into: folder) }
        } catch {
            Self.log.error("video thumbnail failed for \(filename, privacy: .public): \(String(describing: error), privacy: .public)")
        }

        // Embedded recording date from the ORIGINAL video (the extracted m4a may lose
        // it), then a filename date, then the file's creation date, then now.
        let embedded = await Task.detached(operation: { Self.embeddedRecordingDate(of: url) }).value
        let recorded = FilenameDate.ladder(embedded: embedded, fileAt: url) ?? Date()

        // sourceType .audio: it's now an audio file. Keep the original (video) filename
        // so the title isn't "original" and it's recognizable in the queue.
        let pf = PipelineFile(id: id, filename: filename, path: dest.path, size: size,
                              sourceType: .audio, uploadedAt: recorded)
        pf.mediaSource = "video"   // unified source taxonomy → video glyph + label
        pf.isLocalRecording = isLocalRecording
        pf.isLocalImport = !isLocalRecording
        context.insert(pf)
        return pf
    }

    /// A video that cannot be imported (no audio track) still gets a row: a failed note named
    /// for what went wrong, glyph "video", no audio and no words - the phone's
    /// `MemoSaver.processVideo` failure shape (C202, "Video had no audio track", identical).
    /// A `.note` row, so nothing downstream tries to read audio it does not have.
    private func ingestFailedVideo(_ url: URL, title: String, into context: ModelContext) async throws -> PipelineFile {
        let filename = url.lastPathComponent
        let id = UUID().uuidString
        let (folder, _) = try makeFolder(id: id, filename: filename)
        let embedded = await Task.detached(operation: { Self.embeddedRecordingDate(of: url) }).value
        let recorded = FilenameDate.ladder(embedded: embedded, fileAt: url) ?? Date()
        let pf = PipelineFile(id: id, filename: filename, path: folder.appendingPathComponent("original.md").path,
                              size: 0, sourceType: .note, uploadedAt: recorded)
        pf.mediaSource = "video"
        pf.transcribeStatus = .error
        pf.enhancedTitle = title
        pf.isLocalRecording = isLocalRecording
        pf.isLocalImport = !isLocalRecording
        context.insert(pf)
        return pf
    }

    /// A row `ingestFailedVideo` made.
    static func isFailedImport(_ pf: PipelineFile) -> Bool {
        pf.sourceType == .note && pf.mediaSource == "video" && pf.transcribeStatus == .error
    }

    private func ingestNote(_ url: URL, into context: ModelContext) async throws -> PipelineFile {
        let filename = url.lastPathComponent
        let id = UUID().uuidString
        let (folder, _) = try makeFolder(id: id, filename: filename)
        let dest = folder.appendingPathComponent("original.md")
        // Whole file phase off-main: copy + attachment import (HEIC conversion
        // included) + rewritten-markdown persist. Mirrors
        // apple_notes_importer.parse_markdown_note, but COPIES (never mutates the
        // user's source export).
        let (content, title) = try await Self.offMain { () -> (String, String) in
            try FileManager.default.copyItem(at: url, to: dest)
            var content = (try? String(contentsOf: dest, encoding: .utf8)) ?? ""
            // Title from the first `# ` heading, else the filename stem (apple_notes_importer.py).
            let title = Self.appleNoteTitle(content, fallback: (filename as NSString).deletingPathExtension)
            content = Self.importAttachments(
                content: content,
                from: url.deletingLastPathComponent().appendingPathComponent("Attachments", isDirectory: true),
                into: folder.appendingPathComponent("Attachments", isDirectory: true),
                safeTitle: Self.sanitizeTitle(title)
            )
            try? Data(content.utf8).write(to: dest)
            return (content, title)
        }

        let pf = PipelineFile(id: id, filename: filename, path: dest.path,
                              size: content.utf8.count, sourceType: .note)
        // Apple notes arrive already "transcribed" — the markdown body is the text.
        // Body v2 (C10/C19): committed once, here, at the Mac text import.
        pf.transcript = BodyV2.committed(BodyV2.Input(text: content, source: .typed))
        pf.transcribeStatus = .done
        // BatchRunner won't clobber this; the LLM title becomes the suggestion.
        pf.enhancedTitle = title
        // Q241 (4): like every other Mac import (D159) it arrives UNRATED. An inserted row with
        // neither flag reads as a legacy RATED row (`NoteConsent.isRated`).
        pf.isLocalRecording = isLocalRecording
        pf.isLocalImport = !isLocalRecording
        context.insert(pf)
        return pf
    }

    /// Filename date (C70) — the ONE ladder lives in `Shared/Pipeline/FilenameDate.swift`.
    static func dateFromFilename(_ name: String) -> Date? { FilenameDate.date(from: name) }

    /// One bundle item's C70 date, the phone's `CaptureInboxDrainer.sharePlan` rungs exactly
    /// (Q134): a clip by its name, then its file date (its embedded date only dates the NOTE,
    /// below); a picture by EXIF, then its name, then its file date (C74).
    static func importDate(of url: URL, kind: MixedBundle.Kind) -> Date? {
        switch kind {
        case .clip: return FilenameDate.ladder(embedded: nil, fileAt: url)
        case .picture: return ImageDates.ladderDate(at: url)
        }
    }

    // MARK: - Video helpers (synchronous AVFoundation — host-less testable)

    /// True when the file has at least one video track (so a `.mp4`/`.mov` that's
    /// actually audio-only falls through to plain-audio ingest). Uses the synchronous
    /// `tracks(withMediaType:)` accessor — fine off the main thread (ingest runs from
    /// a background-friendly path) and avoids making the ingest API async.
    static func hasVideoTrack(_ url: URL) -> Bool {
        let asset = AVURLAsset(url: url)
        return !asset.tracks(withMediaType: .video).isEmpty
    }

    enum VideoIngestError: Error, Equatable { case noAudioTrack, exportFailed, thumbnailFailed }

    /// Strip `source`'s audio track into a standalone `.m4a` at `dest`. Throws
    /// `noAudioTrack` for a silent clip and `exportFailed` on an export error.
    /// Everything — the container parse AND the export — runs inside one
    /// detached task; the old sync form parked the CALLING thread on a
    /// semaphore for the whole export, a beachball when that thread was main.
    static func extractAudio(from source: URL, to dest: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: source)
            guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
                throw VideoIngestError.noAudioTrack
            }
            let comp = AVMutableComposition()
            guard let track = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw VideoIngestError.exportFailed
            }
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: audioTrack, at: .zero)

            guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetAppleM4A) else {
                throw VideoIngestError.exportFailed
            }
            try? FileManager.default.removeItem(at: dest)
            do { try await export.export(to: dest, as: .m4a) }
            catch { throw VideoIngestError.exportFailed }
            guard FileManager.default.fileExists(atPath: dest.path) else {
                throw VideoIngestError.exportFailed
            }
        }.value
    }

    /// SYNC variant for OFF-MAIN callers only (UploadService's prepare phase) —
    /// the semaphore parks the calling thread for the whole export, which is the
    /// exact beachball the async `extractAudio` exists to avoid on main.
    static func extractAudioSync(from source: URL, to dest: URL) throws {
        let asset = AVURLAsset(url: source)
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            throw VideoIngestError.noAudioTrack
        }
        let comp = AVMutableComposition()
        guard let track = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoIngestError.exportFailed
        }
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: audioTrack, at: .zero)
        guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetAppleM4A) else {
            throw VideoIngestError.exportFailed
        }
        try? FileManager.default.removeItem(at: dest)
        export.outputURL = dest
        export.outputFileType = .m4a
        let semaphore = DispatchSemaphore(value: 0)
        export.exportAsynchronously { semaphore.signal() }
        semaphore.wait()
        guard export.status == .completed,
              FileManager.default.fileExists(atPath: dest.path) else {
            throw VideoIngestError.exportFailed
        }
    }

    /// Grab one representative frame (~1s in, or the midpoint for very short clips —
    /// avoids a black opening frame; same pick as the phone's `representativeFrame`)
    /// and write it as `images/img_001.jpg` plus a phone-shaped
    /// `image_manifest.json` entry at offset 0, so the `[[img_001]]` marker pipeline
    /// (insert at transcription, thumbnail in review, embed on export) just works.
    static func writeVideoThumbnail(from source: URL, into folder: URL) throws {
        let asset = AVURLAsset(url: source)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        let duration = CMTimeGetSeconds(asset.duration)
        let at = CMTime(seconds: min(1.0, max(0, duration / 2)), preferredTimescale: 600)
        let frame = try generator.copyCGImage(at: at, actualTime: nil)

        let imagesDir = folder.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let name = "img_001.jpg"
        let dest = imagesDir.appendingPathComponent(name)
        guard let sink = CGImageDestinationCreateWithURL(dest as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw VideoIngestError.thumbnailFailed
        }
        CGImageDestinationAddImage(sink, frame, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(sink) else { throw VideoIngestError.thumbnailFailed }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try encoder.encode([ImageManifestEntry(filename: name, offsetSeconds: 0)])
            .write(to: folder.appendingPathComponent("image_manifest.json"))
    }

    /// The video's embedded RECORDING date (QuickTime `creationDate` / mp4
    /// `creation_time`) read synchronously. Survives copies — unlike the filesystem
    /// date, which becomes the import/copy time. nil when absent/unparseable.
    static func embeddedRecordingDate(of url: URL) -> Date? {
        let asset = AVURLAsset(url: url)
        guard let item = asset.creationDate else { return nil }
        if let d = item.dateValue { return d }
        if let s = item.stringValue, let d = parseISODate(s) { return d }
        return nil
    }

    /// Parse an ISO-8601 creation-date string (with or without fractional seconds).
    static func parseISODate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }

    /// Filename-safe title: illegal chars → "-", whitespace collapsed, edges trimmed.
    /// Mirrors `apple_notes_importer`'s `safe_title`.
    static func sanitizeTitle(_ title: String) -> String {
        let illegal = Set("\\/:*?\"<>|")
        let replaced = String(title.map { illegal.contains($0) ? "-" : $0 })
        let collapsed = replaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        return trimmed.isEmpty ? "note" : trimmed
    }

    /// Copy each file in `srcDir` into `destDir` renamed "<safeTitle> - <i>.<ext>"
    /// (HEIC/HEIF → JPG via ImageIO), then rewrite the markdown `(Attachments/<orig>)`
    /// refs (plain + URL-encoded) to the new names. Returns the rewritten content;
    /// a no-op (returns `content`) when there's no Attachments dir. Copies — never
    /// mutates the source export.
    static func importAttachments(content: String, from srcDir: URL, into destDir: URL, safeTitle: String) -> String {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: srcDir.path, isDirectory: &isDir), isDir.boolValue else { return content }
        let files = ((try? fm.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { return content }
        try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        var updated = content
        for (i, src) in files.enumerated() {
            let ext = src.pathExtension.lowercased()
            let isHEIC = (ext == "heic" || ext == "heif")
            var outExt = (isHEIC ? "jpg" : ext)
            if outExt.isEmpty { outExt = "bin" }
            var newName = "\(safeTitle) - \(i + 1).\(outExt)"
            var dest = destDir.appendingPathComponent(newName)

            var ok = false
            if isHEIC {
                try? fm.removeItem(at: dest)
                ok = convertToJPEG(src: src, dst: dest)
                if !ok {   // conversion failed — keep the original file + ext
                    outExt = ext.isEmpty ? "bin" : ext
                    newName = "\(safeTitle) - \(i + 1).\(outExt)"
                    dest = destDir.appendingPathComponent(newName)
                }
            }
            if !ok {
                try? fm.removeItem(at: dest)
                ok = ((try? fm.copyItem(at: src, to: dest)) != nil)
            }
            guard ok else { continue }

            let orig = src.lastPathComponent
            let encoded = orig.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? orig
            for oldRef in Set(["Attachments/\(orig)", "Attachments/\(encoded)"]) {
                updated = updated.replacingOccurrences(of: "(\(oldRef))", with: "(Attachments/\(newName))")
            }
        }
        return updated
    }

    /// Convert an image (e.g. an Apple-Notes HEIC attachment) to JPEG using native
    /// ImageIO — no `/usr/bin/sips` subprocess (faster, dependency-free, survives a
    /// future sandbox). Returns false if the source can't be decoded or the write fails.
    private static func convertToJPEG(src: URL, dst: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let dest = CGImageDestinationCreateWithURL(dst as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    /// First `# ` heading (trailing dots trimmed), else the fallback. Mirrors
    /// `apple_notes_importer.parse_markdown_note`.
    static func appleNoteTitle(_ content: String, fallback: String) -> String {
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("# ") {
                let t = String(s.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if !t.isEmpty { return t }
            }
        }
        return fallback
    }

    /// A picked folder → ingest its top-level supported files: Apple-Note `.md`
    /// exports, audio recordings, AND video clips (e.g. dropping a folder of voice
    /// memos / self-recorded videos). Skips subfolders (an Apple Notes export's
    /// `Attachments/` images aren't notes).
    private func ingestFolder(_ url: URL, into context: ModelContext) async throws
        -> (created: [PipelineFile], skipped: [(url: URL, reason: String)]) {
        let items = ((try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var created: [PipelineFile] = []
        var skipped: [(url: URL, reason: String)] = []
        for item in items {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { continue }   // an Apple Notes export's `Attachments/` is not a note
            let ext = item.pathExtension.lowercased()
            guard let kind = ImportKinds.kind(forExtension: ext), [.text, .audio, .video].contains(kind) else {
                // Said, never dropped: a picture / PDF / book / unknown file in a folder.
                skipped.append((item, ImportKinds.kind(forExtension: ext) == .image
                                ? ImportReport.pictureInFolder
                                : ImportReport.skipReason(forName: item.lastPathComponent, onMac: true)))
                continue
            }
            // A folder is an Apple Notes export: its `.md` files are notes, a stray `.txt` is
            // clutter (IngestServiceTests pins this). A `.txt` DROPPED directly is a note.
            if kind == .text, ext == "txt" { skipped.append((item, ImportReport.textInFolder)); continue }
            if let pf = try await ingestFile(item, into: context) { created.append(pf) }
            else { skipped.append((item, ImportReport.skipReason(forName: item.lastPathComponent, onMac: true))) }
        }
        return (created, skipped)
    }

    private func makeFolder(id: String, filename: String) throws -> (URL, String) {
        let folder = outputDir.appendingPathComponent("\(id)_\(filename)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (folder, id)
    }
}
