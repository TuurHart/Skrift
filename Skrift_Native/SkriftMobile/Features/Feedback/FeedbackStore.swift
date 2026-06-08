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
/// transcribed then discarded — we keep the text.
@MainActor
final class FeedbackStore: ObservableObject {
    static let shared = FeedbackStore()

    @Published private(set) var items: [FeedbackItem] = []
    private let root: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.root = docs.appendingPathComponent("Feedback", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }

    var count: Int { items.count }

    func reload() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            items = []; return
        }
        items = entries
            .compactMap { url -> FeedbackItem? in
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }
                return FeedbackItem.load(from: url)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func save(transcript: String, note: String, screenshot: UIImage?, durationSeconds: Double) -> FeedbackItem {
        let id = UUID()
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var hasScreenshot = false
        if let img = screenshot, let pngData = img.pngData() {
            try? pngData.write(to: folder.appendingPathComponent("screenshot.png"))
            hasScreenshot = true
        }
        let metadata = FeedbackMetadata(createdAt: Date(), transcript: transcript, note: note,
                                        hasScreenshot: hasScreenshot, durationSeconds: durationSeconds, sentAt: nil)
        metadata.write(to: folder)
        reload()
        return items.first { $0.folder == folder } ?? FeedbackItem(folder: folder, metadata: metadata)
    }

    /// Mark an item emailed (persists `sentAt`). Idempotent.
    func markSent(_ item: FeedbackItem) {
        guard item.sentAt == nil else { return }
        var metadata = item.metadata
        metadata.sentAt = Date()
        metadata.write(to: item.folder)
        reload()
    }

    func delete(_ item: FeedbackItem) {
        try? FileManager.default.removeItem(at: item.folder)
        reload()
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

    private static let iso = ISO8601DateFormatter()

    private static func makeEncoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        enc.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer(); try c.encode(iso.string(from: date))
        }
        return enc
    }
    private static func makeDecoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer(); return iso.date(from: try c.decode(String.self)) ?? Date()
        }
        return dec
    }

    static func load(from folder: URL) -> FeedbackMetadata? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("metadata.json")) else { return nil }
        return try? makeDecoder().decode(FeedbackMetadata.self, from: data)
    }
    func write(to folder: URL) {
        guard let data = try? Self.makeEncoder().encode(self) else { return }
        try? data.write(to: folder.appendingPathComponent("metadata.json"))
    }
}

struct FeedbackItem: Identifiable, Hashable {
    let folder: URL
    let metadata: FeedbackMetadata

    var id: URL { folder }
    var createdAt: Date { metadata.createdAt }
    var transcript: String { metadata.transcript }
    var note: String { metadata.note }
    var hasScreenshot: Bool { metadata.hasScreenshot }
    var durationSeconds: Double { metadata.durationSeconds }
    var sentAt: Date? { metadata.sentAt }
    var isSent: Bool { metadata.sentAt != nil }
    var screenshotURL: URL { folder.appendingPathComponent("screenshot.png") }
    var screenshotImage: UIImage? { hasScreenshot ? UIImage(contentsOfFile: screenshotURL.path) : nil }

    static func load(from folder: URL) -> FeedbackItem? {
        guard let metadata = FeedbackMetadata.load(from: folder) else { return nil }
        return FeedbackItem(folder: folder, metadata: metadata)
    }
    static func == (lhs: FeedbackItem, rhs: FeedbackItem) -> Bool { lhs.folder == rhs.folder && lhs.sentAt == rhs.sentAt }
    func hash(into hasher: inout Hasher) { hasher.combine(folder) }
}
