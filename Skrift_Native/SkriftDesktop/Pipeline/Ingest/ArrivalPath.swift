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
/// Both doors arrive UNRATED (D159, 2026-09-30 — an import used to floor to 0.1). The rating is
/// consent: recording a thought or adding a file isn't judging it. What a CAPTURE does that an
/// IMPORT does not:
/// 1. **Authors its Memo immediately**, before the sweep can (an import's Memo is the
///    sweep's job — same unrated result either way).
/// 2. **Transcribes at once** through its own hook. Transcription is capture (raw audio becoming text); polish,
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
        /// Give an IMPORT's audio rows their words (Q77 / C49). Words are not polish, so an
        /// unrated import (D159) still gets them on arrival; Tuur's 2026-09-30 report was that
        /// imported voice memos just sat there until a manual Process. Separate from
        /// `transcribe` so a capture's contract (words on stop) and an import's stay
        /// independently pinned.
        var transcribeImport: ([String]) async -> Void
        /// The ambient context (place · daypart · weather) a RECORDING is stamped with (Q326).
        /// A test stubs it; an import never calls it.
        var captureContext: @MainActor () async -> MemoMetadata = { await MacMetadataService().capture() }

        /// Wires nothing — for tests that only care about the store, and for callers with no
        /// engines at all.
        static let inert = Hooks(recordingDate: { _ in nil }, reconcileSoon: {}, transcribe: { _ in },
                                 transcribeImport: { _ in })
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
                    onCreated: ([PipelineFile]) -> Void = { _ in },
                    onSkipped: ([URL]) -> Void = { _ in },
                    onReport: (ImportReport) -> Void = { _ in }) async throws -> [PipelineFile] {
        guard !urls.isEmpty else { return [] }
        // The row is BORN knowing it's a capture. Not stamped afterwards: the reconcile sweep
        // sees inserted-but-unsaved rows and runs while this function is awaiting file work,
        // so anything set after `ingest` returns has already lost the race — measured twice on
        // real takes before this moved (2026-07-28). Everything below can then take its time.
        var service = service
        service.isLocalRecording = asRecording
        let report = try await service.ingestReport(localURLs: urls, combineAudio: combineAudio, into: context)
        let created = report.created
        onCreated(created)
        // Q92: a file that did not become a note is SAID, never silently dropped.
        if !report.skipped.isEmpty { onSkipped(report.skipped) }
        // Q137 / C199: ONE report (made, skipped, failed + why) for the list banner.
        onReport(report.importReport)

        // Backfill the real recording date (async; survives copies because the date lives
        // inside the m4a).
        let audio = created.filter { $0.sourceType == .audio }
        for pf in audio where !report.merged.contains(pf.id) {
            // (A stitched note keeps the FIRST clip's filename time, C124: the stitched file's
            // own embedded date is the stitch moment, not a message time.)
            if let d = await hooks.recordingDate(URL(fileURLWithPath: pf.path)) {
                pf.uploadedAt = d
            }
        }
        if !audio.isEmpty { try? context.save() }

        // A capture authors its own Memo, UNRATED, BEFORE the sweep can.
        // `author` is idempotent, so the sweep's backfill then finds it and leaves it alone —
        // that ordering is the whole mechanism, not an optimisation.
        if asRecording, let cloudContext {
            for pf in created {
                let memo = try? MacMemoAuthor.author(for: pf, audioURL: URL(fileURLWithPath: pf.path),
                                                     into: cloudContext)
                // A note this Mac RECORDED gets a place, like a phone one (2026-08-27). Only a
                // recording: where the Mac is standing says nothing true about an imported file.
                // Fire-and-forget — no recording waits on a location fix.
                if let memo { MacLocationStamp.stamp(memo: memo, file: pf, in: cloudContext, capture: hooks.captureContext) }
            }
            try? cloudContext.save()
        }
        hooks.reconcileSoon()
        if asRecording {
            await hooks.transcribe(created.map(\.id))
        } else {
            // C49 / Q77: an import is unrated (D159) but must not sit wordless until someone
            // rates it — transcription is capture, not processing. Audio only: a note arrives
            // with its text, and `created` also holds video-derived audio rows.
            // Words only; polish waits for the rating (the enhancement model is 9 GB).
            let audioIDs = audio.map(\.id)
            if !audioIDs.isEmpty { await hooks.transcribeImport(audioIDs) }
        }
        return created
    }
}
