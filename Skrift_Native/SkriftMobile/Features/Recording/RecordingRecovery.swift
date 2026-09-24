import AVFoundation
import Foundation

/// The launch sweep that turns a take the process never finished into a note
/// (C99/D26), and cleans up what cannot be recovered (C288).
extension MemoSaver {
    /// The title a rebuilt note carries, so the user sees it was recovered.
    nonisolated static let recoveredTitle = "Recovered recording (the app closed mid-take)"

    struct RecordingSweepReport: Equatable {
        /// Notes rebuilt from a dead take, oldest take first.
        var recovered: [UUID] = []
        /// Take ids whose files held no readable audio: moved to
        /// `QuarantinedRecordings` (never deleted — C288/C99, an m4a with no moov
        /// atom is often rescuable) and out of this directory, so the name still
        /// means "gone from the recordings dir", just not "gone from disk".
        var cleaned: [String] = []
        /// Take ids whose audio was readable but could not be rebuilt this time;
        /// their files stay for the next launch.
        var kept: [String] = []
    }

    /// Sidecar written next to a quarantined take's files, so a later rescue
    /// (`tools/rescue-lost-recordings.py`) or explicit user action can identify it.
    struct QuarantinedTakeSidecar: Codable {
        var take: String
        var firstSeen: Date
        /// Filename -> byte size, as quarantined.
        var fileSizes: [String: Int]
    }

    /// Sweep `directory` for takes left behind by an earlier process run: every
    /// `rec_ckpt_*` marker, and any `rec_tmp_*` / `rec_seg_*` file with no marker.
    /// A take with readable audio becomes a new note (`.transcribing`, titled
    /// `recoveredTitle`, dated when the take started) that the launch
    /// transcription recovery picks up; a take with none is quarantined.
    ///
    /// Never touches an existing memo: a rebuilt take always becomes a NEW note,
    /// so an append that died mid-take cannot run over the note it was appending
    /// to (C263). Takes owned by THIS process run (a live recording) are skipped.
    @discardableResult
    func recoverInterruptedRecordings(directory: URL = AppPaths.recordingsDirectory) async -> RecordingSweepReport {
        var report = RecordingSweepReport()
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []

        // Group every take file by take id.
        var takes: [String: RecordingMarker?] = [:]
        for name in names {
            if let take = Self.takeID(fromMarker: name) {
                let url = directory.appendingPathComponent(name)
                let marker = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(RecordingMarker.self, from: $0) }
                takes[take] = .some(marker)
            } else if let take = Self.takeID(fromAudio: name), takes[take] == nil {
                takes[take] = .some(nil)
            }
        }

        let ordered = takes.keys.sorted { a, b in
            let da = takes[a]??.startedAt ?? Self.creationDate(take: a, in: directory)
            let db = takes[b]??.startedAt ?? Self.creationDate(take: b, in: directory)
            return da < db
        }

        for take in ordered {
            let marker = takes[take] ?? nil
            if marker?.sessionID == RecordingCheckpoint.currentSessionID { continue }   // live take
            // A marker-less file of a take that is recording right now in this run
            // would have a marker from this run — re-check on disk, not the snapshot.
            if marker == nil,
               let live = Self.liveMarker(take: take, in: directory),
               live.sessionID == RecordingCheckpoint.currentSessionID { continue }

            let sources = Self.recoverableSources(take: take, marker: marker, in: directory)
            let files = RecordingCheckpoint.takeFiles(take: take, in: directory)
            guard !sources.isEmpty else {
                Self.quarantine(take: take, files: files, in: directory)
                report.cleaned.append(take)
                RecordingLifecycleLog.log("rec quarantined", "take=\(take) no readable audio — quarantined \(files.count) file(s)")
                continue
            }
            let startedAt = marker?.startedAt ?? Self.creationDate(take: take, in: directory)
            guard let id = await rebuildNote(from: sources, recordedAt: startedAt) else {
                report.kept.append(take)
                RecordingLifecycleLog.log("recover-deferred", "take=\(take) rebuild failed — files kept for the next launch")
                continue
            }
            // Only reached once rebuildNote has merged the audio into the new
            // memo's file, verified it opens with frames, and inserted + SAVED
            // the note to the repository (see rebuildNote below) — so the
            // original take files are only discarded after the new note's
            // audio exists on disk and is recorded in the store.
            RecordingCheckpoint.discardTakeFiles(take: take, in: directory)
            report.recovered.append(id)
            RecordingLifecycleLog.log("recovered", "take=\(take) memo=\(id) sources=\(sources.count)"
                                      + " finalized=\(marker?.finalized ?? false)")
        }
        return report
    }

    /// The audio to rebuild a take from, in order. A cleanly closed main file
    /// wins; otherwise every readable segment (listed ones first, then any the
    /// marker never got to list); otherwise a readable main file on its own.
    nonisolated static func recoverableSources(take: String, marker: RecordingMarker?, in directory: URL) -> [URL] {
        let main = directory.appendingPathComponent(RecordingCheckpoint.mainFilename(take: take))
        if marker?.finalized == true, RecordingCheckpoint.isReadableAudio(main) { return [main] }
        let listed = marker?.segments ?? []
        let onDisk = RecordingCheckpoint.takeFiles(take: take, in: directory).filter { $0.hasPrefix("rec_seg_") }
        let unlisted = onDisk.filter { !listed.contains($0) }.sorted()
        let segments = (listed + unlisted)
            .map { directory.appendingPathComponent($0) }
            .filter(RecordingCheckpoint.isReadableAudio)
        if !segments.isEmpty { return segments }
        return RecordingCheckpoint.isReadableAudio(main) ? [main] : []
    }

    /// Merge `sources` into a new `memo_<id>.m4a` and insert the note. nil when
    /// the audio could not be written.
    private func rebuildNote(from sources: [URL], recordedAt: Date) async -> UUID? {
        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"
        let dest = AppPaths.recordingsDirectory.appendingPathComponent(filename)
        do {
            try await Task.detached(priority: .userInitiated) {
                try MemoSaver.mergeAudioSync(sources: sources, to: dest)
            }.value
        } catch {
            RecordingCheckpoint.discardIfExists(dest)
            return nil
        }
        guard let f = try? AVAudioFile(forReading: dest), f.length > 0 else {
            RecordingCheckpoint.discardIfExists(dest)
            return nil
        }
        let duration = Double(f.length) / f.fileFormat.sampleRate
        repository.insert(Memo.make(
            id: id,
            audioFilename: filename,
            duration: duration,
            recordedAt: recordedAt,
            syncStatus: .waiting,
            title: Self.recoveredTitle,
            transcriptStatus: .transcribing
        ))
        repository.save()
        return id
    }

    nonisolated static func takeID(fromMarker name: String) -> String? {
        guard name.hasPrefix("rec_ckpt_"), name.hasSuffix(".json") else { return nil }
        return String(name.dropFirst("rec_ckpt_".count).dropLast(".json".count))
    }

    /// Take id of a `rec_tmp_<take>.m4a` or `rec_seg_<take>_<NNN>.m4a` file.
    nonisolated static func takeID(fromAudio name: String) -> String? {
        guard name.hasSuffix(".m4a") else { return nil }
        if name.hasPrefix("rec_tmp_") {
            return String(name.dropFirst("rec_tmp_".count).dropLast(".m4a".count))
        }
        if name.hasPrefix("rec_seg_") {
            let body = name.dropFirst("rec_seg_".count).dropLast(".m4a".count)
            guard let us = body.lastIndex(of: "_") else { return nil }
            return String(body[..<us])
        }
        return nil
    }

    /// `QuarantinedRecordings`, a sibling of the swept recordings directory (in
    /// production: `Documents/QuarantinedRecordings`, beside `Documents/recordings`).
    /// A sibling, not a subfolder, so the next sweep's directory listing never
    /// sees a quarantined take again.
    nonisolated static func quarantineDirectory(besideRecordings directory: URL) -> URL {
        let dir = directory.deletingLastPathComponent().appendingPathComponent("QuarantinedRecordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Move every file of an unrecoverable take out of `directory` and into
    /// quarantine, with a sidecar JSON (take id, each file's size, first-seen
    /// date) — the take's own audio is only ever moved, never deleted (C288/C99).
    /// A move that fails leaves the source file where it was, so the next sweep
    /// sees it again.
    private static func quarantine(take: String, files: [String], in directory: URL) {
        let fm = FileManager.default
        let dest = quarantineDirectory(besideRecordings: directory)
        let firstSeen = Self.creationDate(take: take, in: directory)   // read BEFORE the move
        var sizes: [String: Int] = [:]
        for f in files {
            let src = directory.appendingPathComponent(f)
            sizes[f] = (try? fm.attributesOfItem(atPath: src.path))?[.size] as? Int ?? 0
            let dstURL = dest.appendingPathComponent(f)
            RecordingCheckpoint.discardIfExists(dstURL)   // a prior quarantine attempt left a copy
            try? fm.moveItem(at: src, to: dstURL)
        }
        let sidecar = QuarantinedTakeSidecar(take: take, firstSeen: firstSeen, fileSizes: sizes)
        let sidecarURL = dest.appendingPathComponent("quarantine_\(take).json")
        try? JSONEncoder().encode(sidecar).write(to: sidecarURL, options: .atomic)
    }

    private static func liveMarker(take: String, in directory: URL) -> RecordingMarker? {
        let url = directory.appendingPathComponent(RecordingCheckpoint.markerFilename(take: take))
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(RecordingMarker.self, from: $0) }
    }

    /// Earliest creation date among a take's files (the take's start, roughly).
    private static func creationDate(take: String, in directory: URL) -> Date {
        let dates = RecordingCheckpoint.takeFiles(take: take, in: directory).compactMap {
            (try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent($0).path))?[.creationDate] as? Date
        }
        return dates.min() ?? Date()
    }
}
