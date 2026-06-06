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

    /// Fire-and-forget: persist now, transcribe in the background. Used by the UI.
    func save(tempURL: URL, duration: TimeInterval) {
        let id = persist(tempURL: tempURL, duration: duration)
        Task { await runTranscription(id: id) }
    }

    /// Awaitable variant for tests — persist + transcribe, return the memo id.
    @discardableResult
    func saveAndTranscribe(tempURL: URL, duration: TimeInterval) async -> UUID {
        let id = persist(tempURL: tempURL, duration: duration)
        await runTranscription(id: id)
        return id
    }

    private func persist(tempURL: URL, duration: TimeInterval) -> UUID {
        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"
        let dest = AppPaths.recordingsDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: tempURL, to: dest)
        repository.insert(Memo(
            id: id,
            audioFilename: filename,
            duration: duration,
            recordedAt: Date(),
            syncStatus: .waiting,
            transcriptStatus: .transcribing
        ))
        return id
    }

    private func runTranscription(id: UUID) async {
        let url = AppPaths.recordingsDirectory.appendingPathComponent("memo_\(id.uuidString).m4a")
        do {
            let result = try await transcriber.transcribe(audioURL: url, imageManifest: [])
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
