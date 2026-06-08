import AVFoundation
import Foundation

/// Persists a finished recording as a `Memo` and runs transcription, writing the
/// transcript + confidence + markers onto the memo and the word timings to the
/// sidecar. Transcription runs off the UI (the `Transcriber` is an actor for the
/// real engine); the memo appears immediately as `.transcribing` and updates when
/// the transcript lands.
@MainActor
struct MemoSaver {
    var repository: NotesRepository = .shared
    var transcriber: any Transcriber = TranscriberFactory.make()
    var wordTimings = WordTimingsStore()
    var metadataProvider: any MetadataProviding = MetadataProviderFactory.make()

    /// A captured photo handed off from the recorder: temp file + recording-time offset.
    typealias CapturedPhoto = (url: URL, offset: Double)

    /// Fire-and-forget: persist now (with the live caption as a provisional
    /// transcript so Memo detail shows text immediately), transcribe + capture
    /// metadata in the background. Returns the new memo id for navigation.
    @discardableResult
    func save(tempURL: URL, duration: TimeInterval, photos: [CapturedPhoto] = [], provisionalTranscript: String? = nil, capturedMetadata: MemoMetadata? = nil) -> UUID {
        let id = persist(tempURL: tempURL, duration: duration, photos: photos, provisional: provisionalTranscript)
        Task { await applyMetadata(id: id, pre: capturedMetadata) }
        Task { await runTranscription(id: id) }
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
    func importAudio(from source: URL) -> UUID? {
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

        repository.insert(Memo(
            id: id,
            audioFilename: filename,
            duration: duration,
            syncStatus: .waiting,
            transcriptStatus: .transcribing
        ))
        Task { await runTranscription(id: id) }
        return id
    }

    /// Awaitable variant for tests — persist + capture metadata + transcribe.
    @discardableResult
    func saveAndTranscribe(tempURL: URL, duration: TimeInterval, photos: [CapturedPhoto] = []) async -> UUID {
        let id = persist(tempURL: tempURL, duration: duration, photos: photos, provisional: nil)
        await applyMetadata(id: id, pre: nil)
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
    func appendRecordingAsync(to memoID: UUID, tempURL: URL, duration: TimeInterval, liveCaption: String? = nil) async {
        guard let memo = repository.memo(id: memoID), let memoURL = memo.audioURL else {
            try? FileManager.default.removeItem(at: tempURL); return
        }
        let priorDuration = memo.duration

        // Transcribe the new clip (no image markers on an append). Fall back to the
        // live caption if the engine yields nothing.
        var newText = (liveCaption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var newTimings: [WordTiming] = []
        if let result = try? await transcriber.transcribe(audioURL: tempURL, imageManifest: []) {
            let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { newText = result.text; newTimings = result.wordTimings }
        }

        // Merge the new audio onto the memo so playback + sync stay coherent. If the
        // merge can't run (e.g. placeholder audio in tests), keep the base audio and
        // still append the text — the feature is "add more text", audio is a bonus.
        let mergedDuration = (try? await Self.appendAudio(base: memoURL, addition: tempURL)) ?? priorDuration
        try? FileManager.default.removeItem(at: tempURL)

        guard let memo = repository.memo(id: memoID) else { return }
        let existing = (memo.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = existing.isEmpty ? newText : (newText.isEmpty ? existing : existing + "\n\n" + newText)
        memo.transcript = combined.isEmpty ? nil : combined
        memo.transcriptUserEdited = true   // Mac trusts the combined transcript as-is
        if !combined.isEmpty { memo.transcriptStatus = .done }
        memo.duration = mergedDuration

        // Shift the new clip's word timings past the prior audio + append to the sidecar.
        if !newTimings.isEmpty {
            let shifted = newTimings.map { WordTiming(word: $0.word, start: $0.start + priorDuration, end: $0.end + priorDuration) }
            wordTimings.write((wordTimings.load(for: memoID) ?? []) + shifted, for: memoID)
        }
        repository.save()
    }

    /// Errors that make the audio merge fall back to keeping the base file.
    private enum AppendError: Error { case composition, noBaseTrack }

    /// Concatenate `addition` after `base` into one .m4a, replacing `base` in place.
    /// Returns the merged duration (seconds). Throws on non-audio inputs (the caller
    /// then keeps the base audio).
    private static func appendAudio(base: URL, addition: URL) async throws -> TimeInterval {
        let comp = AVMutableComposition()
        guard let track = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AppendError.composition
        }
        let baseAsset = AVURLAsset(url: base)
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
        try? FileManager.default.removeItem(at: base)
        try FileManager.default.moveItem(at: tmpOut, to: base)
        return CMTimeGetSeconds(baseDur) + addSeconds
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
        try? FileManager.default.moveItem(at: tempURL, to: dest)

        let manifest = movePhotos(photos, memoID: id)
        let metadata = manifest.isEmpty ? nil : MemoMetadata(imageManifest: manifest)
        let provisionalText = provisional?.trimmingCharacters(in: .whitespacesAndNewlines)

        repository.insert(Memo(
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
            if !result.wordTimings.isEmpty {
                wordTimings.write(result.wordTimings, for: id)
            }
            guard let memo = repository.memo(id: id) else { return }
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            memo.transcript = text.isEmpty ? nil : result.text
            memo.transcriptConfidence = result.confidence
            memo.transcriptMarkersInjected = result.markersInjected
            memo.transcriptStatus = text.isEmpty ? .failed : .done
            repository.save()
        } catch {
            if let memo = repository.memo(id: id) {
                memo.transcriptStatus = .failed
                repository.save()
            }
        }
    }
}
