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

    /// A captured photo handed off from the recorder: temp file + recording-time offset.
    typealias CapturedPhoto = (url: URL, offset: Double)

    /// Fire-and-forget: persist now, transcribe in the background. Used by the UI.
    func save(tempURL: URL, duration: TimeInterval, photos: [CapturedPhoto] = []) {
        let id = persist(tempURL: tempURL, duration: duration, photos: photos)
        Task { await runTranscription(id: id) }
    }

    /// Awaitable variant for tests — persist + transcribe, return the memo id.
    @discardableResult
    func saveAndTranscribe(tempURL: URL, duration: TimeInterval, photos: [CapturedPhoto] = []) async -> UUID {
        let id = persist(tempURL: tempURL, duration: duration, photos: photos)
        await runTranscription(id: id)
        return id
    }

    private func persist(tempURL: URL, duration: TimeInterval, photos: [CapturedPhoto]) -> UUID {
        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"
        let dest = AppPaths.recordingsDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: tempURL, to: dest)

        let manifest = movePhotos(photos, memoID: id)
        let metadata = manifest.isEmpty ? nil : MemoMetadata(imageManifest: manifest)

        repository.insert(Memo(
            id: id,
            audioFilename: filename,
            duration: duration,
            recordedAt: Date(),
            syncStatus: .waiting,
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
