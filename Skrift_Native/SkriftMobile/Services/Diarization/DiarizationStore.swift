import Foundation

/// A memo's diarization, persisted as a sidecar (`diar_<memoid>.json`): the speaker
/// time-ranges + the current name per slot. Lets the detail extract a speaker's audio
/// (to enroll their voice) when you name them — without re-diarizing.
struct DiarizationData: Codable {
    var segments: [DiarizedSegment]
    var slotNames: [String: String]   // slot index (as string) → current display name
}

struct DiarizationStore {
    var directory: URL = AppPaths.recordingsDirectory
    private func url(for id: UUID) -> URL { directory.appendingPathComponent("diar_\(id.uuidString).json") }

    func write(_ data: DiarizationData, for id: UUID) { try? JSONEncoder().encode(data).write(to: url(for: id)) }
    func load(for id: UUID) -> DiarizationData? {
        guard let d = try? Data(contentsOf: url(for: id)) else { return nil }
        return try? JSONDecoder().decode(DiarizationData.self, from: d)
    }
    func delete(for id: UUID) { try? FileManager.default.removeItem(at: url(for: id)) }
}
