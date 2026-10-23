import Foundation
import SwiftData

/// C245 / R34: the synced `MemoAsset`s that carry a recording's word timings (karaoke,
/// read-along) and its diarization (speaker turns, voice enrollment) — ONE definition of
/// their filenames and blob shapes for every device. The phone has always uploaded both; a
/// Mac take reached the phone with audio only, so karaoke never ran on a Mac recording.
/// Both apps write through here, so the two can never drift into different shapes.
enum TimingAssets {

    /// The phone's sidecar names (`WordTimingsStore`, `DiarizationStore` read these).
    static func wordTimingsFilename(for id: UUID) -> String { "wt_\(id.uuidString).json" }
    static func diarizationFilename(for id: UUID) -> String { "diar_\(id.uuidString).json" }

    /// `[WordTiming]` as the phone's `WordTimingsStore.write` encodes it.
    static func wordTimingsBlob(_ timings: [WordTiming]) -> Data? {
        timings.isEmpty ? nil : try? JSONEncoder().encode(timings)
    }

    /// The phone's `DiarizationData` wire shape: segments, slot → display name, and the slot of
    /// each turn in transcript order (optional, encoded only when known).
    struct Diarization: Codable, Equatable {
        var segments: [DiarizedSegment]
        var slotNames: [String: String]
        var turnSlots: [Int]? = nil
    }

    /// A diarization blob from segments plus the transcript's turn names (in order). When the
    /// turns line up with the segments' speaker runs, each slot takes its turn's name; else
    /// the slots read "Speaker N", as the phone labels an unnamed voice.
    static func diarization(segments: [DiarizedSegment], turnNames: [String]) -> Diarization? {
        guard Set(segments.map(\.speaker)).count >= 2 else { return nil }
        var runs: [Int] = []
        for s in segments.sorted(by: { $0.start < $1.start }) where runs.last != s.speaker { runs.append(s.speaker) }
        var names: [String: String] = [:]
        for slot in Set(segments.map(\.speaker)) { names[String(slot)] = "Speaker \(slot + 1)" }
        let aligned = runs.count == turnNames.count
        if aligned {
            for (slot, name) in zip(runs, turnNames) where names[String(slot)] == "Speaker \(slot + 1)" {
                names[String(slot)] = name
            }
        }
        return Diarization(segments: segments, slotNames: names, turnSlots: aligned ? runs : nil)
    }

    static func diarizationBlob(_ d: Diarization) -> Data? { try? JSONEncoder().encode(d) }

    /// Write `blob` as the memo's one asset of `kind` (replace in place, else insert). Does not
    /// save: the caller saves once.
    static func upsert(kind: String, filename: String, blob: Data, memoID: UUID, in ctx: ModelContext) {
        let existing = try? ctx.fetch(FetchDescriptor<MemoAsset>(
            predicate: #Predicate { $0.memoID == memoID && $0.kind == kind }))
        if let asset = existing?.first {
            asset.blob = blob
            asset.byteCount = blob.count
        } else {
            ctx.insert(MemoAsset(memoID: memoID, kind: kind, filename: filename, blob: blob))
        }
    }
}
