import AVFoundation
import Foundation
import SwiftData
import SwiftUI
import os

/// One live take, end to end: the microphone (`MacRecorder`), the shared caption engine
/// (`LiveCaptionEngine` through the desktop `TranscriptionService`), the DRAFT the user
/// watches and may edit, and the stop-time finalize + arrival. The m2 surface
/// (`mocks/mac-live-transcription.html`) renders this and nothing else.
///
/// The ownership contract the whole design hangs on:
/// - `settledText` is the USER's. It starts as the engine's committed chunks (which never
///   re-transcribe — the phone's hard-won rotation boundary) and every keystroke edit lands
///   here. The engine may only APPEND to it (a newly committed chunk), never rewrite it.
/// - `wetText` is the ENGINE's — the volatile tail, re-transcribed each poll, display-only.
/// - The first user edit sets `everEdited`, which flips finalize authority: an unedited take
///   gets today's full-quality file pass (words swap in silently, phone-parity); an edited
///   take keeps every settled word verbatim and finalizes ONLY the engine's tail
///   (`LiveCaptionEngine.finishParts().finalTail`), landing with the Memo marked
///   user-edited (= trusted).
///
/// `settledText`/`wetText` are thin proxies over a private `LiveRecordingDraft`
/// (`Pipeline/Recording/LiveRecordingDraft.swift`) — the pure, unit-tested absorb math. That
/// separation is also what keeps the two mutation paths honest: a poll calls
/// `draft.absorb(...)` directly (never sets `everEdited`), while a person's edit can ONLY
/// reach the draft through `settledText`'s setter (`draft.edit(...)`, always sets it) — the
/// type system keeps the poll loop from ever looking like a user edit.
@MainActor
@Observable
final class LiveRecordingSession {

    enum Phase: Equatable {
        case idle
        /// Mic + engine coming up (fail-fast still applies — a refusal lands in `.failed`).
        case starting
        case live
        /// Stop pressed; the tail is being finalized + the take is arriving. Brief on an M4.
        /// Stop just stops (m4, trimmed per Tuur): no narration — the UI shows the note with
        /// the wet band until `idle`.
        case settling
        /// Start or capture refused — carries what to tell the user (same alert the Record
        /// button already shows).
        case failed(MacRecorder.Refusal)
    }

    private(set) var phase: Phase = .idle

    // ── the draft ─────────────────────────────────────────────
    /// The user's text. Bind the editor here; the setter records "the user touched this"
    /// (`everEdited`) whenever the change didn't come from the engine's own append.
    var settledText: String {
        get { draft.settledText }
        set { draft.edit(settledText: newValue) }
    }
    /// The engine's volatile tail — rendered wet-ink, never editable.
    var wetText: String { draft.wetText }

    // ── transport passthrough (same meanings as MacRecorder's) ──
    var elapsed: TimeInterval { recorder.elapsed }
    var elapsedLabel: String { RecordingCore.elapsedLabel(elapsed) }
    var meter: RecordingCore.Meter { recorder.meter }
    /// Said in the draft pane when the input died mid-take but the words so far are saved
    /// (recsj-029). nil in every other state.
    var notice: String? { recorder.lossNotice }
    /// The transcription model's state, said in the pane while it loads (Q165): without it a
    /// slow first load looks like the recorder hearing nothing.
    var modelState: RecordingModelState { ASRModelStatus.shared.state }

    /// After a completed stop: the created `PipelineFile` id, so the UI can select it.
    private(set) var noteID: String?

    /// "Add recording" (D173, Q290): the existing note this take lands on, set by
    /// `start(appendingTo:)`. nil = an ordinary take that becomes a new note.
    struct AppendTarget: Equatable {
        let id: String
        let title: String
    }
    private(set) var appendTarget: AppendTarget?

    private static let log = Logger(subsystem: "com.skrift.desktop", category: "liverecord")

    private let coordinator: ProcessingCoordinator
    private let context: ModelContext
    private let recorder = MacRecorder()
    private var draft = LiveRecordingDraft()
    private var captionTask: Task<Void, Never>?

    init(coordinator: ProcessingCoordinator, context: ModelContext) {
        self.coordinator = coordinator
        self.context = context
    }

    /// Mic up, engine on, poll loop running. A refusal lands in `.failed` — the caller
    /// surfaces it exactly like a Record-button refusal today.
    ///
    /// `.starting` lasts until the FIRST captured buffer, not just until `recorder.start()`
    /// returns — that call only confirms the capture session was configured and dispatched
    /// (`MacRecorder`'s own 1.5s fail-fast can still kill the take with zero buffers after
    /// this function has already returned). The fan-out closure this class installs for the
    /// caption feed doubles as that signal: its first invocation IS the first buffer.
    /// (A fail-fast death with zero buffers ever arriving leaves `phase` at `.starting`, same
    /// as a mid-take device loss leaves it at `.live` — either way the very next `stop()`/
    /// `cancel()` picks up `recorder.state`'s `.failed` honestly, same as today.)
    func start(appendingTo file: PipelineFile? = nil) async {
        // One mic, one take: a second start while a take is in flight is ignored.
        switch phase {
        case .starting, .live, .settling: return
        default: break
        }
        phase = .starting
        draft = LiveRecordingDraft()
        noteID = nil
        appendTarget = file.map { AppendTarget(id: $0.id, title: $0.displayTitle) }
        // R46: the recorder ends the take itself when the disk refuses a write — stop + SAVE
        // what landed, the note titled with the reason.
        recorder.onTakeEnded = { [weak self] reason in
            Task { @MainActor [weak self] in await self?.stop(reason: reason) }
        }
        var announcedLive = false
        // Read once, synchronously, while `recorder.start()` builds the capture session.
        recorder.onLiveBuffer = { [weak self] buffer in
            if !announcedLive {
                announcedLive = true
                Task { @MainActor [weak self] in
                    guard let self, self.phase == .starting else { return }
                    self.phase = .live
                }
            }
            Task { await TranscriptionService.shared.feedStream(buffer) }
        }
        guard await recorder.start() else {
            applyRecorderFailure()
            return
        }
        await TranscriptionService.shared.beginStream()
        startCaptionPolling()
    }

    /// Stop, finalize per the ownership contract, hand the take to `ArrivalPath.run`
    /// (asRecording: true, with hooks that respect `everEdited`), then `.idle`.
    func stop(reason: String? = nil) async {
        guard phase != .settling else { return }   // the recorder's own stop (write failure) and a click can race
        phase = .settling
        captionTask?.cancel(); captionTask = nil

        // Why the take ended on its own (a write failure), if it did — titles the note (R46).
        let endedReason = reason ?? recorder.endedReason
        guard let url = recorder.stop() else {
            applyRecorderFailure()
            await TranscriptionService.shared.endStream()
            draft = LiveRecordingDraft()
            return
        }

        let cloudContext = MemoCloudStore.container?.mainContext
        var createdRow: PipelineFile?

        // "Add recording": land the take on its note. Only a take that could NOT be added
        // (the note is gone, or its audio can't be spliced) falls through to the new-note
        // path below, so the take is never lost.
        if let target = appendTarget {
            appendTarget = nil
            if await finishAppend(clip: url, to: target, cloudContext: cloudContext) {
                phase = .idle
                draft = LiveRecordingDraft()
                return
            }
            coordinator.flash("Couldn't add it to that note, so it's saved as a new note")
        }

        if draft.everEdited {
            // Edited → the person's settled text is FINAL for its region; only the engine's
            // own un-rotated tail needs a final-quality close (`finishParts`, not `endStream`
            // — the whole point is a partial re-ASR that never touches a settled word).
            let finalTail = await TranscriptionService.shared.finishStreamTail()
            let finalTranscript = LiveRecordingFinalize.transcript(
                settledText: draft.settledText, finalTail: finalTail)
            var hooks = ArrivalPath.Hooks.live(coordinator: coordinator, context: context)
            // The row already has its words — BatchRunner must never re-ASR an edited take.
            hooks.transcribe = { _ in }
            do {
                let created = try await ArrivalPath.run(
                    urls: [url], asRecording: true, into: context, cloudContext: cloudContext,
                    hooks: hooks,
                    onCreated: { rows in
                        guard let pf = rows.first else { return }
                        createdRow = pf
                        // BEFORE the arrival hooks run (`MacMemoAuthor.author`, inside
                        // `ArrivalPath.run`, right after this closure) — that ordering is what
                        // lets `author` read "transcript already set on a fresh recording" as
                        // the user-edited signal (see `MacMemoAuthor.author`'s own comment).
                        // Body v2 (C10): an edited take is the person's text — commit it as an edit.
                        pf.transcript = BodyV2.committed(BodyV2.Input(
                            text: finalTranscript, source: .speech, userEdited: true))
                        pf.transcribeStatus = .done
                        // The pane's "✎ edited while recording" chip reads this local
                        // mirror; the synced Memo's own flag is inferred by `author()`
                        // from the transcript being present this early.
                        pf.transcriptUserEdited = true
                    })
                noteID = created.first?.id
                finishTake(created: created, titled: endedReason, cloudContext: cloudContext)
            } catch {
                Self.log.error("stop(): edited-take ingest failed — \(String(describing: error), privacy: .public)")
            }
        } else {
            // Not edited → today's path VERBATIM: the full-quality file pass replaces
            // everything. The only addition: seed the row's transcript with the live text
            // right as the real pass starts (inside the wrapped `transcribe` hook, AFTER the
            // Memo is authored with an empty transcript) so words never blink out locally —
            // seeding any earlier would leave the Memo non-empty at authoring time, and
            // `reflectTranscripts` only ever updates a Memo whose transcript is still empty,
            // stranding the synced copy on the rough live text forever.
            let liveText = LiveRecordingFinalize.transcript(
                settledText: draft.settledText, finalTail: draft.wetText)
            await TranscriptionService.shared.endStream()
            var hooks = ArrivalPath.Hooks.live(coordinator: coordinator, context: context)
            let realTranscribe = hooks.transcribe
            hooks.transcribe = { ids in
                if !liveText.isEmpty { createdRow?.transcript = liveText }
                await realTranscribe(ids)
            }
            do {
                let created = try await ArrivalPath.run(
                    urls: [url], asRecording: true, into: context, cloudContext: cloudContext,
                    hooks: hooks,
                    onCreated: { rows in createdRow = rows.first })
                noteID = created.first?.id
                finishTake(created: created, titled: endedReason, cloudContext: cloudContext)
            } catch {
                Self.log.error("stop(): ingest failed — \(String(describing: error), privacy: .public)")
            }
        }

        phase = .idle
        draft = LiveRecordingDraft()
    }

    /// Abandon the take: mic stopped, engine cleared, file deleted, draft discarded.
    func cancel() {
        captionTask?.cancel(); captionTask = nil
        recorder.cancel()
        Task { await TranscriptionService.shared.endStream() }
        draft = LiveRecordingDraft()
        noteID = nil
        appendTarget = nil
        phase = .idle
    }

    /// Land a stopped take on an existing note (`MacAppendRecording`, the phone's
    /// `appendRecordingAsync` shape). Returns false — with the note untouched and the take's
    /// files kept — when the take could not be added; the caller then saves it as a new note.
    ///
    /// The words: an EDITED take keeps the person's settled text plus the engine's final tail
    /// (the new-note rule); an unedited one takes the full-quality file pass, falling back to
    /// the live text when that pass hears nothing or fails. The file pass's word timings ride
    /// along either way (`KaraokeTrack` aligns them to the shown words).
    private func finishAppend(clip url: URL, to target: AppendTarget, cloudContext: ModelContext?) async -> Bool {
        let targetID = target.id
        guard let pf = try? context.fetch(FetchDescriptor<PipelineFile>(
            predicate: #Predicate { $0.id == targetID })).first, pf.deletedAt == nil else {
            Self.log.error("append: note \(targetID, privacy: .public) is gone; saving the take as a new note")
            return false
        }
        var text: String
        let edited = draft.everEdited
        if edited {
            let tail = await TranscriptionService.shared.finishStreamTail()
            text = LiveRecordingFinalize.transcript(settledText: draft.settledText, finalTail: tail)
        } else {
            text = LiveRecordingFinalize.transcript(settledText: draft.settledText, finalTail: draft.wetText)
            await TranscriptionService.shared.endStream()
        }
        var timings: [WordTiming] = []
        if let result = try? await TranscriptionService.shared.transcribe(audioURL: url),
           !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !edited { text = result.text }
            timings = result.wordTimings
        }

        // Audio first, off the main actor. A throw leaves the note's audio as it was.
        let path = pf.path
        let splice: (merged: TimeInterval, base: TimeInterval)
        do {
            splice = try await Task.detached(priority: .userInitiated) {
                try MacAppendRecording.spliceAudio(path: path, clip: url) { msg in
                    Logger(subsystem: "com.skrift.desktop", category: "liverecord").error("\(msg, privacy: .public)")
                }
            }.value
        } catch {
            Self.log.error("append: splice failed — \(String(describing: error), privacy: .public); note untouched")
            return false
        }

        let settings = SettingsStore.shared.load()
        let memo = cloudContext.flatMap { MacCloudWriteBack.resolve(for: pf, in: $0) }
        do {
            try MacAppendRecording.land(text: text, timings: timings, splice: splice,
                                        on: pf, memo: memo, cloud: cloudContext,
                                        people: NamesStore.shared.livePeople(),
                                        author: settings.authorName)
        } catch {
            // The audio is already in the note; only the cloud save failed. Never re-save the
            // take as a second note — the row holds everything and the next edit re-syncs.
            Self.log.error("append: cloud write failed — \(String(describing: error), privacy: .public)")
        }
        try? context.save()
        recorder.discardFinishedTake()
        noteID = pf.id
        coordinator.flash(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          ? "Recording added — no words heard" : "Recording added")
        return true
    }

    /// The take is stored as a note: title it with why it ended early (R46), then — and only
    /// then — delete the take's segment files. Until here they are the only copy, and the
    /// next launch's sweep would rebuild the note from them. An ingest that produced no row
    /// leaves them in place.
    private func finishTake(created: [PipelineFile], titled reason: String?, cloudContext: ModelContext?) {
        guard let pf = created.first else { return }
        if let reason { MacTakeTitle.apply(reason, to: pf, cloudContext: cloudContext) }
        recorder.discardFinishedTake()
    }

    /// Launch sweep (C99): rebuild every take an earlier run never finished into a note.
    /// Safe to call once at startup; a take recording right now is skipped by the shared core.
    func recoverInterruptedTakes() async {
        guard phase == .idle else { return }
        let report = await MacRecoverySweep.run(
            into: context, cloudContext: MemoCloudStore.container?.mainContext,
            hooks: ArrivalPath.Hooks.live(coordinator: coordinator, context: context))
        if !report.recovered.isEmpty || !report.kept.isEmpty || !report.cleaned.isEmpty {
            Self.log.notice("sweep: recovered=\(report.recovered.count, privacy: .public) kept=\(report.kept.count, privacy: .public) quarantined=\(report.cleaned.count, privacy: .public)")
        }
    }

    // MARK: - Privates

    private func applyRecorderFailure() {
        guard let refusal = LiveRecordingFinalize.refusal(after: recorder.state) else {
            phase = .idle
            return
        }
        phase = .failed(refusal)
        recorder.clearFailure()
    }

    /// Poll the live caption on a SELF-PACING loop — mirrors the phone's
    /// `LiveRecordingService.startCaptionPolling` (`LiveRecordingService.swift:1367`): each
    /// snapshot re-transcribes the whole accumulated live chunk, so its cost grows with the
    /// chunk, and pacing the next poll off the last snapshot's cost (+ thermal pressure)
    /// keeps an M4 from spinning the ANE flat out for the whole take.
    ///
    /// Gated on `Task.isCancelled` alone, NOT `phase == .live` — `phase` only graduates from
    /// `.starting` to `.live` once the first buffer actually arrives (an async race against
    /// this very loop's first iteration), while `stop()`/`cancel()` both cancel `captionTask`
    /// as their very first action, before touching `phase` at all. Cancellation is the
    /// race-free signal; re-deriving "still active" from `phase` here isn't.
    private func startCaptionPolling() {
        captionTask?.cancel()
        captionTask = Task { @MainActor [weak self] in
            // Per-iteration local borrow (`s`), the phone loop's own idiom — a plain
            // `guard let self` would hold the session strongly across every sleep for the
            // task's whole life, and can't be re-guarded after later awaits anyway.
            while !Task.isCancelled {
                guard self != nil else { return }
                let started = Date()
                let parts = await TranscriptionService.shared.liveCaptionParts()
                let cost = Date().timeIntervalSince(started)
                guard let s = self, !Task.isCancelled else { return }
                if !parts.full.isEmpty {
                    s.draft.absorb(full: parts.full, committed: parts.committed)
                }
                // floor 0.4 (Mac-only): text settles `stablePollsToSettle` poll cycles
                // after the last word, so the poll floor is the felt settle latency.
                let delay = LiveCaptionEngine.pollDelay(
                    afterSnapshotCost: cost, thermal: ProcessInfo.processInfo.thermalState,
                    floor: 0.4)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }
}
