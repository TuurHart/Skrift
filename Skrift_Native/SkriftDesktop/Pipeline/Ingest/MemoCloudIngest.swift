import Foundation
import SwiftData

/// The READ bridge for the Mac→CloudKit client (`MAC_CLOUDKIT_PLAN.md`, 8b): turn a
/// CloudKit-synced `Memo` (+ its `MemoAsset` blob rows) into a local `PipelineFile`.
///
/// **One typed path.** `UploadService.prepare(memo:assets:)` reads the memo's fields and
/// asset blobs directly and decides audio, text or capture once (`UploadService.shape`): the
/// trust gate (`transcriptUserEdited || confidence >= 0.7`), the working-folder
/// materialization, the significance/title/mediaSource reads and the image manifest all live
/// there. The PipelineFile `id` is the memo UUID, so a memo dedups to one row, the contract
/// spine. `metadataJSON(for:)` survives only to fill `PipelineFile.audioMetadataJSON`.
///
/// **Dedup.** `ingest(memo:…)` skips a memo that already has a row, by memo-UUID id OR the
/// embedded `memo_<uuid>.m4a` filename (legacy Bonjour-era rows have a random id).
enum MemoCloudIngest {

    /// Ingest one synced memo into the local pipeline `context`, applying the gate + dedup.
    /// Returns the new `PipelineFile`, or `nil` when skipped (trashed, gated out by
    /// significance, or already ingested).
    ///
    /// Only a rated memo (`NoteConsent.isRated`) enters the queue: significance 0 is synced
    /// but skipped. The Queue band's "Process all N" rates first, then ingests.
    @discardableResult
    static func ingest(memo: Memo, assets: [MemoAsset],
                       upload: UploadService = UploadService(),
                       into context: ModelContext,
                       allowFilenameMatch: Bool = true) throws -> PipelineFile? {
        // Trashed memos never process (the phone hid them; mirror the HTTP list filter).
        guard memo.deletedAt == nil else { return nil }
        // Flag-to-process: significance 0 is synced but never enters the queue.
        guard NoteConsent.isRated(memo) else { return nil }

        let id = memo.id.uuidString
        let filename = audioFilename(for: memo)
        guard !alreadyIngested(id: id, filename: filename, in: context,
                               allowFilenameMatch: allowFilenameMatch) else { return nil }

        let pf = try upload.ingest(memo: memo, assets: assets, into: context)
        // Baseline the live-sync watermark to the memo's current edit time, so a LATER phone
        // edit (newer `lastEditedAt`) is detected by `MemoCloudUpdate` (Part B, phone→Mac).
        pf?.syncedSourceEditedAt = memo.lastEditedAt
        // Typed row mirrors `UploadService` doesn't carry (lock / reminder / photo OCR) —
        // `MemoCloudUpdate` keeps them fresh on later phone edits.
        if let pf {
            pf.imageOCRText = ocrText(for: memo)
            // Every mirrored row field `UploadService` doesn't carry — lock, reminder,
            // tags, importance, destination — adopted from the ONE declaration
            // (`MirroredNoteFields`). `adopt` rather than `pull` because this is FIRST
            // contact: tags in particular must not be wiped by an empty phone list.
            for field in MirroredNoteFields.all { _ = field.adopt(memo, pf) }
            // The phone's name decisions (C81, D20): the row's first link already honours them
            // only if they are on it before the sanitise step runs.
            NameResolutionsMirror.pull(memo, into: pf)
            // Q186: the note's include-audio-in-export switch, one value on every device.
            ExportAudioMirror.pull(memo, into: pf)
        }
        return pf
    }

    /// Flat OCR text for search — the phone's Vision text on each photo
    /// (`imageManifest[].text`, riding the synced metadata blob), joined. nil when none.
    static func ocrText(for memo: Memo) -> String? {
        let texts = (memo.metadata?.imageManifest ?? [])
            .compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    /// The audio filename the memo's row carries — `memo.audioFilename`, or the
    /// `memo_<uuid>.m4a` fallback. Also the dedup key
    /// against a legacy Bonjour-era row (whose id is random but whose filename embeds the UUID).
    static func audioFilename(for memo: Memo) -> String {
        memo.audioFilename.isEmpty ? "memo_\(memo.id.uuidString).m4a" : memo.audioFilename
    }

    /// True when this memo already has a PipelineFile — by memo-UUID id (a prior CloudKit
    /// ingest) OR by its OWN embedded filename (a legacy Bonjour-era audio row, which minted
    /// a random id but whose filename is `memo_<this uuid>.m4a`). Bonjour is retired, but the
    /// filename arm still matches those rows, so a CloudKit re-ingest of one keeps deduping.
    static func alreadyIngested(id: String, filename: String, in context: ModelContext,
                                allowFilenameMatch: Bool = true) -> Bool {
        let descriptor = FetchDescriptor<PipelineFile>(
            predicate: #Predicate { $0.id == id || $0.filename == filename }
        )
        let hits = (try? context.fetch(descriptor)) ?? []
        // An id hit is always decisive. The FILENAME arm is what still dedups a legacy
        // Bonjour row (random id, same filename) — but the caller can switch it off when it
        // knows that row is already OWNED by a different memo, which only the sweep can see.
        return hits.contains { $0.id == id || allowFilenameMatch }
    }

    /// HEAL: adopt a `wordTimings` asset that synced AFTER this memo was ingested.
    /// CloudKit delivers a memo's asset rows independently of the Memo record — the
    /// 2026-07-25 case trailed by 10½ hours — and ingest reads assets exactly ONCE, so a
    /// row that lost that race stayed karaoke-dead on the Mac forever (every click seeks
    /// 0:00, the highlight degrades to a time proportion) while the phone/iPad, which read
    /// the asset directly, played fine. Same late-asset hole the photo heal
    /// (`MemoPhotoMaterializer.materializeMissing`) plugs; sweep-driven and idempotent.
    ///
    /// Trusted-transcript rows only — the same rule first ingest applies to the sidecar
    /// parts: an untrusted memo is re-ASR'd by the Mac and `BatchRunner` writes the Mac's
    /// OWN timings, which the `wordTimingsJSON` empty-guard also protects from clobber.
    /// The cheap guards run before `fetchAssets()` so the steady-state sweep still never
    /// faults asset blobs (the sweep's standing rule).
    static func adoptLateWordTimings(memo: Memo, pf: PipelineFile,
                                     fetchAssets: () -> [MemoAsset]) -> Bool {
        guard memo.deletedAt == nil,
              pf.wordTimingsJSON?.isEmpty ?? true,
              pf.transcribeStatus == .done,
              !(pf.transcript ?? "").isEmpty
        else { return false }
        guard let wt = fetchAssets().first(where: { $0.kind == MemoAsset.Kind.wordTimings }),
              !wt.blob.isEmpty,
              let words = try? JSONDecoder().decode([WordTiming].self, from: wt.blob),
              !words.isEmpty
        else { return false }
        pf.wordTimings = words
        return true
    }

    /// HEAL: the diarization twin of `adoptLateWordTimings` — same CloudKit race, same
    /// once-only read at ingest. A phone-diarized conversation whose `diar` asset lands
    /// late leaves the Mac unable to enroll a speaker's voice from it (the enroll slice
    /// needs the segments) and the review screen with no turns to show.
    ///
    /// Writes the `diar_<id>.json` sidecar too, not just the SwiftData copy — ingest does
    /// both, and voice enrollment reads the sidecar. Skipped when the working folder can't
    /// be derived (a capture row with an empty `path`); the SwiftData copy still lands.
    static func adoptLateDiarization(memo: Memo, pf: PipelineFile,
                                     fetchAssets: () -> [MemoAsset],
                                     sidecar: DiarizationSidecar = DiarizationSidecar()) -> Bool {
        guard memo.deletedAt == nil,
              pf.diarizationSegmentsJSON?.isEmpty ?? true,
              pf.transcribeStatus == .done,
              !(pf.transcript ?? "").isEmpty
        else { return false }
        guard let dz = fetchAssets().first(where: { $0.kind == MemoAsset.Kind.diarization }),
              !dz.blob.isEmpty,
              let data = try? JSONDecoder().decode(DiarizationData.self, from: dz.blob),
              !data.segments.isEmpty
        else { return false }
        pf.diarizationSegments = data.segments
        if !pf.path.isEmpty {
            sidecar.write(data, in: DiarizationSidecar.workingFolder(for: pf), id: pf.id)
        }
        return true
    }

    /// Rebuild the phone's `UploadMetadata` JSON shape from the Memo, on the desktop (the
    /// phone's `UploadMetadata` type can't move here — it depends on the mobile-only
    /// `MemoMetadata`/`SharedContent`). Starts from the raw `metadataData` blob (which already
    /// carries location/weather/pressure/dayPeriod/daylight/steps/imageManifest/bookTitle/…)
    /// and overlays the memo-level fields the phone adds (`source`, `tags`, `recordedAt`,
    /// `duration`, the transcript-trust flags, `title`/`significance`/`annotationText` when
    /// set, and the nested `sharedContent`). Values come from the same Memo fields the phone
    /// uses, so every downstream read (`PhoneMetadata`, `SharedContent.decode`, the trust
    /// gate) sees identical content.
    static func metadataJSON(for memo: Memo) -> Data {
        var dict: [String: Any] = [:]
        if let blob = memo.metadataData,
           let obj = (try? JSONSerialization.jsonObject(with: blob)) as? [String: Any] {
            dict = obj
        }

        dict["source"] = "mobile"
        dict["tags"] = memo.tags
        dict["recordedAt"] = ISO8601.string(from: memo.recordedAt)
        dict["duration"] = memo.duration
        dict["transcriptUserEdited"] = memo.transcriptUserEdited
        dict["transcriptMarkersInjected"] = memo.transcriptMarkersInjected
        if let confidence = memo.transcriptConfidence { dict["transcriptConfidence"] = confidence }
        if let title = memo.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            dict["title"] = title
        }
        // Flag-to-send: only emitted when > 0 (matches UploadMetadata).
        if memo.significance > 0 { dict["significance"] = memo.significance }
        if let annotation = memo.annotationText { dict["annotationText"] = annotation }
        // Nested sharedContent (capture items) — pass the raw blob through verbatim so the
        // desktop's SharedContent.decode reads the identical object.
        if let scBlob = memo.sharedContentData,
           let sc = (try? JSONSerialization.jsonObject(with: scBlob)) as? [String: Any] {
            dict["sharedContent"] = sc
        }

        // `.sortedKeys` for a DETERMINISTIC byte layout — without it JSONSerialization emits
        // keys in (randomized) dictionary order, so the same memo would produce different
        // bytes each ingest (decoded content identical, but not reproducible / diffable).
        return (try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}
