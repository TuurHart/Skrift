import Foundation

/// What ObsidianPublisher last wrote for a memo. Gives two guarantees:
/// - **Sticky path** — re-export overwrites the SAME file even after the memo is renamed
///   (single owner per file → no `note 2.md` conflict copies).
/// - **Content-hash idempotency** — an unchanged memo is skipped (no needless vault churn).
struct ExportRecord: Codable, Equatable {
    var relativePath: String
    var contentHash: String
    var exportedAt: Date
    /// Set once Skrift detects the user edited this exported file in their vault. From then on
    /// Skrift NEVER overwrites it (the note is theirs); deleting the vault file lets a fresh
    /// export recreate it. The edit-guard floor — see `ObsidianPublisher.publish`.
    var userEdited: Bool

    init(relativePath: String, contentHash: String, exportedAt: Date, userEdited: Bool = false) {
        self.relativePath = relativePath
        self.contentHash = contentHash
        self.exportedAt = exportedAt
        self.userEdited = userEdited
    }

    // Back-compat decode: an older state file without `userEdited` reads as false (synthesized
    // Decodable would otherwise reject the missing key).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        relativePath = try c.decode(String.self, forKey: .relativePath)
        contentHash = try c.decode(String.self, forKey: .contentHash)
        exportedAt = try c.decode(Date.self, forKey: .exportedAt)
        userEdited = (try? c.decode(Bool.self, forKey: .userEdited)) ?? false
    }

    enum CodingKeys: String, CodingKey { case relativePath, contentHash, exportedAt, userEdited }
}

/// Per-device record of what's been published to the Obsidian vault, keyed by memo id.
///
/// **Local-only, NOT CloudKit-synced** — each device has its own vault bookmark, so "exported
/// here" is a per-device fact (syncing it would falsely mark a memo exported on a device whose
/// vault never received it). This is why export state is a small local JSON, not a `Memo` field
/// or a synced `@Model` (which also keeps it off the hot `Memo` schema). Used from the publish
/// flow (typically the main actor).
final class ExportStateStore {
    static let shared = ExportStateStore()

    private let fileURL: URL
    private var cache: [String: ExportRecord]

    init(fileURL: URL = AppPaths.documentsDirectory.appendingPathComponent("skrift_export_state.json")) {
        self.fileURL = fileURL
        self.cache = Self.read(fileURL)
    }

    func record(for memoID: UUID) -> ExportRecord? { cache[memoID.uuidString] }

    func set(_ record: ExportRecord, for memoID: UUID) {
        cache[memoID.uuidString] = record
        persist()
    }

    func remove(for memoID: UUID) {
        guard cache.removeValue(forKey: memoID.uuidString) != nil else { return }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func read(_ url: URL) -> [String: ExportRecord] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: ExportRecord].self, from: data) else { return [:] }
        return decoded
    }
}
