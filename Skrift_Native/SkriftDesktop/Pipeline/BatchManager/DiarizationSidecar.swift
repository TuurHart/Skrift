import Foundation
import os

/// A memo's diarization, persisted as a per-file sidecar (`diar_<id>.json`) inside the
/// working folder, next to `original.<ext>` / `word_timings` / `images/`. Byte-mirrors the
/// phone's `DiarizationData` (`Skrift_Native/SkriftMobile/Services/Diarization/DiarizationStore.swift`)
/// so the two apps' sidecars are interchangeable: the speaker time-ranges + the current
/// display name per slot.
///
/// WHY persist this: the Mac DISCARDED its diarization output after re-emitting the
/// `**[[Person]]:**` / `**Speaker N:**` turns. To later ENROLL a speaker's voice from the
/// Mac review screen we need that speaker's segments (to slice their audio out of the
/// recording and embed it via `DiarizationService.embedSpeaker(audioURL:segments:slot:)`)
/// WITHOUT re-diarizing. Pure file I/O — no engine deps — so it's covered by the host-less
/// test target.
struct DiarizationData: Codable, Equatable {
    var segments: [DiarizedSegment]
    /// Slot index (as a string, mirroring the phone's JSON keys) → current display name.
    var slotNames: [String: String]

    init(segments: [DiarizedSegment], slotNames: [String: String]) {
        self.segments = segments
        self.slotNames = slotNames
    }

    /// Build from a `DiarizationOutput` — converts the `[Int: String]` slot map to the
    /// string-keyed JSON form the phone sidecar uses.
    init(_ output: DiarizationOutput) {
        self.segments = output.segments
        self.slotNames = Dictionary(uniqueKeysWithValues: output.slotNames.map { (String($0.key), $0.value) })
    }
}

/// Reads/writes `diar_<id>.json` sidecars in a working folder. Mirrors the phone's
/// `DiarizationStore`, but keyed by the PipelineFile id (which the on-disk folder embeds).
struct DiarizationSidecar {
    /// Sidecar I/O failures show up in Console.app / `log stream --predicate
    /// 'subsystem == "com.skrift.desktop"'` — a silent write failure here would
    /// quietly cost the portable copy of the segments.
    private static let log = Logger(subsystem: "com.skrift.desktop", category: "diarization")

    private func url(in folder: URL, id: String) -> URL {
        folder.appendingPathComponent("diar_\(id).json")
    }

    /// The working folder for a PipelineFile = the directory holding its `original.<ext>`
    /// (`pf.path`). Falls back to the path itself if it has no parent component.
    static func workingFolder(for pf: PipelineFile) -> URL {
        URL(fileURLWithPath: pf.path).deletingLastPathComponent()
    }

    func write(_ data: DiarizationData, in folder: URL, id: String) {
        do {
            try JSONEncoder().encode(data).write(to: url(in: folder, id: id))
        } catch {
            // Not fatal — the SwiftData copy (pf.diarizationSegments) still holds the
            // segments — but never silent: the sidecar is the portability/enroll copy.
            Self.log.error("diar sidecar write failed for \(id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    func load(in folder: URL, id: String) -> DiarizationData? {
        guard let d = try? Data(contentsOf: url(in: folder, id: id)) else { return nil }
        return try? JSONDecoder().decode(DiarizationData.self, from: d)
    }

    func delete(in folder: URL, id: String) {
        let target = url(in: folder, id: id)
        guard FileManager.default.fileExists(atPath: target.path) else { return }   // nothing to delete
        do {
            try FileManager.default.removeItem(at: target)
        } catch {
            Self.log.error("diar sidecar delete failed for \(id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
