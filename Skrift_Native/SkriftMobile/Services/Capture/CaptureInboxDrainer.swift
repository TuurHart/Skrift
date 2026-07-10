import Foundation
import SwiftData

/// Drains the CaptureInbox (written by the SkriftShare extension) into SwiftData
/// Memo objects.
///
/// **Crash-safety:** entries are deleted ONLY after the Memo is saved. If the process
/// dies between the save and the delete, the next drain re-creates the Memo. We dedup
/// with an explicit `repository.memo(id:)` check before inserting (below): when a memo
/// with the same UUID already exists we skip the insert and just delete the inbox entry.
/// (`Memo.id` is no longer `@Attribute(.unique)` — dropped for CloudKit-backed SwiftData
/// in standalone Phase 1; this explicit check is now the sole dedup.)
///
/// **Thread model:** must be called from the `@MainActor` (SkriftApp, scenePhase, .task).
/// All SwiftData writes require the main context.
@MainActor
enum CaptureInboxDrainer {

    /// Convert each pending inbox entry to a Memo and save. Idempotent: safe to call
    /// on every foreground transition. Also resumes any dictation transcription a
    /// previous run never finished (crash / terminal failure recovery).
    static func drain(into repository: NotesRepository) {
        defer { CaptureDictation.resumePending(repository: repository) }
        // Surface any share-extension diagnostics in the app devlog (the
        // extension can't write devlog.txt itself — round-1 mic mystery).
        CaptureInbox.flushExtLog { DevLog.log($0) }
        let pending = CaptureInbox.pendingEntries()
        guard !pending.isEmpty else { return }

        // Every share jumps to its note on the next app-open (signed 2026-07-10,
        // mock share-ingest-wave1.html) — collect the last created memo and fire
        // ONE bridge request after the loop (the bridge keeps most-recent-wins).
        var openTarget: UUID?
        defer { if let openTarget { MemoOpenBridge.shared.open(openTarget) } }

        for (entry, entryDir) in pending {
            let memoID = entry.id

            // Shared VIDEO → import as a normal voice memo (audio + a frame
            // thumbnail + transcribe), NOT a capture item. Copy it out of the
            // inbox, delete the entry FIRST (a re-drain must not double-import —
            // importVideo mints its OWN memo UUID, so the id-dup guard below
            // wouldn't catch it), then import from the app-owned temp.
            if entry.type == "video" {
                let src0 = CaptureInbox.videoURL(for: entry, entryDir: entryDir)
                DevLog.log("drain: video entry \(entry.id); src present=\(src0.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)")
                if let src = src0, FileManager.default.fileExists(atPath: src.path) {
                    let ext = src.pathExtension.isEmpty ? "mov" : src.pathExtension
                    let temp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("shared_import_\(entry.id.uuidString).\(ext)")
                    try? FileManager.default.removeItem(at: temp)
                    let copied = (try? FileManager.default.copyItem(at: src, to: temp)) != nil
                    DevLog.log("drain: video copied=\(copied) → \(temp.lastPathComponent); deleting entry + importing")
                    CaptureInbox.delete(entryDir: entryDir)
                    // Land the user on the imported memo: it relocates to the
                    // video's filming date, so otherwise it "vanishes" from the
                    // top of the list (user-confirmed via DevLog 2026-06-14).
                    if copied, let mid = MemoSaver().importVideo(from: temp) {
                        openTarget = mid
                    }
                } else {
                    DevLog.log("drain: video entry \(entry.id) — no src file, discarding")
                    CaptureInbox.delete(entryDir: entryDir)
                }
                continue
            }

            // Shared AUDIO (WhatsApp voice notes / Voice Memos / Files) → import as
            // a normal transcribed memo, NOT a capture item (the i4 fix — the url
            // branch used to win and save a LINK; a Files m4a became a dead file
            // card). One entry with N clip names = the B1 combine (clips merged in
            // order → one transcript); split notes arrive as N single-clip entries.
            // Same delete-first pattern as video: importAudioClips mints its own
            // memo UUID, so the id-dup guard below wouldn't catch a re-drain.
            if entry.type == "audio" {
                let srcs = CaptureInbox.audioURLs(for: entry, entryDir: entryDir)
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
                DevLog.log("drain: audio entry \(entry.id); clips present=\(srcs.count)/\(entry.audioFileNames?.count ?? 0)")
                if !srcs.isEmpty {
                    // Copy every clip to an app-owned temp BEFORE deleting the entry.
                    var temps: [URL] = []
                    for (i, src) in srcs.enumerated() {
                        let ext = src.pathExtension.isEmpty ? "m4a" : src.pathExtension
                        let temp = FileManager.default.temporaryDirectory
                            .appendingPathComponent("shared_import_\(entry.id.uuidString)_\(i).\(ext)")
                        try? FileManager.default.removeItem(at: temp)
                        if (try? FileManager.default.copyItem(at: src, to: temp)) != nil {
                            temps.append(temp)
                        }
                    }
                    // Oldest clip's original date (index-aligned array) → the memo's
                    // recordedAt seed; the import upgrades to the embedded asset
                    // date when one exists (round-1: memos dated to upload time).
                    let clipDate = entry.audioRecordedAts?.first.flatMap { ISO8601.date(from: $0) }
                    DevLog.log("drain: audio copied=\(temps.count) clip(s); dates=\(entry.audioRecordedAts ?? []); deleting entry + importing")
                    CaptureInbox.delete(entryDir: entryDir)
                    if let mid = MemoSaver(repository: repository).importAudioClips(from: temps, recordedAt: clipDate) {
                        // The sheet's significance circles apply to the imported memo.
                        if entry.significance > 0, let memo = repository.memo(id: mid) {
                            memo.significance = entry.significance
                            repository.save()
                        }
                        openTarget = mid
                    }
                } else {
                    DevLog.log("drain: audio entry \(entry.id) — no clip files, discarding")
                    CaptureInbox.delete(entryDir: entryDir)
                }
                continue
            }

            // Duplicate guard: if we already have this memo, just clean up.
            if repository.memo(id: memoID) != nil {
                CaptureInbox.delete(entryDir: entryDir)
                continue
            }

            // Build the SharedContent from the inbox entry.
            guard let contentType = ShareContentType(rawValue: entry.type) else {
                // Unknown type — discard the entry rather than leaving it forever.
                CaptureInbox.delete(entryDir: entryDir)
                continue
            }

            var sharedContent = SharedContent(
                type: contentType,
                url: entry.url,
                urlTitle: entry.urlTitle,
                text: entry.text,
                fileName: entry.imageFileName,
                mimeType: entry.mimeType
            )

            // File capture (e.g. a shared PDF): copy the document from the inbox into
            // the recordings dir under the memo UUID so it persists. We store the
            // RELATIVE filename in `filePath` (resolved against recordingsDirectory at
            // open time) so it survives reinstall — same rule as audio/photos.
            if contentType == .file,
               let srcURL = CaptureInbox.fileURL(for: entry, entryDir: entryDir),
               FileManager.default.fileExists(atPath: srcURL.path) {
                let ext = (entry.fileName.map { ($0 as NSString).pathExtension } ?? "")
                let destName = "file_\(memoID.uuidString).\(ext.isEmpty ? "pdf" : ext)"
                let destURL = AppPaths.recordingsDirectory.appendingPathComponent(destName)
                do {
                    try? FileManager.default.removeItem(at: destURL)
                    try FileManager.default.copyItem(at: srcURL, to: destURL)
                    sharedContent = SharedContent(type: .file, filePath: destName,
                                                  fileName: entry.fileDisplayName, mimeType: entry.mimeType)
                } catch {
                    print("[CaptureInboxDrainer] file copy failed: \(error)")
                }
            }

            // For image captures, move the image(s) from the inbox to the recordings
            // directory under the memo's UUID before saving the Memo — a multi-photo
            // share (B2) always lands as ONE memo with an N-entry manifest. Manifest
            // entries use offsetSeconds 0 (the capture has no timeline).
            var imageManifest: [ImageManifestEntry]?
            if contentType == .image {
                let srcURLs = CaptureInbox.imageURLs(for: entry, entryDir: entryDir)
                var manifest: [ImageManifestEntry] = []
                for (i, srcURL) in srcURLs.enumerated() where FileManager.default.fileExists(atPath: srcURL.path) {
                    // Destination: recordings dir, photo_<memoUUID>_00N.<ext>
                    let ext = srcURL.pathExtension
                    let destName = "photo_\(memoID.uuidString)_\(String(format: "%03d", i + 1)).\(ext.isEmpty ? "jpg" : ext)"
                    let destURL = AppPaths.recordingsDirectory.appendingPathComponent(destName)
                    do {
                        if FileManager.default.fileExists(atPath: destURL.path) {
                            try FileManager.default.removeItem(at: destURL)
                        }
                        try FileManager.default.copyItem(at: srcURL, to: destURL)
                        manifest.append(ImageManifestEntry(filename: destName, offsetSeconds: 0))
                    } catch {
                        // Image copy failed — save the capture with whatever images
                        // landed rather than abandoning the whole entry.
                        print("[CaptureInboxDrainer] image copy failed: \(error)")
                    }
                }
                if !manifest.isEmpty { imageManifest = manifest }
            }

            // Dictated voice note: move the audio to the app-owned pending spot
            // BEFORE the entry is deleted (crash between delete and transcription
            // must not lose the recording). The app transcribes it async after the
            // memo is saved; the memo shows .transcribing until the text lands.
            var hasDictation = false
            if let srcURL = CaptureInbox.dictationURL(for: entry, entryDir: entryDir),
               FileManager.default.fileExists(atPath: srcURL.path) {
                let destURL = CaptureDictation.pendingAudioURL(for: memoID)
                do {
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.copyItem(at: srcURL, to: destURL)
                    hasDictation = true
                } catch {
                    // Copy failed — save the capture without the voice note rather
                    // than abandoning the whole entry (same policy as images).
                    print("[CaptureInboxDrainer] dictation copy failed: \(error)")
                }
            }

            // Parse the sharedAt timestamp using the app's canonical formatter
            // (fractional-seconds UTC, matching JavaScript Date.toISOString() and the
            // Mac contract). Fall back to now() if the string is malformed.
            let recordedAt = ISO8601.date(from: entry.sharedAt) ?? Date()

            // Build MemoMetadata for image manifest (only populated for image captures).
            let metadata: MemoMetadata? = imageManifest.map { manifest in
                MemoMetadata(imageManifest: manifest)
            }

            let memo = Memo.make(
                id: memoID,
                audioFilename: "",          // no audio — the discriminator for capture items
                duration: 0,
                recordedAt: recordedAt,
                tags: [],
                syncStatus: .waiting,
                transcript: nil,
                // No ASR needed for the capture itself; a dictated voice note keeps
                // the memo .transcribing until its text lands (sync waits on .done).
                transcriptStatus: hasDictation ? .transcribing : .done,
                significance: entry.significance,
                metadata: metadata,
                sharedContent: sharedContent,
                annotationText: entry.annotationText?.isEmpty == false ? entry.annotationText : nil
            )

            repository.insert(memo)
            // Delete only AFTER the insert+save (repository.insert calls save()).
            CaptureInbox.delete(entryDir: entryDir)
            openTarget = memoID

            if hasDictation {
                CaptureDictation.transcribe(memoID: memoID, repository: repository)
            }
        }
    }
}
