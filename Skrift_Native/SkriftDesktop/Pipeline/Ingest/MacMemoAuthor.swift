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
    @discardableResult
    static func author(for pf: PipelineFile, audioURL: URL?, into ctx: ModelContext) throws -> Memo? {
        guard let id = UUID(uuidString: pf.id) else { return nil }
        let already = try ctx.fetchCount(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id }))
        guard already == 0 else { return nil }

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
                        significance: sig > 0 ? sig : 0.1,
                        recordingDeviceID: DeviceID.current())
        if let t = pf.transcript, !t.isEmpty {
            markTranscribed(memo, transcript: t)
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
    /// output), while `transcriptUserEdited` stays false — nobody edited it, and that flag would
    /// be a lie. Together with `.done` this keeps `Memo.isTrustedTranscript` coherent.
    private static func markTranscribed(_ memo: Memo, transcript: String) {
        memo.transcript = transcript
        memo.transcriptStatus = .done
        memo.transcriptConfidence = 1.0
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
