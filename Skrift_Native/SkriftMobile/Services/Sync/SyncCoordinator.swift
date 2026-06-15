import Foundation

/// Drives a full sync to the Mac, mirroring the RN `sync.ts` order:
///   1. names sync (bidirectional LWW) — when a Mac is configured
///   2. reconcile — mark memos the Mac already has (by filename) as synced
///   3. upload each remaining `waiting` memo with significance > 0 (flag-to-send)
///
/// **Flag-to-send gating:** only memos the user rated significant (`significance > 0`)
/// are uploaded — an unrated memo (significance 0) stays on the phone until flagged.
/// Memos whose audio file is missing are skipped (left `waiting`). A failed upload
/// leaves the memo `waiting` for the next run.
@MainActor
struct SyncCoordinator {
    var repository: NotesRepository = .shared
    var macTransport: any MacTransport = MacTransportFactory.make()
    var namesTransport: NamesTransport? = MacTransportFactory.makeNamesTransport()

    @discardableResult
    func syncAll() async -> Int {
        if let namesTransport {
            _ = await NamesSync(store: .shared, transport: namesTransport).run()
        }

        let eligible = repository.allMemos().filter { $0.syncStatus == .waiting && $0.significance > 0 }.count
        let paired = MacConnection.load()
        DevLog.log("sync: start — paired=\(paired.map { "\($0.host):\($0.port)" } ?? "none") eligible(waiting & sig>0)=\(eligible)")

        if let filenames = try? await macTransport.listFilenames(), !filenames.isEmpty {
            let known = Set(filenames)
            for memo in repository.allMemos() where memo.syncStatus == .waiting && known.contains(memo.audioFilename) {
                memo.syncStatus = .synced
            }
            repository.save()
        }

        var newlySynced = 0
        // Flag-to-send: skip unrated memos (significance 0) — they stay on the phone.
        for memo in repository.allMemos() where memo.syncStatus == .waiting && memo.significance > 0 {
            let payload: (body: Data, contentType: String)

            if memo.audioURL == nil {
                // Capture item: no audio. Use the C3 capture multipart path.
                // Guard: must have sharedContent (otherwise there's nothing to upload).
                guard memo.sharedContent != nil else { continue }
                // Hold while a dictated voice note is still transcribing — the
                // annotation IS the body for captures (the Mac has no audio to
                // fall back on), so uploading early would drop the spoken part.
                guard memo.transcriptStatus == .done else { continue }
                payload = UploadPayload.buildCapture(memo: memo, photos: loadPhotos(for: memo))
            } else {
                // Standard audio memo path. Attach the per-memo word-timings + (for a
                // diarized conversation) the diarization sidecar as OPTIONAL parts, so the
                // Mac can drive karaoke/read-along + enroll a speaker's voice without
                // re-transcribing. Absent when the memo has neither (byte-compatible).
                guard let audioURL = memo.audioURL,
                      let audioData = try? Data(contentsOf: audioURL) else { continue }
                let wtJSON = WordTimingsStore().load(for: memo.id).flatMap { try? JSONEncoder().encode($0) }
                let diarJSON = DiarizationStore().load(for: memo.id).flatMap { try? JSONEncoder().encode($0) }
                payload = UploadPayload.build(memo: memo, audioData: audioData, photos: loadPhotos(for: memo),
                                              wordTimingsJSON: wtJSON, diarizationJSON: diarJSON)
            }

            do {
                try await macTransport.uploadMemo(body: payload.body, contentType: payload.contentType)
                memo.syncStatus = .synced
                repository.save()
                newlySynced += 1
            } catch {
                // leave waiting; retried next sync (the transport already DevLog'd the why)
                DevLog.log("sync: memo \(memo.id) stays waiting — upload failed")
            }
        }
        DevLog.log("sync: done — newlySynced=\(newlySynced)")
        return newlySynced
    }

    private func loadPhotos(for memo: Memo) -> [(filename: String, data: Data)] {
        guard let manifest = memo.metadata?.imageManifest else { return [] }
        return manifest.compactMap { entry in
            let url = AppPaths.recordingsDirectory.appendingPathComponent(entry.filename)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return (entry.filename, data)
        }
    }
}
