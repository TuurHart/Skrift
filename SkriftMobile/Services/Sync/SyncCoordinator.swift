import Foundation

/// Drives a full sync to the Mac, mirroring the RN `sync.ts` order:
///   1. names sync (bidirectional LWW) — when a Mac is configured
///   2. reconcile — mark memos the Mac already has (by filename) as synced
///   3. upload each remaining `waiting` memo (audio + metadata + transcript + photos)
///
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
        for memo in repository.allMemos() where memo.syncStatus == .waiting {
            guard let audioURL = memo.audioURL, let audioData = try? Data(contentsOf: audioURL) else { continue }
            let payload = UploadPayload.build(memo: memo, audioData: audioData, photos: loadPhotos(for: memo))
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
