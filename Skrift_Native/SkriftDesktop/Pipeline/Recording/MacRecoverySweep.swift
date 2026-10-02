import AVFoundation
import Foundation
import SwiftData

/// The Mac's launch sweep (C99/D26/C288, Q163): a take the process never finished — a kill,
/// a crash, a dead battery, a force-quit mid-record — becomes a NOTE on the next launch,
/// titled so the user can see it was recovered. The scan, ordering, source choice and
/// quarantine are the shared `RecordingSweep` (the phone runs the same); this file is only
/// the Mac's `rebuild`: merge the surviving audio, then run the SAME arrival path a live
/// stop uses, so the recovered take is unrated, authored, and transcribed like any capture.
///
/// Host-less: the contexts and hooks are parameters (this folder is compiled into the
/// unit-test bundle without the app), so a test can drive it with a synthetic orphan
/// segment set and no microphone.
enum MacRecoverySweep {

    /// Sweep `directory` (default: the recordings staging folder). Returns the shared report.
    @MainActor
    @discardableResult
    static func run(directory: URL = AppPaths.recordingsDirectory,
                    into context: ModelContext,
                    cloudContext: ModelContext?,
                    hooks: ArrivalPath.Hooks,
                    service: IngestService = IngestService()) async -> RecordingSweep.Report {
        await RecordingSweep.run(directory: directory) { sources, startedAt, _ in
            await rebuild(sources: sources, startedAt: startedAt, directory: directory,
                          into: context, cloudContext: cloudContext, hooks: hooks, service: service)
        }
    }

    /// Merge `sources` into a staged `memo_<id>.m4a`, run the arrival path on it, title the
    /// note. nil when the audio could not be rebuilt or ingested — the take's files then
    /// stay for the next launch.
    @MainActor
    private static func rebuild(sources: [URL], startedAt: Date, directory: URL,
                                into context: ModelContext, cloudContext: ModelContext?,
                                hooks: ArrivalPath.Hooks, service: IngestService) async -> UUID? {
        let staged = directory.appendingPathComponent(RecordingCore.filename())
        defer { RecordingCheckpoint.discardIfExists(staged) }   // ingest COPIES it; the staged file is scratch
        do {
            try await Task.detached(priority: .userInitiated) {
                try AudioClipMerge.merge(sources: sources, to: staged)
            }.value
        } catch {
            return nil
        }
        guard RecordingCheckpoint.isReadableAudio(staged) else { return nil }

        // The note is dated when the take STARTED, not when the sweep ran.
        var arrival = hooks
        arrival.recordingDate = { _ in startedAt }
        do {
            let created = try await ArrivalPath.run(
                urls: [staged], asRecording: true, into: context, cloudContext: cloudContext,
                hooks: arrival, service: service)
            guard let pf = created.first, let id = UUID(uuidString: pf.id) else { return nil }
            MacTakeTitle.apply(RecordingSweep.recoveredTitle, to: pf, cloudContext: cloudContext)
            return id
        } catch {
            RecordingLifecycleLog.log("recover-deferred", "arrival failed — \(error.localizedDescription)")
            return nil
        }
    }
}

/// Titles a note with WHY it looks the way it does — a recovered take, or a take the disk
/// stopped (R46). Both the row (what the pane shows) and the synced Memo (what the phone
/// shows) carry it; neither counts as a user edit.
enum MacTakeTitle {
    @MainActor
    static func apply(_ title: String, to pf: PipelineFile, cloudContext: ModelContext?) {
        pf.enhancedTitle = title
        if let cloudContext, let id = UUID(uuidString: pf.id),
           let memo = try? cloudContext.fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })).first {
            memo.title = title
            try? cloudContext.save()
        }
    }
}
