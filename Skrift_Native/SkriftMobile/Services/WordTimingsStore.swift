import Foundation

/// Per-memo word-timing sidecar (`recordings/wt_{uuid}.json`). Mirrors the RN
/// sidecar convention. Kept out of the SwiftData index so memo queries stay
/// cheap — these per-word arrays are only needed for karaoke playback.
struct WordTimingsStore {
    var directory: URL = AppPaths.recordingsDirectory

    /// The sidecar filename for a memo. Single source of the name — `AssetMaterializer`
    /// (Phase 1d) uses it to sync the sidecar across devices, so the two can't drift.
    static func filename(for id: UUID) -> String { "wt_\(id.uuidString).json" }

    private func fileURL(_ id: UUID) -> URL {
        directory.appendingPathComponent(Self.filename(for: id))
    }

    func write(_ timings: [WordTiming], for id: UUID) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(timings) else { return }
        try? data.write(to: fileURL(id))
    }

    func load(for id: UUID) -> [WordTiming]? {
        guard let data = try? Data(contentsOf: fileURL(id)) else { return nil }
        return try? JSONDecoder().decode([WordTiming].self, from: data)
    }

    func delete(for id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(id))
    }
}
