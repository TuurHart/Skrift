import Foundation
import SwiftData
import AVFoundation

/// The Mac AUTHORS Memos ⑤ (`MAC_CLOUDKIT_PLAN.md` direction, Q5 2026-07-21 lock): a file
/// ingested locally on the Mac (the +Upload button / drag-drop, `IngestService`) becomes a
/// synced `Memo` like any phone capture — "Mac-only files" stop existing. Before this, ZERO
/// desktop code constructed a `Memo`; local uploads made only `PipelineFile`s, invisible to
/// the phone.
///
/// **Pure + host-less testable**, like `MemoCloudIngest`/`MacCloudWriteBack`: every entry point
/// takes its `ModelContext` explicitly rather than touching `MemoCloudStore.container` itself —
/// deliberately so. This file lives under `Pipeline/`, which `project.yml`'s
/// `SkriftDesktopTests` target compiles HOST-LESS, straight into the test bundle, with NO
/// `App/`/`Features/` sources (see that target's own comment: "compile the pure-logic sources
/// straight into the test bundle instead of @testable-importing the app"). `MemoCloudStore`/
/// `SettingsStore`-as-a-sync-gate are only ever referenced from `App/`/`Features/` throughout
/// this codebase (`MacCloudMetaSync`, `MemoCloudReconciler+Wiring`) — never from here — so this
/// enum stays reachable with a plain in-memory container, matching `MemoCloudIngest`'s own style.
///
/// **How a local file actually gets authored:** `backfill`, hooked into `MemoCloudReconciler`'s
/// reconcile sweep (`MemoCloudReconciler+Wiring.reconcile`, `App/`-domain — that's where the
/// `MemoCloudStore`/`cloudKitMacSyncEnabled` gate lives), scans every local `PipelineFile` with a
/// UUID id and no `Memo` yet. This is what covers the live +Upload-button/drag-drop path
/// (`IngestService`, which mints `UUID().uuidString` ids) — the sweep picks a row up on the next
/// reconcile, whichever local path created it, without this file ever depending on
/// `IngestService` or `UploadService`. (`UploadService.ingest`'s `memoID == nil` local branch has
/// no live caller today — Bonjour, its historical caller, is retired — so there is nothing to
/// hook there; see the note in `UploadService.ingest`'s doc comment.)
///
/// `reflectTranscripts` is the companion: once a Mac-authored memo's `PipelineFile` gets
/// transcribed by the normal pipeline (BatchRunner), copy that transcript back onto the `Memo` so
/// it reaches the phone — without touching the processing coordinator (out of this lane's scope).
enum MacMemoAuthor {

    // MARK: - Core (pure — explicit ModelContext, no container/settings coupling)

    /// Author a `Memo` for `pf`, or `nil` when skipped: `pf.id` isn't a UUID (a demo/synthetic
    /// row — real local ingests always mint `UUID().uuidString`), or a `Memo` with that id
    /// already exists (idempotent — never re-author, never overwrite). Attaches a `MemoAsset`
    /// with the audio blob when `audioURL` resolves to a readable file; authors WITHOUT audio
    /// otherwise (an honest text-only note beats no note at all).
    /// `floorSignificance` — whether an unrated file still gets a minimal 0.1 rating.
    ///
    /// TRUE for an IMPORT, where the act of adding a file is a request to process it. FALSE
    /// for a Mac RECORDING: capturing a thought is not judging it. Under the unrated model
    /// (2026-07-26, which postdates this floor) the rating IS consent — the Mac spends nothing
    /// on a note until you judge it — so a recording that floored to 0.1 arrived on the phone
    /// pre-rated "passing" and queued itself for processing, which is precisely the lie this
    /// floor was written to avoid, in the other direction (Tuur, 2026-07-28: "it shouldn't be.
    /// Because it's an unrated note").
    ///
    /// The parameter only ever LOWERS the floor: `pf.isLocalRecording` overrides it, because a
    /// recording must stay unrated no matter which caller gets here first. That is not
    /// belt-and-braces — the sweep's `backfill` takes the default and genuinely does race the
    /// arrival path (proven by `-recordingest` on 2026-07-28: the sweep authored the take's
    /// Memo at 0.1 before the capture path could author it at 0).
    @discardableResult
    static func author(for pf: PipelineFile, audioURL: URL?, into ctx: ModelContext,
                       floorSignificance: Bool = true) throws -> Memo? {
        guard let id = UUID(uuidString: pf.id) else { return nil }
        let already = try ctx.fetchCount(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id }))
        guard already == 0 else { return nil }

        let floorSignificance = floorSignificance && !pf.isLocalRecording
        let sig = pf.significance ?? 0
        let memo = Memo(id: id, audioFilename: pf.filename,
                        duration: audioDuration(at: audioURL) ?? 0,
                        // The closest PipelineFile analogue to "recordedAt" — IngestService's own
                        // doc calls this the CONTENT date (filename-embedded / file creation date),
                        // not the upload time. PipelineFile carries no separate duration field.
                        recordedAt: pf.uploadedAt,
                        // LOCKED (brief): a Mac capture is user-initiated processing — an unrated
                        // Memo the Mac silently processes would lie on the phone's flag-to-process
                        // UI, so an un-rated/zero pf still floors to a real (if minimal) rating.
                        significance: (sig > 0 || !floorSignificance) ? sig : 0.1,
                        recordingDeviceID: DeviceID.current())
        if let t = pf.transcript, !t.isEmpty {
            // A live-recording finalize (`LiveRecordingSession.stop()`) seeds `pf.transcript`
            // (+ `.done`) BEFORE this call runs — but ONLY for an EDITED take: an ordinary
            // (not-edited) recording's words always arrive later, via the transcribe hook,
            // strictly AFTER this call (so `reflectTranscripts` still gets to update the
            // Memo once the real pass lands). So seeing a transcript already here, on a
            // fresh local recording, IS the "a person edited this take" signal — no new
            // parameter needs to reach this call from `ArrivalPath.run`, which is frozen.
            markTranscribed(memo, transcript: t, userEdited: pf.isLocalRecording)
        }
        ctx.insert(memo)

        if let audioURL, FileManager.default.fileExists(atPath: audioURL.path),
           let blob = try? Data(contentsOf: audioURL) {
            ctx.insert(MemoAsset(memoID: id, kind: MemoAsset.Kind.audio, filename: pf.filename, blob: blob))
        }

        try ctx.save()
        return memo
    }

    /// Sweep-companion: for each `pf` whose transcript is non-empty but whose ALREADY-AUTHORED
    /// memo's transcript is still empty, copy it over + mark `.done`. This is how a Mac upload's
    /// OWN transcription (produced by the normal pipeline, well after `author` first ran with
    /// `transcriptStatus = .pending`) reaches the phone, without this lane touching the
    /// processing coordinator. Scoped to memos THIS Mac authored (`recordingDeviceID ==
    /// DeviceID.current()`) — a phone-originated memo's transcript is the processing
    /// coordinator's business, not this sweep's; reflecting a Mac re-ASR onto a phone memo would
    /// be a materially different (and broader) feature than "a Mac upload's transcription reaches
    /// the phone." No `lastEditedAt`/`editedAt` bump — same echo-quiet reasoning as
    /// `MacCloudMetaSync` (these are synced fields on their own; bumping it would make the
    /// reconciler's OTHER text-reflect logic think the phone edited something).
    @discardableResult
    static func reflectTranscripts(files: [PipelineFile], into ctx: ModelContext) throws -> Int {
        var count = 0
        for pf in files {
            guard let t = pf.transcript, !t.isEmpty, let id = UUID(uuidString: pf.id) else { continue }
            // Only FINAL words may publish. A live take's row carries the rough caption SEED
            // while the file pass is still decoding — and this reflect runs from the sweep
            // too, so without this gate the seed reaches the (empty) Memo first, the real
            // reflect then skips it as non-empty, and the cloud echo copies the seed back
            // over the row's final text (found 2026-07-28: a paragraphed final clobbered
            // back to its flat seed). In-flight rows simply wait for their own reflect.
            guard pf.transcribeStatus == .done else { continue }
            guard let memo = try ctx.fetch(FetchDescriptor<Memo>(
                predicate: #Predicate { $0.id == id })).first else { continue }
            guard memo.recordingDeviceID == DeviceID.current() else { continue }
            guard (memo.transcript ?? "").isEmpty else { continue }
            markTranscribed(memo, transcript: t)
            count += 1
        }
        if count > 0 { try ctx.save() }
        return count
    }

    /// One-shot (idempotent by construction — no stored "ran once" flag) sweep over every LIVE
    /// local `PipelineFile`: author a `Memo` for each one with a UUID id and no memo yet. Skips
    /// non-UUID ids (demo/synthetic rows — `DemoSeed`'s handful of fixed string ids like
    /// `"demo-1"`) UP FRONT so `author`'s own idempotency fetch never runs for them.
    ///
    /// ALSO requires a real on-disk `path` — every genuine local ingest sets one, regardless of
    /// `sourceType` (`UploadService`/`IngestService` always pass `path:`), so an empty path can
    /// only be a synthetic row. This matters because `DemoSeed` has exactly one row (`f7`, built
    /// to make a memo-link chip resolve in `-snapshot`/`-demo` renders) with a deliberately
    /// UUID-shaped id but NO path — without this check `author`'s own "no audio → author
    /// text-only anyway" fallback (correct for a real pathless-audio edge case) would let that
    /// demo row's fabricated title/transcript leak into a real CloudKit Memo store under
    /// `-demo` + CloudKit-Mac-sync-on. `author`'s own UUID + idempotency guards make this
    /// otherwise safe to call on every reconcile sweep.
    @discardableResult
    static func backfill(files: [PipelineFile], into ctx: ModelContext) throws -> Int {
        var count = 0
        for pf in files {
            guard UUID(uuidString: pf.id) != nil, !pf.path.isEmpty else { continue }
            if try author(for: pf, audioURL: resolvedAudioURL(for: pf), into: ctx) != nil {
                count += 1
            }
        }
        return count
    }

    // MARK: - Typed notes (the ✎/⌘N verb — mocks/mac-new-note.html, m2 signed 2026-07-28)

    /// A typed note born on the Mac. The shape rules moved to `Memo.newTyped` when the
    /// iPad grew the same ✎ verb (2026-08-18) — one author, so `transcriptStatus` /
    /// the `"typed"` marker / unrated-by-birth can never drift between the apps. No
    /// `PipelineFile` — the rating is what pipelines a memo; the unrated pane renders
    /// and edits it.
    static func typedNote(into ctx: ModelContext, now: Date = Date()) throws -> Memo {
        try Memo.newTyped(into: ctx, now: now)
    }

    // MARK: - Privates

    /// The on-disk audio file for a local `PipelineFile`, or `nil` for a non-audio row
    /// (`.note`/`.capture` — `path` isn't an audio file for those, see
    /// `PipelineFile.workingFolder`) or one with no path yet. `path` is already the absolute
    /// `original.<ext>` file — both `UploadService` and `IngestService` set it that way at
    /// construction, so no further resolution is needed.
    private static func resolvedAudioURL(for pf: PipelineFile) -> URL? {
        guard pf.sourceType == .audio, !pf.path.isEmpty else { return nil }
        return URL(fileURLWithPath: pf.path)
    }

    /// Stamp a Mac-completed transcript onto a freshly-authored (or reflected) memo.
    /// `transcriptConfidence = 1.0` is an honest signal (this IS the Mac's own finished ASR
    /// output). `userEdited` defaults false — the ordinary case, where nobody edited it and
    /// that flag would be a lie — and is `true` only for a live take a person edited
    /// mid-record (`author`'s call, above): there the settled text really IS theirs, and the
    /// flag makes the transcript TRUSTED cross-device. Together with `.done` this keeps
    /// `Memo.isTrustedTranscript` coherent.
    private static func markTranscribed(_ memo: Memo, transcript: String, userEdited: Bool = false) {
        // Body v2 (C10): a body carrying pictures is committed through the one writer (a
        // speech row was already committed by BatchRunner, so that is a no-op). A body with
        // no picture is stored as-is: C19's whitespace pass would flatten an imported
        // note's nested-list indentation.
        let manifest = memo.metadata?.imageManifest ?? []
        memo.transcript = BodyV2Marker.runs(in: transcript, manifestCount: manifest.count).isEmpty
            ? transcript
            : BodyV2.committed(BodyV2.Input(text: transcript, manifest: manifest,
                                            source: .speech, userEdited: userEdited))
        memo.transcriptStatus = .done
        memo.transcriptConfidence = 1.0
        memo.transcriptUserEdited = userEdited
    }

    /// Best-effort audio duration off the materialized file. `PipelineFile` carries no duration
    /// field (unlike the phone's `Memo`) — this is the only source, so a Mac-authored memo doesn't
    /// permanently show "0:00" on the phone's duration chip. Synchronous `AVURLAsset` access
    /// matches this codebase's own established pattern for a quick local-file read
    /// (`IngestService.hasVideoTrack`/`embeddedRecordingDate`), not a new one. `nil`/unreadable →
    /// the caller floors to 0; never blocks authoring.
    private static func audioDuration(at url: URL?) -> TimeInterval? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        let seconds = CMTimeGetSeconds(AVURLAsset(url: url).duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}
