import AVFoundation
import Foundation
import UIKit

/// Persists a finished recording as a `Memo` and runs transcription, writing the
/// transcript + confidence + markers onto the memo and the word timings to the
/// sidecar. Transcription runs off the UI (the `Transcribing` is an actor for the
/// real engine); the memo appears immediately as `.transcribing` and updates when
/// the transcript lands.
@MainActor
struct MemoSaver {
    var repository: NotesRepository = .shared
    var transcriber: any Transcribing = TranscriberFactory.make()
    var diarizer: any Diarizing = DiarizerFactory.make()
    var wordTimings = WordTimingsStore()
    var metadataProvider: any MetadataProviding = MetadataProviderFactory.make()
    /// Sleep before each transcription attempt of an APPENDED clip (first entry =
    /// the immediate attempt). `transcribe` itself awaits the model load, so these
    /// only kick in on genuine failures (failed download, engine error, unreadable
    /// file). Injectable so tests can retry instantly.
    var appendRetryDelays: [TimeInterval] = [0, 2, 5, 15]
    /// Opt-in source + clipboard writer for Settings → Capture → "Copy transcript
    /// to clipboard" (default OFF). Injectable for tests — UIPasteboard is shared
    /// global state.
    var defaults: UserDefaults = .standard
    var copyToClipboard: (String) -> Void = { UIPasteboard.general.string = $0 }

    /// UserDefaults key for the auto-copy opt-in (mirrored by `SettingsView`'s
    /// `@AppStorage`). Default OFF — user-locked decision.
    nonisolated static let autoCopySettingKey = "autoCopyTranscript"

    /// A captured photo handed off from the recorder: temp file + recording-time offset.
    typealias CapturedPhoto = (url: URL, offset: Double)

    /// Fire-and-forget: persist now (with the live caption as a provisional
    /// transcript so Memo detail shows text immediately), transcribe + capture
    /// metadata in the background. Returns the new memo id for navigation.
    @discardableResult
    func save(tempURL: URL, duration: TimeInterval, photos: [CapturedPhoto] = [], provisionalTranscript: String? = nil, capturedMetadata: MemoMetadata? = nil) -> UUID {
        let id = persist(tempURL: tempURL, duration: duration, photos: photos, provisional: provisionalTranscript)
        Task {
            await applyMetadata(id: id, pre: capturedMetadata)
            // OCR the just-captured photos NOW (after the metadata merge so the
            // manifest is settled) — the launch/foreground sweeps alone left a
            // fresh memo's photos unsearchable for the rest of the session
            // (device round 1, build 31).
            PhotoTextIndexer.run(repository)
        }
        // Background-task assertion like every import path has: without it, record →
        // stop → immediately background the app suspends this Task mid-transcribe and
        // the memo sits at "Transcribing…" until the next launch's recovery sweep.
        Task { await BackgroundTask.run(name: "skrift.save-transcribe") { await runTranscription(id: id) } }
        // Capture the recording (+ any photos) as CloudKit-mirrored MemoAssets right
        // away (Phase 1c) so a fresh memo syncs its media without waiting for the next
        // foreground sweep. Off the synchronous return path so navigation isn't blocked.
        Task { AssetMaterializer.capture(memoID: id, repository: repository) }
        return id
    }

    /// Import an external audio file shared into Skrift (Share Sheet / "Open in").
    /// Copies it into recordings (preserving the source extension), creates the
    /// memo, and runs the same on-device transcription as a recording — common
    /// formats (m4a/wav/mp3/caf) transcribe on-device; an unsupported one (e.g.
    /// .opus) fails gracefully → synced as raw audio → the Mac transcribes.
    /// No contextual metadata (the memo wasn't recorded here/now). Returns the
    /// new memo id, or nil if the file couldn't be copied.
    @discardableResult
    func importAudio(from source: URL, recordedAt: Date? = nil) -> UUID? {
        let id = UUID()
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let filename = "memo_\(id.uuidString).\(ext)"
        let dest = AppPaths.recordingsDirectory.appendingPathComponent(filename)

        // Files shared from outside the sandbox arrive security-scoped.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: source, to: dest)
        } catch {
            return nil
        }

        var duration: TimeInterval = 0
        if let f = try? AVAudioFile(forReading: dest) {
            duration = Double(f.length) / f.fileFormat.sampleRate
        }

        // Date ladder mirrors video: embedded asset date > supplied date (the
        // share's clip file date) > now. Device round 1: a WhatsApp voice note
        // landed dated to the UPLOAD moment, not the voice note's creation.
        repository.insert(Memo(
            id: id,
            audioFilename: filename,
            duration: duration,
            recordedAt: recordedAt ?? Date(),
            syncStatus: .waiting,
            transcriptStatus: .transcribing
        ))
        Task {
            // Background-task claim (Scribbel pattern): a share-launched import
            // finishes its transcribe in the ~30s grace when the user backgrounds
            // right away; the launch recovery sweep stays the backstop.
            await BackgroundTask.run(name: "skrift.import-audio") {
                if let d = await Self.embeddedCreationDate(of: AVURLAsset(url: dest)),
                   let memo = repository.memo(id: id) {
                    memo.recordedAt = d
                    repository.save()
                }
                await runTranscription(id: id)
            }
        }
        return id
    }

    // MARK: - Multi-clip audio import (Wave-1 B1 combine)

    /// Import N audio clips shared TOGETHER as ONE memo — the "8 WhatsApp voice
    /// notes → one note" flow (mock `share-ingest-wave1.html`, signed 2026-07-10).
    /// A single clip delegates to `importAudio`. Multiple clips: a placeholder
    /// memo appears immediately (same pattern as `importVideo`), then the clips
    /// are MERGED IN ORDER into one m4a off the UI and the merged file is
    /// transcribed once — one continuous transcript/karaoke, exactly like an
    /// audiobook capture + ramble. Returns the memo id, nil for an empty list.
    @discardableResult
    func importAudioClips(from sources: [URL], recordedAt: Date? = nil) -> UUID? {
        guard !sources.isEmpty else { return nil }
        if sources.count == 1 { return importAudio(from: sources[0], recordedAt: recordedAt) }

        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"
        repository.insert(Memo(
            id: id,
            audioFilename: filename,
            duration: 0,
            // The FIRST (oldest) clip's date — upgraded to its embedded asset
            // date in the async core when one exists.
            recordedAt: recordedAt ?? Date(),
            syncStatus: .waiting,
            transcriptStatus: .transcribing
        ))
        DevLog.log("importAudioClips: placeholder memo \(id) inserted; clips=\(sources.count)")
        Task {
            await BackgroundTask.run(name: "skrift.import-clips") {
                await importAudioClipsAsync(id: id, sources: sources)
            }
        }
        return id
    }

    /// Awaitable core of `importAudioClips` (used directly by tests): merge the
    /// clips into the memo's m4a, set the duration, transcribe. Returns true when
    /// the merge succeeded. Unreadable clips are skipped (logged); if NONE are
    /// readable the memo fails honestly with a reason title, never a silent husk.
    @discardableResult
    func importAudioClipsAsync(id: UUID, sources: [URL]) async -> Bool {
        let dest = AppPaths.recordingsDirectory.appendingPathComponent("memo_\(id.uuidString).m4a")
        do {
            try await Self.mergeAudio(sources: sources, to: dest)
        } catch {
            DevLog.log("importAudioClips[\(id)] merge failed: \(error)")
            if let memo = repository.memo(id: id) {
                memo.transcriptStatus = .failed
                memo.title = "Couldn't read the shared audio"
                repository.save()
            }
            return false
        }
        // First clip's embedded asset date (when present) beats the file date
        // the placeholder was seeded with — read BEFORE the temps are deleted.
        let embedded = await Self.embeddedCreationDate(of: AVURLAsset(url: sources[0]))
        for src in sources { try? FileManager.default.removeItem(at: src) }

        var duration: TimeInterval = 0
        if let f = try? AVAudioFile(forReading: dest) {
            duration = Double(f.length) / f.fileFormat.sampleRate
        }
        DevLog.log("importAudioClips[\(id)] merged ok; duration=\(String(format: "%.1f", duration))s")
        guard let memo = repository.memo(id: id) else { return true }
        memo.duration = duration
        if let embedded { memo.recordedAt = embedded }
        repository.save()
        await runTranscription(id: id)
        return true
    }

    /// Concatenate the audio of `sources` (in array order) into a single m4a at
    /// `dest` — SAMPLE-ACCURATE `AVAudioFile` frame reads, off the main actor.
    /// Device round 2: the AVMutableComposition+export path produced a phantom
    /// silent tail on WhatsApp voice notes (`merged ok; duration=287.5s` with the
    /// real content ending early) — the same compressed-audio weakness as the
    /// audiobook chunk-drift gotcha. Decoding real frames and re-encoding once
    /// writes exactly the audio that exists, nothing more.
    /// Unreadable clips are skipped; throws when none contribute audio.
    private static func mergeAudio(sources: [URL], to dest: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try mergeAudioSync(sources: sources, to: dest)
        }.value
    }

    nonisolated private static func mergeAudioSync(sources: [URL], to dest: URL) throws {
        try? FileManager.default.removeItem(at: dest)
        var out: AVAudioFile?
        var outFormat: AVAudioFormat?
        var wroteFrames = false

        for src in sources {
            guard let file = try? AVAudioFile(forReading: src) else {
                DevLog.log("mergeAudio: skipping unreadable clip \(src.lastPathComponent)")
                continue
            }
            let proc = file.processingFormat
            if out == nil {
                // AAC output at the first readable clip's rate/channels.
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: proc.sampleRate,
                    AVNumberOfChannelsKey: proc.channelCount,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                ]
                out = try AVAudioFile(forWriting: dest, settings: settings)
                outFormat = proc
            }
            guard let out, let outFormat else { continue }

            // Later clips in a different PCM format get converted to the first
            // clip's (rare — a WhatsApp batch is uniform). Per-file converter so
            // its internal state never crosses clip boundaries.
            let converter = proc == outFormat ? nil : AVAudioConverter(from: proc, to: outFormat)
            let chunkFrames: AVAudioFrameCount = 32_768
            // framePosition guard: AVAudioFile.read THROWS (-50) when asked to
            // read at EOF rather than returning zero frames.
            while file.framePosition < file.length {
                guard let buf = AVAudioPCMBuffer(pcmFormat: proc, frameCapacity: chunkFrames) else { break }
                try file.read(into: buf)
                guard buf.frameLength > 0 else { break }
                if let converter {
                    let ratio = outFormat.sampleRate / proc.sampleRate
                    let cap = AVAudioFrameCount(Double(buf.frameLength) * ratio) + 64
                    guard let cbuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: cap) else { break }
                    var fed = false
                    var convErr: NSError?
                    converter.convert(to: cbuf, error: &convErr) { _, status in
                        if fed { status.pointee = .noDataNow; return nil }
                        fed = true
                        status.pointee = .haveData
                        return buf
                    }
                    if convErr != nil {
                        DevLog.log("mergeAudio: convert failed on \(src.lastPathComponent): \(convErr!)")
                        break
                    }
                    if cbuf.frameLength > 0 {
                        try out.write(from: cbuf)
                        wroteFrames = true
                    }
                } else {
                    try out.write(from: buf)
                    wroteFrames = true
                }
            }
        }
        guard wroteFrames else { throw VideoImportError.noAudioTrack }
    }

    // MARK: - Video import (extract audio + 1 frame thumbnail)

    /// Import a VIDEO shared into Skrift / picked from Photos (e.g. a self-recorded
    /// "life advice to myself" clip). Strips the audio track to a `memo_<id>.m4a` and
    /// transcribes it on-device exactly like an audio import — the original video is
    /// NOT kept (audio + one representative frame is the captured decision). One frame
    /// is grabbed (`AVAssetImageGenerator`) and attached as a `[[img_001]]` via the
    /// existing image-manifest mechanism, landing at the start of the transcript.
    ///
    /// `recordedAt` comes from the video's EMBEDDED creation date (`AVAsset.creationDate`)
    /// or the supplied `creationDate` (e.g. `PHAsset.creationDate` from the Photos
    /// picker), NOT the import time — mirroring how the Mac reads the embedded recording
    /// date. Returns the new memo id, or nil if the audio couldn't be extracted.
    ///
    /// Fire-and-forget: persists the memo immediately (`.transcribing`) and runs audio
    /// extraction + transcription in the background; the memo updates in place.
    @discardableResult
    func importVideo(from source: URL, creationDate: Date? = nil) -> UUID? {
        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"

        // Insert a placeholder memo right away so the UI shows it while the audio
        // extraction (which can be slow for long clips) runs in the background. The
        // embedded creation date is read inside the async task and written back.
        repository.insert(Memo(
            id: id,
            audioFilename: filename,
            duration: 0,
            recordedAt: creationDate ?? Date(),
            syncStatus: .waiting,
            transcriptStatus: .transcribing
        ))
        DevLog.log("importVideo: placeholder memo \(id) inserted; source=\(source.lastPathComponent)")
        Task {
            await BackgroundTask.run(name: "skrift.import-video") {
                await processVideo(id: id, source: source, fallbackDate: creationDate)
            }
        }
        return id
    }

    /// Awaitable core of `importVideo` (used directly by tests): extract the audio,
    /// grab a frame thumbnail, set the embedded recording date, then transcribe.
    /// Returns true when audio extraction succeeded.
    @discardableResult
    func importVideoAsync(id: UUID, source: URL, fallbackDate: Date? = nil) async -> Bool {
        await processVideo(id: id, source: source, fallbackDate: fallbackDate)
    }

    @discardableResult
    private func processVideo(id: UUID, source: URL, fallbackDate: Date?) async -> Bool {
        let filename = "memo_\(id.uuidString).m4a"
        let dest = AppPaths.recordingsDirectory.appendingPathComponent(filename)

        // Files shared from outside the sandbox arrive security-scoped.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        DevLog.log("processVideo[\(id)] start; scoped=\(scoped) srcExists=\(FileManager.default.fileExists(atPath: source.path))")

        let asset = AVURLAsset(url: source)

        // Embedded recording date (survives copies) > supplied PHAsset date > now.
        let recorded = (await Self.embeddedCreationDate(of: asset)) ?? fallbackDate ?? Date()

        // Extract the audio track to .m4a. If the asset has no audio (a silent clip)
        // there's nothing to transcribe — fail gracefully, and SAY WHY: a bare
        // Error pill on an empty memo read as a mystery (2026-06-09 audit). An
        // unreadable container gets its own honest title (A9 — .avi/.mpg used to
        // claim "no audio track").
        let extracted: Bool
        var failTitle = "Video had no audio track"
        do { extracted = try await Self.extractAudio(from: asset, to: dest) }
        catch {
            DevLog.log("processVideo[\(id)] extractAudio threw: \(error)")
            if case VideoImportError.unreadableContainer = error {
                failTitle = "Video format not supported"
            }
            extracted = false
        }
        guard extracted else {
            DevLog.log("processVideo[\(id)] extract failed → .failed; memo present=\(repository.memo(id: id) != nil)")
            if let memo = repository.memo(id: id) {
                memo.transcriptStatus = .failed
                memo.recordedAt = recorded
                memo.title = failTitle
                var meta = memo.metadata ?? MemoMetadata()
                meta.sourceType = MemoMetadata.Source.video   // still a video → keep the source glyph
                memo.metadata = meta
                repository.save()
            }
            return false
        }
        DevLog.log("processVideo[\(id)] audio extracted ok")

        var duration: TimeInterval = 0
        if let f = try? AVAudioFile(forReading: dest) {
            duration = Double(f.length) / f.fileFormat.sampleRate
        }
        DevLog.log("processVideo[\(id)] duration=\(duration); grabbing frame")

        // One representative frame → photo_<id>_001.jpg → [[img_001]] at offset 0.
        var manifest: [ImageManifestEntry] = []
        if let frame = await Self.representativeFrame(of: asset) {
            let photoName = "photo_\(id.uuidString)_001.jpg"
            let photoDest = AppPaths.recordingsDirectory.appendingPathComponent(photoName)
            try? FileManager.default.removeItem(at: photoDest)
            if (try? frame.write(to: photoDest)) != nil {
                manifest.append(ImageManifestEntry(filename: photoName, offsetSeconds: 0))
            }
        }
        DevLog.log("processVideo[\(id)] frame done; manifest=\(manifest.count)")

        guard let memo = repository.memo(id: id) else {
            DevLog.log("processVideo[\(id)] memo GONE after extract (something deleted it)")
            return true
        }
        memo.recordedAt = recorded
        memo.duration = duration
        // Mark the source as video (the first entry of the unified source taxonomy)
        // so the list row shows a video glyph — set ALWAYS, even when no frame was
        // grabbed (a silent/odd clip), preserving the frame manifest when present.
        var meta = memo.metadata ?? MemoMetadata()
        meta.sourceType = MemoMetadata.Source.video
        if !manifest.isEmpty { meta.imageManifest = manifest }
        memo.metadata = meta
        repository.save()
        DevLog.log("processVideo[\(id)] memo updated; recordedAt=\(recorded) now=\(Date()) → transcribe")

        PhotoTextIndexer.run(repository)      // frame thumbnail → searchable now, not next launch
        await runTranscription(id: id)
        DevLog.log("processVideo[\(id)] done; final status=\(repository.memo(id: id).map { "\($0.transcriptStatus)" } ?? "GONE")")
        return true
    }

    // MARK: - Video helpers (pure AVFoundation — host-less testable)

    /// Video container UTIs/extensions Skrift accepts for import. `avi`/`mpg`/`mpeg`
    /// stay listed even though iOS AVFoundation can't demux them: the `public.movie`
    /// doc type delivers them anyway, and routing them into `importVideo` yields the
    /// honest "format not supported" memo — dropping them here would silently eat the
    /// share (A9).
    nonisolated static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "qt", "avi", "mpg", "mpeg", "3gp", "3g2"]

    /// True when the URL's extension is a known video container. Used to route a
    /// shared/opened file to `importVideo` rather than `importAudio`.
    nonisolated static func isVideoFile(_ url: URL) -> Bool {
        videoExtensions.contains(url.pathExtension.lowercased())
    }

    /// The video's embedded creation date (QuickTime `creationDate` / mp4
    /// `creation_time`). Survives copies — unlike the filesystem date, which becomes
    /// the import/copy time. nil when absent or unparseable.
    nonisolated static func embeddedCreationDate(of asset: AVAsset) async -> Date? {
        guard let item = (try? await asset.load(.creationDate)) ?? nil else { return nil }
        if let d = (try? await item.load(.dateValue)) ?? nil { return d }
        if let s = (try? await item.load(.stringValue)) ?? nil, let d = parseCreationDate(s) { return d }
        return nil
    }

    /// Parse an ISO-8601 creation-date string (with or without fractional seconds).
    nonisolated static func parseCreationDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }

    enum VideoImportError: Error { case unreadableContainer, noAudioTrack, exportFailed }

    /// Strip the audio track of `asset` into a standalone .m4a at `dest`. Throws when
    /// the asset has no audio or the export fails (caller marks the memo failed).
    private static func extractAudio(from asset: AVAsset, to dest: URL) async throws -> Bool {
        // A container AVFoundation can't demux (.avi/.mpg arrive via the public.movie
        // doc type) must fail as "format not supported", not "no audio track" (A9).
        guard (try? await asset.load(.isReadable)) == true else {
            throw VideoImportError.unreadableContainer
        }
        let comp = AVMutableComposition()
        guard let track = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw VideoImportError.noAudioTrack
        }
        let duration = try await asset.load(.duration)
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audioTrack, at: .zero)

        guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetAppleM4A) else {
            throw VideoImportError.exportFailed
        }
        try? FileManager.default.removeItem(at: dest)
        try await export.export(to: dest, as: .m4a)
        return true
    }

    /// Grab one representative frame (near the start, tolerant) as JPEG data. nil when
    /// the asset has no video track or the generator fails.
    private static func representativeFrame(of asset: AVAsset) async -> Data? {
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else {
            return nil
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        // 1s in (or the first frame for very short clips) — avoids a black opening frame.
        let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        let at = CMTime(seconds: min(1.0, max(0, duration / 2)), preferredTimescale: 600)
        guard let cg = try? await generator.image(at: at).image else { return nil }
        let ui = UIImage(cgImage: cg)
        return ui.jpegData(compressionQuality: 0.85)
    }

    // MARK: - Audiobook quote capture

    /// Save an audiobook QUOTE CAPTURE as a memo (cross-lane contracts C1/C2).
    /// The audio is the already sentence-snapped quote span (a temp .m4a the
    /// capture flow extracted + trimmed); the transcript is the quote as
    /// markdown blockquote lines ("> " prefix) — the ramble later appends below
    /// it via the ordinary `appendRecording` flow, audio merge included, which
    /// yields exactly the C1 shape (quote block, blank line, ramble). The phone
    /// writes NO `[[..]]` and NO attribution line — the Mac owns both at export.
    ///
    /// Self-contained like `importAudio`/`importVideo`: no transcription run
    /// (the quote text came from the capture flow's span transcription) and no
    /// contextual location/weather capture (the moment belongs to the book, not
    /// the room). `transcriptUserEdited` is set so the Mac trusts the formatted
    /// transcript verbatim instead of re-transcribing the quote audio (which
    /// would destroy the blockquote). `recordedAt` = the capture time.
    /// Returns the new memo id, or nil if the quote audio couldn't be moved.
    @discardableResult
    func saveQuoteCapture(
        audioTempURL: URL,
        quote: String,
        duration: TimeInterval,
        wordTimings timings: [WordTiming] = [],
        bookTitle: String?,
        bookAuthor: String?,
        bookChapter: String?,
        bookID: UUID? = nil,
        bookPosition: Double? = nil,
        recordedAt: Date = Date()
    ) -> UUID? {
        let transcript = QuoteFormatting.blockquote(quote)
        guard !transcript.isEmpty else { return nil }

        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"
        let dest = AppPaths.recordingsDirectory.appendingPathComponent(filename)
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: audioTempURL, to: dest)
        } catch {
            print("[Skrift] Quote capture audio move failed: \(error)")
            return nil
        }

        repository.insert(Memo.make(
            id: id,
            audioFilename: filename,
            duration: duration,
            recordedAt: recordedAt,
            syncStatus: .waiting,
            transcript: transcript,
            transcriptStatus: .done,
            transcriptUserEdited: true,   // deliberate formatting — Mac must not re-transcribe
            metadata: MemoMetadata(
                bookTitle: bookTitle,
                bookAuthor: bookAuthor,
                bookChapter: bookChapter,
                bookID: bookID,
                bookPosition: bookPosition
            )
        ))
        if !timings.isEmpty {
            wordTimings.write(timings, for: id)
        }
        return id
    }

    /// Awaitable variant for tests — persist + capture metadata + transcribe.
    @discardableResult
    func saveAndTranscribe(tempURL: URL, duration: TimeInterval, photos: [CapturedPhoto] = []) async -> UUID {
        let id = persist(tempURL: tempURL, duration: duration, photos: photos, provisional: nil)
        await applyMetadata(id: id, pre: nil)
        PhotoTextIndexer.run(repository)
        await runTranscription(id: id)
        return id
    }

    /// Append a follow-up recording to an EXISTING memo (memo detail → "Add
    /// recording"). Fire-and-forget: transcribe the new clip, merge its audio onto
    /// the memo's file, append the new text (+ word timings shifted past the prior
    /// duration), and mark the transcript user-edited so the Mac trusts the combined
    /// result (no re-transcription). The memo updates in place.
    func appendRecording(to memoID: UUID, tempURL: URL, duration: TimeInterval, liveCaption: String? = nil) {
        Task { await appendRecordingAsync(to: memoID, tempURL: tempURL, duration: duration, liveCaption: liveCaption) }
    }

    /// Awaitable core of `appendRecording` (used directly by tests).
    ///
    /// Hardened after the 2026-06-10 "append silently adds NO text" repros: the
    /// memo shows `.transcribing` for the whole append (which also swaps the
    /// detail editor out, so a mid-edit draft can't clobber the appended text when
    /// it lands), the clip is KEPT on disk until its text has landed (deleting it
    /// up front destroyed the only retry source), a cold engine is awaited +
    /// retried instead of `try?`-swallowed, and a terminal failure surfaces as
    /// `.failed` (the memos list shows an Error pill) — never a silent no-op.
    func appendRecordingAsync(to memoID: UUID, tempURL: URL, duration: TimeInterval, liveCaption: String? = nil) async {
        guard let memo = repository.memo(id: memoID), let memoURL = memo.audioURL else {
            DevLog.log("append BAILED — memo missing or no audioURL (memoID \(memoID)); clip discarded")
            try? FileManager.default.removeItem(at: tempURL); return
        }
        let priorDuration = memo.duration
        let priorStatus = memo.transcriptStatus
        DevLog.log("append start memo \(memoID) clipDur=\(String(format: "%.1f", duration))s priorStatus=\(priorStatus) priorBodyLen=\((memo.transcript ?? "").count)")

        // Make the append visible immediately — a cold model can take a while.
        memo.transcriptStatus = .transcribing
        repository.save()

        // Move the clip to a stable name; it must survive until its text landed.
        let clipURL = AppPaths.recordingsDirectory
            .appendingPathComponent("append_\(memoID.uuidString)_\(UUID().uuidString).m4a")
        var clip = tempURL
        do {
            try FileManager.default.moveItem(at: tempURL, to: clipURL)
            clip = clipURL
        } catch {
            // Couldn't move (shouldn't happen — same volume); transcribe in place.
        }

        // Merge the new audio onto the memo FIRST so playback + sync are coherent
        // even while a cold engine is still loading. (The merge only reads the
        // clip — it stays available for transcription.) If the merge can't run
        // (e.g. placeholder audio in tests), keep the base audio and still append
        // the text — the feature is "add more text", audio is a bonus.
        let merge = try? await Self.appendAudio(base: memoURL, addition: clip)
        let mergedDuration = merge?.merged ?? priorDuration
        // Shift the appended clip's word-timings by the PRECISE base duration the
        // clip was spliced at — not the (possibly-estimated) memo.duration.
        let clipOffset = merge?.base ?? priorDuration

        // Transcribe the clip (no image markers on an append). `transcribe` itself
        // awaits the model load, so stopping the append before the model was ready
        // QUEUES here instead of failing; the retry loop covers real errors.
        var result: TranscriptionResult?
        let delays = appendRetryDelays.isEmpty ? [0] : appendRetryDelays
        for delay in delays {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            if let attempt = try? await transcriber.transcribe(audioURL: clip, imageManifest: []) {
                result = attempt
                break
            }
        }

        // Prefer the engine text; fall back to the live caption when the engine
        // ran but heard nothing (e.g. its silence guard).
        let engineText = (result?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackCaption = (liveCaption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let newText = engineText.isEmpty ? fallbackCaption : (result?.text ?? "")
        let newTimings = engineText.isEmpty ? [] : (result?.wordTimings ?? [])
        DevLog.log("append transcribe: gotResult=\(result != nil) engineLen=\(engineText.count) captionLen=\(fallbackCaption.count) clipExists=\(FileManager.default.fileExists(atPath: clip.path))")

        guard let memo = repository.memo(id: memoID) else {
            try? FileManager.default.removeItem(at: clip)
            return
        }
        memo.duration = mergedDuration

        guard !newText.isEmpty else {
            if result != nil {
                // The engine ran and heard no speech (and no live caption either):
                // an honest no-text append. The audio is merged; restore the prior
                // status and consume the clip.
                DevLog.log("append NO-TEXT: engine ran but heard nothing (no caption) → restored \(priorStatus); nothing appended")
                memo.transcriptStatus = priorStatus
                try? FileManager.default.removeItem(at: clip)
            } else {
                DevLog.log("append FAILED: transcription threw on every retry → .failed; clip kept for retry")
                // Transcription failed outright after retries — surface it (the
                // memos list shows an Error pill) and KEEP the clip on disk as the
                // retry source. transcriptUserEdited stays untouched, so an
                // unedited memo can still be re-transcribed by the Mac (the
                // appended speech is already merged into the audio).
                memo.transcriptStatus = .failed
            }
            repository.save()
            return
        }

        let existing = (memo.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        memo.transcript = existing.isEmpty ? newText : existing + "\n\n" + newText
        memo.transcriptUserEdited = true   // Mac trusts the combined transcript as-is
        memo.transcriptStatus = .done
        memo.markEdited()
        DevLog.log("append LANDED: +\(newText.count) chars (existing=\(existing.count)) → total \(memo.transcript?.count ?? 0)")

        // Shift the new clip's word timings past the prior audio + append to the sidecar.
        if !newTimings.isEmpty {
            let shifted = newTimings.map { WordTiming(word: $0.word, start: $0.start + clipOffset, end: $0.end + clipOffset) }
            wordTimings.write((wordTimings.load(for: memoID) ?? []) + shifted, for: memoID)
        }
        repository.save()
        autoCopyIfEnabled(memo.transcript)   // the COMBINED transcript, not just the clip
        try? FileManager.default.removeItem(at: clip)
    }

    /// Settings → Capture → "Copy transcript to clipboard" (default OFF): when
    /// the user opted in, put the finished transcript on the pasteboard. Called
    /// only on transcription SUCCESS — failures and silent no-text results never
    /// overwrite the clipboard.
    private func autoCopyIfEnabled(_ transcript: String?) {
        guard defaults.bool(forKey: Self.autoCopySettingKey),
              let transcript, !transcript.isEmpty else { return }
        copyToClipboard(transcript)
    }

    /// Errors that make the audio merge fall back to keeping the base file.
    private enum AppendError: Error { case composition, noBaseTrack }

    /// Concatenate `addition` after `base` into one .m4a, replacing `base` in place.
    /// Returns the merged duration AND the precise `base` duration — the exact splice
    /// offset, which the caller uses to shift the appended clip's word-timings (memo
    /// `duration` can be an estimate for imported VBR audio and would drift karaoke).
    /// Throws on non-audio inputs (the caller then keeps the base audio).
    private static func appendAudio(base: URL, addition: URL) async throws -> (merged: TimeInterval, base: TimeInterval) {
        let comp = AVMutableComposition()
        guard let track = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AppendError.composition
        }
        // Precise timing: `base` can be an imported MP3 (importAudio preserves
        // the .mp3 extension). Without the key a VBR MP3 reports an estimated
        // duration, which would misplace the splice offset (`at: baseDur`) and
        // write a wrong merged duration. The addition is always the app's own
        // AAC clip, so it doesn't need it.
        let baseAsset = AVURLAsset(url: base, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let baseDur = try await baseAsset.load(.duration)
        guard let baseTrack = try await baseAsset.loadTracks(withMediaType: .audio).first else { throw AppendError.noBaseTrack }
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: baseDur), of: baseTrack, at: .zero)

        let addAsset = AVURLAsset(url: addition)
        var addSeconds = 0.0
        if let addTrack = try? await addAsset.loadTracks(withMediaType: .audio).first,
           let addDur = try? await addAsset.load(.duration) {
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: addDur), of: addTrack, at: baseDur)
            addSeconds = CMTimeGetSeconds(addDur)
        }

        guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetAppleM4A) else {
            throw AppendError.composition
        }
        let tmpOut = base.deletingLastPathComponent().appendingPathComponent("merge_\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: tmpOut)
        try await export.export(to: tmpOut, as: .m4a)
        // Atomic replace — a failed swap or a kill mid-move can NEVER leave the memo
        // with no audio file (the old remove-then-move had that data-loss window).
        _ = try FileManager.default.replaceItemAt(base, withItemAt: tmpOut)
        let baseSeconds = CMTimeGetSeconds(baseDur)
        return (merged: baseSeconds + addSeconds, base: baseSeconds)
    }

    /// Merge contextual metadata onto the memo, preserving the photo
    /// `imageManifest` set at persist time. Reuses `pre` (captured when the
    /// recorder opened) if given, else captures now.
    private func applyMetadata(id: UUID, pre: MemoMetadata?) async {
        let captured: MemoMetadata
        if let pre { captured = pre } else { captured = await metadataProvider.capture() }
        guard let memo = repository.memo(id: id) else { return }
        var merged = captured
        merged.imageManifest = memo.metadata?.imageManifest ?? captured.imageManifest
        memo.metadata = merged
        repository.save()
    }

    private func persist(tempURL: URL, duration: TimeInterval, photos: [CapturedPhoto], provisional: String?) -> UUID {
        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"
        let dest = AppPaths.recordingsDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: tempURL, to: dest)
        } catch {
            // A silent move failure here used to insert a Memo pointing at a file that
            // was never written. Rescue with a copy (leaves the tmp original in place);
            // if that also fails the insert still happens so the memo surfaces as
            // .failed instead of the recording vanishing without a trace.
            DevLog.log("persist[\(id)]: audio move FAILED (\(error)) — trying copy fallback")
            do { try FileManager.default.copyItem(at: tempURL, to: dest) }
            catch { DevLog.log("persist[\(id)]: copy fallback FAILED — \(filename) missing: \(error)") }
        }

        let manifest = movePhotos(photos, memoID: id)
        let metadata = manifest.isEmpty ? nil : MemoMetadata(imageManifest: manifest)
        let provisionalText = provisional?.trimmingCharacters(in: .whitespacesAndNewlines)

        repository.insert(Memo.make(
            id: id,
            audioFilename: filename,
            duration: duration,
            recordedAt: Date(),
            syncStatus: .waiting,
            transcript: (provisionalText?.isEmpty == false) ? provisionalText : nil,
            transcriptStatus: .transcribing,
            metadata: metadata
        ))
        return id
    }

    /// Move captured photos to `photo_{memoId}_{NNN}.jpg` and build the manifest
    /// (ascending in capture order).
    private func movePhotos(_ photos: [CapturedPhoto], memoID: UUID) -> [ImageManifestEntry] {
        var manifest: [ImageManifestEntry] = []
        for (index, photo) in photos.enumerated() {
            let filename = "photo_\(memoID.uuidString)_\(String(format: "%03d", index + 1)).jpg"
            let dest = AppPaths.recordingsDirectory.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: photo.url, to: dest)
                manifest.append(ImageManifestEntry(filename: filename, offsetSeconds: photo.offset))
            } catch {
                // skip a photo that couldn't be moved
            }
        }
        return manifest
    }

    private func runTranscription(id: UUID) async {
        // Use the memo's actual filename (recordings are memo_<id>.m4a; imports
        // preserve the source extension, e.g. .opus/.wav/.mp3).
        let filename = repository.memo(id: id)?.audioFilename ?? "memo_\(id.uuidString).m4a"
        let url = AppPaths.recordingsDirectory.appendingPathComponent(filename)
        let manifest = repository.memo(id: id)?.metadata?.imageManifest ?? []
        do {
            let result = try await transcriber.transcribe(audioURL: url, imageManifest: manifest)
            // Opt-in deterministic filler strip (Settings -> Transcription), OFF by
            // default: standalone hesitations (um/uh/hmm...) drop from the text AND
            // the karaoke timings in lockstep. Voice memos/imports only - audiobook
            // quote captures never pass through here (verbatim book text).
            var storedText = result.text
            var storedTimings = result.wordTimings
            if UserDefaults.standard.bool(forKey: FillerFilter.settingKey) {
                let stripped = FillerFilter.strip(transcript: storedText, words: storedTimings)
                storedText = stripped.text
                storedTimings = stripped.words
            }
            if !storedTimings.isEmpty {
                wordTimings.write(storedTimings, for: id)
            }
            guard let memo = repository.memo(id: id) else { return }
            let text = storedText.trimmingCharacters(in: .whitespacesAndNewlines)
            // Paragraph the stored transcript (hybrid: long pause after a sentence,
            // or every ~4 sentences) so the memo + Obsidian export read as paragraphs
            // instead of a wall of text. Token-preserving (punctuation + [[img]]
            // markers intact); karaoke is newline-aware so word-timing alignment holds.
            memo.transcript = text.isEmpty ? nil : Paragrapher.paragraphed(transcript: storedText, words: storedTimings)
            memo.transcriptConfidence = result.confidence
            memo.transcriptMarkersInjected = result.markersInjected
            memo.transcriptStatus = text.isEmpty ? .failed : .done
            repository.save()
            autoCopyIfEnabled(memo.transcript)
            // Speaker splitting is a deliberate POST-transcript action now (the "Split
            // speakers" button in Memo detail), not automatic on save — so a recording is
            // never gated on remembering a toggle, and the slow diarization model only
            // loads when you actually ask to split.
        } catch {
            DevLog.log("runTranscription[\(id)] FAILED: \(error)")
            if let memo = repository.memo(id: id) {
                memo.transcriptStatus = .failed
                repository.save()
            }
        }
    }

    /// Re-transcribe recordings orphaned at `.transcribing` by a process kill.
    /// A recording's transcription runs in a fire-and-forget `Task` (see `save`)
    /// that CANNOT survive app suspension/termination — e.g. a cold-launch
    /// auto-record (widget/Siri) stopped before the ASR model finished loading,
    /// then the app was backgrounded: the `Task` dies and the memo is stranded
    /// as `.transcribing` forever — a perpetual "Transcribing" spinner with no
    /// retry (the 2026-06-16 device bug: "the last message is stuck … not
    /// transcribing at all"). No transcription `Task` survives a relaunch, so at
    /// launch ANY memo still `.transcribing` is orphaned by definition and safe
    /// to re-run. Called once per launch from `SkriftApp`.
    ///
    /// Scoped to PLAIN audio memos (recordings + audio/video imports) — exactly
    /// what `runTranscription` owns. Capture *dictations* (empty `audioFilename`,
    /// audio in the pending dir) are recovered by `CaptureDictation.resumePending`;
    /// audiobook *captures* (`isBookCapture`) transcribe at creation and resume
    /// via `BookTranscriptionJob` — both excluded so this never clobbers them.
    /// Runs sequentially: one model-bound transcription at a time.
    /// Whether THIS device should recover a stuck memo: only ones it recorded
    /// (`recordingDeviceID == current`) or legacy/local memos with no id. A memo that
    /// arrived from another device still `.transcribing` is owned by THAT device — the
    /// transcript will sync once it finishes; re-transcribing here would race/clobber.
    nonisolated static func ownsForRecovery(_ recordingDeviceID: String?, thisDevice: String = DeviceID.current()) -> Bool {
        recordingDeviceID == nil || recordingDeviceID == thisDevice
    }

    func recoverStuckTranscriptions() async {
        let stuck = repository.allMemos().filter { memo in
            memo.transcriptStatus == .transcribing
                && !memo.audioFilename.isEmpty
                && !memo.isBookCapture
                && Self.ownsForRecovery(memo.recordingDeviceID)
                && FileManager.default.fileExists(
                    atPath: AppPaths.recordingsDirectory
                        .appendingPathComponent(memo.audioFilename).path)
        }
        guard !stuck.isEmpty else { return }
        DevLog.log("recover: \(stuck.count) memo(s) stuck in .transcribing — re-running")
        for memo in stuck {
            DevLog.log("recover stuck transcription — memo \(memo.id)")
            await runTranscription(id: memo.id)
        }
    }

    /// Split an already-saved memo into speakers (the detail's "Split speakers" button):
    /// load its audio + word-timings and re-emit the transcript as speaker turns.
    /// `targetSpeakers` forces exactly N voices (nil = Auto). ≥2 speakers → turns;
    /// otherwise the transcript is left as plain prose.
    func diarizeExisting(id: UUID, targetSpeakers: Int? = nil) async {
        guard let memo = repository.memo(id: id), let url = memo.audioURL,
              let words = wordTimings.load(for: id), !words.isEmpty else { return }
        // Mark in-flight so a diarization orphaned by app suspension is re-run at the
        // next launch (recoverStuckDiarizations). 0 = Auto, N>0 = forced N speakers.
        memo.pendingDiarizationTarget = targetSpeakers ?? 0
        repository.save()
        await diarizeIntoTurns(id: id, audioURL: url, words: words, targetSpeakers: targetSpeakers)
        // Attempt complete (a real split OR a <2-speaker no-op) — clear the marker.
        // A kill MID-diarize never reaches here, so the marker survives for recovery.
        repository.memo(id: id)?.pendingDiarizationTarget = nil
        repository.save()
    }

    /// Re-run any diarization orphaned by a process kill. "Split speakers" runs in a
    /// fire-and-forget Task that can't survive app suspension — the user backgrounds
    /// the app while it's "identifying speakers" (it can take a while), the Task dies,
    /// and the memo is stranded with `pendingDiarizationTarget` still set and the
    /// transcript un-split (2026-06-21 device bug). Any memo still marked in-flight at
    /// launch is orphaned by definition → re-run it. Scoped like the transcription
    /// sweep: this device's own memos (`ownsForRecovery`), audio + word-timings present
    /// (diarization needs both). Called once per launch from `SkriftApp`.
    func recoverStuckDiarizations() async {
        let stuck = repository.allMemos().filter { memo in
            memo.pendingDiarizationTarget != nil
                && !memo.audioFilename.isEmpty
                && Self.ownsForRecovery(memo.recordingDeviceID)
                && (wordTimings.load(for: memo.id)?.isEmpty == false)
                && FileManager.default.fileExists(
                    atPath: AppPaths.recordingsDirectory
                        .appendingPathComponent(memo.audioFilename).path)
        }
        guard !stuck.isEmpty else { return }
        DevLog.log("recover: \(stuck.count) memo(s) stuck mid-diarization — re-running")
        for memo in stuck {
            let target = memo.pendingDiarizationTarget ?? 0     // 0 = Auto
            DevLog.log("recover stuck diarization — memo \(memo.id) target=\(target)")
            await diarizeExisting(id: memo.id, targetSpeakers: target == 0 ? nil : target)
        }
    }

    /// Diarize the recording and, if ≥2 speakers are found, rewrite the transcript as
    /// `**Speaker N:**` turns (fused with the word-timings). A single-speaker result is
    /// left as the plain transcript.
    private func diarizeIntoTurns(id: UUID, audioURL: URL, words: [WordTiming], targetSpeakers: Int?) async {
        DiarizationStatus.shared.begin(id)
        defer { DiarizationStatus.shared.finish() }
        guard let out = try? await diarizer.diarize(audioURL: audioURL, targetSpeakers: targetSpeakers),
              Set(out.segments.map(\.speaker)).count >= 2 else { return }
        // Auto-matched (enrolled) speakers come back named; the rest are "Speaker N".
        var attributed = SpeakerFusion.attributedTranscript(words: words, segments: out.segments) {
            out.slotNames[$0] ?? "Speaker \($0 + 1)"
        }
        guard let memo = repository.memo(id: id) else { return }
        // Fusion rebuilds from the words, which drops the `[[img_NNN]]` photo markers — so
        // re-insert them by timestamp, landing each in the turn being spoken when it was
        // taken (photos + manifest are untouched; this restores the inline markers).
        if let manifest = memo.metadata?.imageManifest, !manifest.isEmpty {
            let tw = words.map { TimedWord(text: $0.word, start: $0.start, end: $0.end) }
            attributed = ImageMarkers.insert(transcript: attributed, words: tw, manifest: manifest)
        }
        memo.transcript = attributed
        memo.transcriptStatus = .done
        // Diarization is a deliberate, structural transformation the Mac MUST preserve —
        // mark it user-edited so it's trusted regardless of the original ASR confidence.
        // Otherwise a noisy multi-speaker take with confidence < 0.7 gets silently
        // re-transcribed on the Mac (turns destroyed) — same rationale as the quote
        // capture / appended-recording paths above.
        memo.transcriptUserEdited = true
        memo.markEdited()   // structural change → bump the Recently-edited sort, like append
        repository.save()
        // Persist segments + per-slot names so naming can extract a speaker's audio,
        // plus the per-turn slot map (turn i → slot) so a rename/enroll targets ONE
        // speaker even when two slots share a name. turns() with the default minTurnWords
        // matches the order attributedTranscript emitted above, so the indices line up.
        var names: [String: String] = [:]
        for seg in out.segments { names[String(seg.speaker)] = out.slotNames[seg.speaker] ?? "Speaker \(seg.speaker + 1)" }
        let turnSlots = SpeakerFusion.turns(words: words, segments: out.segments).map(\.speaker)
        DiarizationStore().write(DiarizationData(segments: out.segments, slotNames: names, turnSlots: turnSlots), for: id)
    }
}
