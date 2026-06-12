import Foundation
import SwiftData

/// Drains the CaptureInbox (written by the SkriftShare extension) into SwiftData
/// Memo objects.
///
/// **Crash-safety:** entries are deleted ONLY after the Memo is saved. If the process
/// dies between the save and the delete, the next drain re-creates the Memo. SwiftData's
/// `@Attribute(.unique)` on `Memo.id` lets us detect duplicates: when a memo with the
/// same UUID already exists we skip the insert and just delete the inbox entry.
///
/// **Thread model:** must be called from the `@MainActor` (SkriftApp, scenePhase, .task).
/// All SwiftData writes require the main context.
@MainActor
enum CaptureInboxDrainer {

    /// Convert each pending inbox entry to a Memo and save. Idempotent: safe to call
    /// on every foreground transition.
    static func drain(into repository: NotesRepository) {
        let pending = CaptureInbox.pendingEntries()
        guard !pending.isEmpty else { return }

        for (entry, entryDir) in pending {
            let memoID = entry.id

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

            let sharedContent = SharedContent(
                type: contentType,
                url: entry.url,
                urlTitle: entry.urlTitle,
                text: entry.text,
                fileName: entry.imageFileName,
                mimeType: entry.mimeType
            )

            // For image captures, move the image from the inbox to the recordings
            // directory under the memo's UUID before saving the Memo. The image
            // manifest entry uses offsetSeconds 0 (the capture has no timeline).
            var imageManifest: [ImageManifestEntry]?
            if contentType == .image,
               let srcURL = CaptureInbox.imageURL(for: entry, entryDir: entryDir),
               let imageFileName = entry.imageFileName {

                // Destination: recordings dir, photo_<memoUUID>_001.<ext>
                let ext = (imageFileName as NSString).pathExtension
                let destName = "photo_\(memoID.uuidString)_001.\(ext.isEmpty ? "jpg" : ext)"
                let destURL = AppPaths.recordingsDirectory.appendingPathComponent(destName)
                do {
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.copyItem(at: srcURL, to: destURL)
                    imageManifest = [ImageManifestEntry(filename: destName, offsetSeconds: 0)]
                } catch {
                    // Image copy failed — save the capture without the image rather
                    // than abandoning the whole entry.
                    print("[CaptureInboxDrainer] image copy failed: \(error)")
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

            let memo = Memo(
                id: memoID,
                audioFilename: "",          // no audio — the discriminator for capture items
                duration: 0,
                recordedAt: recordedAt,
                tags: [],
                syncStatus: .waiting,
                transcript: nil,
                transcriptStatus: .done,    // no ASR needed; annotation is the body
                significance: entry.significance,
                metadata: metadata,
                sharedContent: sharedContent,
                annotationText: entry.annotationText?.isEmpty == false ? entry.annotationText : nil
            )

            repository.insert(memo)
            // Delete only AFTER the insert+save (repository.insert calls save()).
            CaptureInbox.delete(entryDir: entryDir)
        }
    }
}
