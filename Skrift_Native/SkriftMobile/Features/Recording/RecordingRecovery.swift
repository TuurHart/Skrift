import AVFoundation
import Foundation

/// The launch sweep that turns a take the process never finished into a note
/// (C99/D26), and cleans up what cannot be recovered (C288).
extension MemoSaver {
    /// The title a rebuilt note carries, so the user sees it was recovered.
    nonisolated static let recoveredTitle = RecordingSweep.recoveredTitle

    /// The report, the quarantine sidecar and every on-disk rule live in the shared
    /// core (`Shared/Recording/RecordingSweep.swift`, Q163) — the Mac runs the same sweep.
    typealias RecordingSweepReport = RecordingSweep.Report
    typealias QuarantinedTakeSidecar = RecordingSweep.QuarantinedTakeSidecar

    /// Sweep `directory` for takes left behind by an earlier process run (the scan, the
    /// ordering and the quarantine are `RecordingSweep.run`). A take with readable audio
    /// becomes a new note (`.transcribing`, titled `recoveredTitle`, dated when the take
    /// started) that the launch transcription recovery picks up; a take with none is
    /// quarantined.
    @discardableResult
    func recoverInterruptedRecordings(directory: URL = AppPaths.recordingsDirectory) async -> RecordingSweepReport {
        await RecordingSweep.run(directory: directory) { sources, startedAt, _ in
            await self.rebuildNote(from: sources, recordedAt: startedAt)
        }
    }

    nonisolated static func recoverableSources(take: String, marker: RecordingMarker?, in directory: URL) -> [URL] {
        RecordingSweep.recoverableSources(take: take, marker: marker, in: directory)
    }

    /// Merge `sources` into a new `memo_<id>.m4a` and insert the note. nil when
    /// the audio could not be written.
    private func rebuildNote(from sources: [URL], recordedAt: Date) async -> UUID? {
        let id = UUID()
        let filename = RecordingCore.filename(id: id)
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

    nonisolated static func quarantineDirectory(besideRecordings directory: URL) -> URL {
        RecordingSweep.quarantineDirectory(besideRecordings: directory)
    }
}
