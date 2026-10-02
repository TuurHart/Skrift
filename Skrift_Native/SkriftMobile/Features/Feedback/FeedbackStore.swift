import Foundation
import UIKit

/// File-based feedback storage, ported from the user's Shhhcribble app. Each item
/// lives at `Documents/Feedback/<uuid>/`:
///
///     metadata.json   { createdAt, transcript, note, hasScreenshot, durationSeconds, sentAt? }
///     screenshot.png  (optional — pasted from the clipboard)
///
/// `sentAt` tracks whether the item was emailed (nil = draft). File-based on purpose
/// (short-lived items, direct external access, no SwiftData migration risk). Audio is
/// transcribed then discarded — we keep the text. The on-disk layout and field names are
/// read over USB by `.claude/skills/pull-phone-feedback`; do not rename them.
enum FeedbackStore {
    private static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Feedback", isDirectory: true)
    }

    /// Write a new item folder and return it.
    static func save(transcript: String, note: String, screenshot: UIImage?, durationSeconds: Double) -> FeedbackItem {
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var hasScreenshot = false
        if let img = screenshot, let pngData = img.pngData() {
            try? pngData.write(to: folder.appendingPathComponent("screenshot.png"))
            hasScreenshot = true
        }
        let metadata = FeedbackMetadata(createdAt: Date(), transcript: transcript, note: note,
                                        hasScreenshot: hasScreenshot, durationSeconds: durationSeconds, sentAt: nil)
        metadata.write(to: folder)
        return FeedbackItem(folder: folder, metadata: metadata)
    }

    /// Mark an item emailed (persists `sentAt`). Idempotent.
    static func markSent(_ item: FeedbackItem) {
        guard item.sentAt == nil else { return }
        var metadata = item.metadata
        metadata.sentAt = Date()
        metadata.write(to: item.folder)
    }
}

/// On-disk schema for `metadata.json` (ISO8601 dates so items stay readable).
struct FeedbackMetadata: Codable {
    let createdAt: Date
    let transcript: String
    let note: String
    let hasScreenshot: Bool
    let durationSeconds: Double
    var sentAt: Date?

    func write(to folder: URL) {
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(self) else { return }
        try? data.write(to: folder.appendingPathComponent("metadata.json"))
    }
}

struct FeedbackItem: Identifiable {
    let folder: URL
    let metadata: FeedbackMetadata

    var id: URL { folder }
    var createdAt: Date { metadata.createdAt }
    var transcript: String { metadata.transcript }
    var note: String { metadata.note }
    var sentAt: Date? { metadata.sentAt }
}
