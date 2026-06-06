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
    func save(tempURL: URL, duration: TimeInterval, photos: [CapturedPhoto] = [], provisionalTranscript: String? = nil) -> UUID {
        let id = persist(tempURL: tempURL, duration: duration, photos: photos, provisional: provisionalTranscript)
        Task { await captureMetadata(id: id) }
        Task { await runTranscription(id: id) }
        return id
    }

    /// Re-run the one-shot transcription on an existing memo's audio (the detail
    /// overflow "Re-transcribe"). Marks it transcribing, then refreshes the
    /// transcript + confidence + markers + word-timing sidecar.
    func retranscribe(id: UUID) {
        guard let memo = repository.memo(id: id) else { return }
        memo.transcriptStatus = .transcribing
        memo.transcriptUserEdited = false
        repository.save()
        Task { await runTranscription(id: id) }
    }

    /// Awaitable variant for tests — persist + capture metadata + transcribe.
    @discardableResult
    func saveAndTranscribe(tempURL: URL, duration: TimeInterval, photos: [CapturedPhoto] = []) async -> UUID {
        let id = persist(tempURL: tempURL, duration: duration, photos: photos, provisional: nil)
        await captureMetadata(id: id)
        await runTranscription(id: id)
        return id
    }

    /// Capture contextual metadata and merge it onto the memo, preserving the
    /// photo `imageManifest` set at persist time (capture doesn't know about it).
    private func captureMetadata(id: UUID) async {
        let captured = await metadataProvider.capture()
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
        let url = AppPaths.recordingsDirectory.appendingPathComponent("memo_\(id.uuidString).m4a")
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
