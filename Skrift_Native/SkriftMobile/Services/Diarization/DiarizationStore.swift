import Foundation

/// A memo's diarization, persisted as a sidecar (`diar_<memoid>.json`): the speaker
/// time-ranges + the current name per slot. Lets the detail extract a speaker's audio
/// (to enroll their voice) when you name them — without re-diarizing.
struct DiarizationData: Codable {
    var segments: [DiarizedSegment]
    var slotNames: [String: String]   // slot index (as string) → current display name
    /// The diarization SLOT of each turn in transcript order (turn i → slot). Lets a
    /// rename/enroll target ONE speaker even when two slots share a display name (e.g.
    /// the same voice split into two slots, both auto-labelled "Tiuri"). Optional +
    /// `encodeIfPresent` → byte-compatible with older sidecars/uploads (decodes nil).
    var turnSlots: [Int]? = nil
}

struct DiarizationStore {
    var directory: URL = AppPaths.recordingsDirectory
    /// The sidecar filename for a memo. Single source of the name — `AssetMaterializer`
    /// (Phase 1d) uses it to sync the sidecar across devices, so the two can't drift.
    static func filename(for id: UUID) -> String { "diar_\(id.uuidString).json" }
    private func url(for id: UUID) -> URL { directory.appendingPathComponent(Self.filename(for: id)) }

    func write(_ data: DiarizationData, for id: UUID) { try? JSONEncoder().encode(data).write(to: url(for: id)) }
    func load(for id: UUID) -> DiarizationData? {
        guard let d = try? Data(contentsOf: url(for: id)) else { return nil }
        return try? JSONDecoder().decode(DiarizationData.self, from: d)
    }
    func delete(for id: UUID) { try? FileManager.default.removeItem(at: url(for: id)) }
}
