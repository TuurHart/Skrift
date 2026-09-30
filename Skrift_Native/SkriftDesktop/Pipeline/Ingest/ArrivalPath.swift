import Foundation
import SwiftData

/// What happens to a file the moment it arrives on the Mac — by drag, by the Import panel, or
/// out of the Record button. ONE path for all three, because a Mac recording is deliberately
/// not a new kind of thing: it is a file coming in a different door.
///
/// This used to live inside `SidebarView`, which made two claims about recording unprovable
/// without a working microphone and a pair of eyes — that a take arrives UNRATED, and that it
/// gets its words immediately. Both shipped untested on 2026-07-28 and were still unverified
/// when the button stopped producing takes at all. Out here the wiring can be pinned by a
/// test and driven headlessly (`-recordingest`), so the next mic problem can't also hide a
/// pipeline problem behind it.
///
/// The two things a CAPTURE does that an IMPORT does not:
/// 1. **Authors its Memo unrated.** The rating is consent, and recording a thought isn't
///    judging it. Import gets the 0.1 floor instead — putting a file on the Mac *is* a
///    request to process it.
/// 2. **Transcribes at once.** Transcription is capture (raw audio becoming text); polish,
///    name-linking and export are processing, and only those are what a rating gates. Which
///    is also why this can't wait for Process: `process()` skips unrated notes, so without
///    this step a Mac take would stay wordless forever.
enum ArrivalPath {

    /// The pieces that live outside this file's target — audio metadata, the CloudKit sweep,
    /// the transcription run. Injected so the pipeline half stays host-less and testable;
    /// `Hooks.live` in the app target is the single place the real ones get wired.
    struct Hooks {
        /// The real RECORDING date out of the audio's own metadata. The filesystem date is
        /// when the file was copied, not when it was spoken.
        var recordingDate: (URL) async -> Date?
        /// Kick the CloudKit reconcile sweep now rather than at the next trigger.
        var reconcileSoon: () -> Void
        /// Give these files their words. Called for captures only.
        var transcribe: ([String]) async -> Void

        /// Wires nothing — for tests that only care about the store, and for callers with no
        /// engines at all.
        static let inert = Hooks(recordingDate: { _ in nil }, reconcileSoon: {}, transcribe: { _ in })
    }

    /// `combineAudio` carries the C68 chooser's answer ("One note") down to ingest; the doors
    /// that ask (Import, drop, Photos promise) pass it, everything else keeps the default.
    ///
    /// Ingest `urls`, then run the capture steps if `asRecording`. Returns the new rows in
    /// arrival order.
    ///
    /// `onCreated` fires the instant the rows exist, BEFORE transcription — that is the whole
    /// reason it isn't just the return value. Transcribing a take can run for many seconds,
    /// and a note that only appears once its words do would make stopping a recording look
    /// like it did nothing, which is precisely the impression this feature has already given
    /// once.
    ///
    /// Throws only what ingest itself throws (a failed copy or export). The capture steps are
    /// best-effort by design: a take that reached disk must not be lost because CloudKit or
    /// the ASR model was unavailable — the file is already safe, and the reconcile sweep and
    /// Process both pick it up later.
    @MainActor
    @discardableResult
    static func run(urls: [URL],
                    asRecording: Bool,
                    into context: ModelContext,
                    cloudContext: ModelContext?,
                    hooks: Hooks,
                    service: IngestService = IngestService(),
                    combineAudio: Bool = false,
                    onCreated: ([PipelineFile]) -> Void = { _ in }) async throws -> [PipelineFile] {
        guard !urls.isEmpty else { return [] }
        // The row is BORN knowing it's a capture. Not stamped afterwards: the reconcile sweep
        // sees inserted-but-unsaved rows and runs while this function is awaiting file work,
        // so anything set after `ingest` returns has already lost the race — measured twice on
        // real takes before this moved (2026-07-28). Everything below can then take its time.
        var service = service
        service.isLocalRecording = asRecording
        let created = try await service.ingest(localURLs: urls, combineAudio: combineAudio, into: context)
        onCreated(created)

        // Backfill the real recording date (async; survives copies because the date lives
        // inside the m4a).
        let audio = created.filter { $0.sourceType == .audio }
        for pf in audio {
            if let d = await hooks.recordingDate(URL(fileURLWithPath: pf.path)) {
                pf.uploadedAt = d
            }
        }
        if !audio.isEmpty { try? context.save() }

        // A capture authors its own Memo, UNRATED, BEFORE the sweep can floor it to 0.1.
        // `author` is idempotent, so the sweep's backfill then finds it and leaves it alone —
        // that ordering is the whole mechanism, not an optimisation.
        if asRecording, let cloudContext {
            for pf in created {
                let memo = try? MacMemoAuthor.author(for: pf, audioURL: URL(fileURLWithPath: pf.path),
                                                     into: cloudContext, floorSignificance: false)
                // A note this Mac RECORDED gets a place, like a phone one (2026-08-27). Only a
                // recording: where the Mac is standing says nothing true about an imported file.
                // Fire-and-forget — no recording waits on a location fix.
                if let memo { MacLocationStamp.stamp(memo: memo, file: pf, in: cloudContext) }
            }
            try? cloudContext.save()
        }
        hooks.reconcileSoon()
        if asRecording {
            await hooks.transcribe(created.map(\.id))
        }
        return created
    }
}
