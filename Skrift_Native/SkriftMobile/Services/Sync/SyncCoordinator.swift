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
                // Standard audio memo path (byte-identical to pre-capture behaviour).
                guard let audioURL = memo.audioURL,
                      let audioData = try? Data(contentsOf: audioURL) else { continue }
                payload = UploadPayload.build(memo: memo, audioData: audioData, photos: loadPhotos(for: memo))
            }

            do {
                try await macTransport.uploadMemo(body: payload.body, contentType: payload.contentType)
                memo.syncStatus = .synced
                repository.save()
                newlySynced += 1
            } catch {
                // leave waiting; retried next sync
            }
        }
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
