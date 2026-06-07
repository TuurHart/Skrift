import Foundation

/// Per-memo word-timing sidecar (`recordings/wt_{uuid}.json`). Mirrors the RN
/// sidecar convention. Kept out of the SwiftData index so memo queries stay
/// cheap — these per-word arrays are only needed for karaoke playback.
struct WordTimingsStore {
    var directory: URL = AppPaths.recordingsDirectory

    private func fileURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("wt_\(id.uuidString).json")
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
