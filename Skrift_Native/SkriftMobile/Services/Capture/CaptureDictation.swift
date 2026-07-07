import Foundation

/// Transcribes a capture's dictated voice note in the MAIN APP (the share
/// extension only records — Parakeet can't fit in its memory ceiling) and
/// appends the text to `Memo.annotationText`.
///
/// Hardening mirrors `MemoSaver.appendRecordingAsync` (the 2026-06-10 "append
/// silently adds NO text" lessons):
/// - the memo shows `.transcribing` the whole time (the capture detail swaps its
///   annotation editor out, so a mid-edit draft can't clobber the landing text);
/// - the audio is KEPT on disk until its text has landed (it is the only retry
///   source) and deleted only on success or an honest engine-heard-nothing;
/// - a cold engine is awaited + retried; terminal failure surfaces as `.failed`
///   (Error pill) — never a silent no-op — and the next drain retries it;
/// - the capture only reads as complete once its text is `.done`, so nothing
///   downstream races the dictated text.
@MainActor
enum CaptureDictation {

    /// Retry delays (seconds) between transcription attempts. Injectable so
    /// tests run instantly.
    static var retryDelays: [TimeInterval] = [0, 2, 5]

    /// Memo IDs with a transcription in flight — guards against a foreground
    /// bounce double-kicking the same dictation (double-append risk).
    private(set) static var inFlight: Set<UUID> = []

    /// Where a memo's pending dictation audio lives (app-owned, survives until
    /// the text has landed).
    static func pendingAudioURL(for memoID: UUID) -> URL {
        AppPaths.recordingsDirectory.appendingPathComponent("dictation_\(memoID.uuidString).m4a")
    }

    /// Kick off (or resume) transcription for a capture with pending dictation.
    /// Fire-and-forget from the drain; safe to call repeatedly.
    static func transcribe(memoID: UUID, repository: NotesRepository,
                           transcriber: any Transcriber = TranscriberFactory.make()) {
        guard !inFlight.contains(memoID) else { return }
        inFlight.insert(memoID)
        Task { @MainActor in
            defer { inFlight.remove(memoID) }
            await transcribeNow(memoID: memoID, repository: repository, transcriber: transcriber)
        }
    }

    /// Awaitable core (used directly by tests).
    static func transcribeNow(memoID: UUID, repository: NotesRepository,
                              transcriber: any Transcriber) async {
        let audioURL = pendingAudioURL(for: memoID)
        guard let memo = repository.memo(id: memoID) else {
            try? FileManager.default.removeItem(at: audioURL)
            return
        }
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            // Audio vanished (e.g. failed copy) — close out honestly rather than
            // leaving the memo stuck in .transcribing forever.
            memo.transcriptStatus = .done
            repository.save()
            return
        }

        memo.transcriptStatus = .transcribing
        repository.save()

        var result: TranscriptionResult?
        let delays = retryDelays.isEmpty ? [0] : retryDelays
        for delay in delays {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            if let attempt = try? await transcriber.transcribe(audioURL: audioURL, imageManifest: []) {
                result = attempt
                break
            }
        }

        guard let memo = repository.memo(id: memoID) else {
            try? FileManager.default.removeItem(at: audioURL)
            return
        }

        let text = (result?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            if result != nil {
                // Engine ran and heard nothing: honest no-text dictation. Consume
                // the audio and finish.
                memo.transcriptStatus = .done
                try? FileManager.default.removeItem(at: audioURL)
            } else {
                // Failed outright after retries — surface it (Error pill) and KEEP
                // the audio as the retry source; the next drain re-kicks it.
                memo.transcriptStatus = .failed
            }
            repository.save()
            return
        }

        let typed = (memo.annotationText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        memo.annotationText = typed.isEmpty ? text : typed + "\n\n" + text
        memo.transcriptStatus = .done
        repository.save()
        // Text landed — the audio has served its purpose (captures carry no
        // audio per C3; the annotation is the body).
        try? FileManager.default.removeItem(at: audioURL)
    }

    /// Re-kick any capture whose dictation never finished (crash mid-transcribe
    /// → stuck `.transcribing`; terminal failure → `.failed` with audio kept).
    /// Called from every inbox drain, so recovery rides app foreground.
    static func resumePending(repository: NotesRepository,
                              transcriber: any Transcriber = TranscriberFactory.make()) {
        for memo in repository.allMemos()
        where memo.audioFilename.isEmpty
            && (memo.transcriptStatus == .transcribing || memo.transcriptStatus == .failed)
            && FileManager.default.fileExists(atPath: pendingAudioURL(for: memo.id).path) {
            transcribe(memoID: memo.id, repository: repository, transcriber: transcriber)
        }
    }
}
