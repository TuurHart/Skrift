import Foundation

// MARK: - Inbox entry (shared type, compiled into both app + extension targets)

/// One capture item written by the share extension into the App Group container
/// and read by the main app when it comes to the foreground.
///
/// The shape is intentionally flat (no nested Codable structs) so JSONEncoder /
/// JSONDecoder never runs into the SwiftData nested-struct trap, even though this
/// type is NOT a SwiftData model.
struct CaptureInboxEntry: Codable {
    /// Stable ID for idempotent drain (write once, delete only after Memo is saved).
    let id: UUID
    /// Mirrors `SharedContent.type` raw value: "url" | "text" | "image" | "file".
    let type: String
    /// URL string for url-type captures.
    let url: String?
    /// Page title from the share payload (no network fetch).
    let urlTitle: String?
    /// Plain-text content for text-type captures.
    let text: String?
    /// Filename (relative to the inbox folder) for the accompanying image, when type == "image".
    let imageFileName: String?
    /// MIME type for image captures, e.g. "image/jpeg".
    let mimeType: String?
    /// User-typed annotation from the share sheet (may be nil / empty).
    let annotationText: String?
    /// Significance rating (0–1, 0.1 steps) set in the share sheet.
    let significance: Double
    /// ISO8601 timestamp when the share action completed.
    let sharedAt: String
    /// Filename (relative to the entry folder) of a dictated voice note, when the
    /// user recorded one in the sheet. The EXTENSION only records — Parakeet can't
    /// fit in the extension's memory ceiling, so the MAIN APP transcribes it on
    /// drain and appends the text to `annotationText` (audio discarded after).
    /// Optional so entries written by older builds keep decoding.
    var dictationFileName: String? = nil
    /// Filename (relative to the entry folder) of a shared VIDEO (a movie shared
    /// from Photos/Files). The MAIN APP imports it on drain via
    /// `MemoSaver.importVideo` — it becomes a normal voice memo (audio + a frame
    /// thumbnail + transcribe), NOT a capture item. Optional so older entries decode.
    var videoFileName: String? = nil
    /// Filename (relative to the entry folder) of a shared AUDIO file (WhatsApp
    /// voice note / Voice Memos / Files). The MAIN APP imports it on drain via
    /// `MemoSaver.importAudio` — a normal transcribed memo, NOT a capture item
    /// (the i4 fix; was a link/file card). Optional so older entries decode.
    var audioFileName: String? = nil
    /// Filename (relative to the entry folder) of a shared DOCUMENT (e.g. a PDF
    /// shared from Files/Books). The MAIN APP persists it into the recordings dir on
    /// drain → a `.file` capture. Optional so older entries decode.
    var fileName: String? = nil
    /// The document's original display name (e.g. "report.pdf"), shown in the capture
    /// detail. Distinct from `fileName` (the UUID-keyed stored name).
    var fileDisplayName: String? = nil
}

// MARK: - Inbox

/// Manages the capture-inbox folder inside the App Group shared container.
///
/// The inbox is a folder of JSON+image pairs, one sub-folder per entry:
///   `<group>/CaptureInbox/<uuid>/entry.json`
///   `<group>/CaptureInbox/<uuid>/<imageFileName>` (image captures only)
///
/// **Thread safety:** all methods are synchronous and safe to call from any
/// thread/actor — they only do file I/O and contain no shared mutable state.
/// The drain path is always called @MainActor (in SkriftApp).
enum CaptureInbox {
    // MARK: - Group ID

    /// Read the App Group identifier from the bundle's Info.plist key
    /// `SkriftAppGroup`.  Both the app and the extension Info.plist carry this
    /// key with value `$(SKRIFT_APP_GROUP)`, which is substituted at build time
    /// (Debug → "group.com.skrift.mobile.dev", Release → "group.com.skrift.mobile").
    /// This avoids hard-coding the group ID in source — one build setting to flip.
    static var appGroupID: String {
        // Try the bundle that owns this call (app or extension).
        if let id = Bundle.main.object(forInfoDictionaryKey: "SkriftAppGroup") as? String,
           !id.isEmpty {
            return id
        }
        // Fallback: derive from the bundle ID's dev/prod split. NO assertionFailure
        // here — this runs at app LAUNCH (the inbox drain), and a Debug-build trap
        // on a missing plist key took the whole app down on the simulator (every
        // UI test failed "app is not running"). A wrong group just means an empty
        // inbox, which is recoverable; crashing at launch is not.
        let dev = (Bundle.main.bundleIdentifier ?? "").contains(".dev")
        return dev ? "group.com.skrift.mobile.dev" : "group.com.skrift.mobile"
    }

    // MARK: - Container

    /// Root of the shared App Group container.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// `<group>/CaptureInbox/` — created on first access.
    static var inboxURL: URL? {
        guard let base = containerURL else { return nil }
        let dir = base.appendingPathComponent("CaptureInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Write (called by the share extension)

    /// Write a capture entry to the inbox.  For image captures, `imageData` must
    /// be non-nil and `entry.imageFileName` must be set; for dictated captures,
    /// `dictationData` must be non-nil and `entry.dictationFileName` set.
    ///
    /// Crash-safe: the file is written atomically (write to a tmp file, then
    /// rename) — a crash mid-write leaves the old entry intact or no entry at all,
    /// never a half-written JSON.
    @discardableResult
    static func write(_ entry: CaptureInboxEntry, imageData: Data? = nil, dictationData: Data? = nil,
                      videoFileURL: URL? = nil, fileSourceURL: URL? = nil,
                      audioFileURL: URL? = nil) -> Bool {
        guard let inbox = inboxURL else { return false }
        let entryDir = inbox.appendingPathComponent(entry.id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: entryDir, withIntermediateDirectories: true)
            // Write the payload files first (if any) so that if the JSON write
            // crashes, the orphaned dir gets cleaned up on the next drain pass.
            if let imageData, let name = entry.imageFileName {
                let imageURL = entryDir.appendingPathComponent(name)
                try imageData.write(to: imageURL, options: .atomic)
            }
            if let dictationData, let name = entry.dictationFileName {
                let audioURL = entryDir.appendingPathComponent(name)
                try dictationData.write(to: audioURL, options: .atomic)
            }
            // Shared video: COPY the movie file (never load it into memory — a
            // video can be hundreds of MB, well past the extension's memory ceiling).
            if let videoFileURL, let name = entry.videoFileName {
                let destURL = entryDir.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.copyItem(at: videoFileURL, to: destURL)
            }
            // Shared audio (voice note): COPY the file in (same memory rationale as video).
            if let audioFileURL, let name = entry.audioFileName {
                let destURL = entryDir.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.copyItem(at: audioFileURL, to: destURL)
            }
            // Shared document (PDF/etc.): COPY the file in (same memory rationale as video).
            if let fileSourceURL, let name = entry.fileName {
                let destURL = entryDir.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.copyItem(at: fileSourceURL, to: destURL)
            }
            // Atomic JSON write.
            let data = try JSONEncoder().encode(entry)
            let jsonURL = entryDir.appendingPathComponent("entry.json")
            try data.write(to: jsonURL, options: .atomic)
            return true
        } catch {
            // Non-fatal: the app will just not drain this entry. Log and continue.
            print("[CaptureInbox] write failed: \(error)")
            return false
        }
    }

    // MARK: - Read (called by the app drain)

    /// Return all pending inbox entries (newest-first by filename sort is fine —
    /// `sharedAt` carries the canonical timestamp for ordering). Entries with a
    /// missing or corrupt JSON are skipped (stale partial writes).
    static func pendingEntries() -> [(entry: CaptureInboxEntry, entryDir: URL)] {
        guard let inbox = inboxURL else { return [] }
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: inbox,
                                                      includingPropertiesForKeys: nil,
                                                      options: .skipsHiddenFiles) else { return [] }
        return dirs.compactMap { dir in
            let jsonURL = dir.appendingPathComponent("entry.json")
            guard let data = try? Data(contentsOf: jsonURL),
                  let entry = try? JSONDecoder().decode(CaptureInboxEntry.self, from: data)
            else { return nil }
            return (entry, dir)
        }
    }

    /// Resolve the on-disk URL of the image for an image-type entry.
    static func imageURL(for entry: CaptureInboxEntry, entryDir: URL) -> URL? {
        guard let name = entry.imageFileName else { return nil }
        return entryDir.appendingPathComponent(name)
    }

    /// Resolve the on-disk URL of the dictated voice note, when present.
    static func dictationURL(for entry: CaptureInboxEntry, entryDir: URL) -> URL? {
        guard let name = entry.dictationFileName else { return nil }
        return entryDir.appendingPathComponent(name)
    }

    /// Resolve the on-disk URL of a shared video, when present.
    static func videoURL(for entry: CaptureInboxEntry, entryDir: URL) -> URL? {
        guard let name = entry.videoFileName else { return nil }
        return entryDir.appendingPathComponent(name)
    }

    /// Resolve the on-disk URL of a shared document (PDF/etc.), when present.
    static func fileURL(for entry: CaptureInboxEntry, entryDir: URL) -> URL? {
        guard let name = entry.fileName else { return nil }
        return entryDir.appendingPathComponent(name)
    }

    /// Resolve the on-disk URL of a shared audio file, when present.
    static func audioURL(for entry: CaptureInboxEntry, entryDir: URL) -> URL? {
        guard let name = entry.audioFileName else { return nil }
        return entryDir.appendingPathComponent(name)
    }

    // MARK: - Delete (called by the drain, only AFTER the Memo is saved)

    /// Remove an entry directory (JSON + image if any) from the inbox.
    /// Called only after the Memo has been successfully inserted into SwiftData —
    /// order matters for crash safety: drain is idempotent, so a missed delete
    /// just re-creates the memo on next foreground (which the drainer dedups via an
    /// explicit `NotesRepository.memo(id:)` check before inserting — `Memo.id` is no
    /// longer `@Attribute(.unique)`, dropped for CloudKit-backed SwiftData; see Memo.swift).
    static func delete(entryDir: URL) {
        try? FileManager.default.removeItem(at: entryDir)
    }
}
