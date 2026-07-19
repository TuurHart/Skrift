import Foundation
import SwiftData

/// The READ bridge for the Mac→CloudKit client (`MAC_CLOUDKIT_PLAN.md`, 8b): turn a
/// CloudKit-synced `Memo` (+ its `MemoAsset` blob rows) into a local `PipelineFile`, the
/// CloudKit analogue of the HTTP `POST /api/files/upload` handler.
///
/// **Parity by construction.** Rather than re-implement the field mapping (and risk drift
/// from the proven HTTP path), this synthesizes the SAME multipart `parts` the phone would
/// have uploaded — a `files` audio part, a `metadata` JSON part, the `transcript`, the
/// `wordTimings` / `diar` sidecars, and `images` parts — and hands them to the EXISTING
/// `UploadService.ingest`. So the trust gate (`transcriptUserEdited || confidence ≥ 0.7`),
/// the working-folder materialization, the significance/title/mediaSource reads, and the
/// image manifest are all the identical code. The one deliberate divergence (per the plan):
/// the PipelineFile `id` is forced to `memo.id.uuidString` (via `UploadService`'s `memoID`),
/// so a memo dedups to one row regardless of transport — the contract spine.
///
/// **Coexistence.** Reads/writes nothing of the Bonjour path; both feed the same
/// `PipelineFile` store and `ingest(memo:…)` dedups (by memo-UUID id OR the embedded
/// `memo_<uuid>.m4a` filename) so a memo seen via CloudKit AND Bonjour collapses to one row.
enum MemoCloudIngest {

    /// Ingest one synced memo into the local pipeline `context`, applying the gate + dedup.
    /// Returns the new `PipelineFile`, or `nil` when skipped (trashed, gated out by
    /// significance, or already ingested via either transport).
    ///
    /// `processEverything` is the 8d opt-in override for the "process every synced memo,
    /// not just significance > 0" Mac setting; the default preserves the phone's
    /// flag-to-send intent (`significance > 0` only — `0` stays on the phone).
    @discardableResult
    static func ingest(memo: Memo, assets: [MemoAsset],
                       upload: UploadService = UploadService(),
                       into context: ModelContext,
                       processEverything: Bool = false) throws -> PipelineFile? {
        // Trashed memos never process (the phone hid them; mirror the HTTP list filter).
        guard memo.deletedAt == nil else { return nil }
        // Flag-to-send: significance 0 stays on the phone (unless the Mac opts into all).
        guard processEverything || memo.significance > 0 else { return nil }

        let id = memo.id.uuidString
        let filename = audioFilename(for: memo)
        guard !alreadyIngested(id: id, filename: filename, in: context) else { return nil }

        let parts = buildParts(memo: memo, assets: assets, filename: filename)
        let pf = try upload.ingest(parts: parts, into: context, memoID: id).first
        // Baseline the live-sync watermark to the memo's current edit time, so a LATER phone
        // edit (newer `lastEditedAt`) is detected by `MemoCloudUpdate` (Part B, phone→Mac).
        pf?.syncedSourceEditedAt = memo.lastEditedAt
        // Typed row mirrors the multipart shim doesn't carry (lock / reminder / photo OCR) —
        // `MemoCloudUpdate` keeps them fresh on later phone edits.
        if let pf {
            pf.locked = memo.locked
            pf.remindAt = memo.remindAt
            pf.imageOCRText = ocrText(for: memo)
            // The phone's user-applied tags → the Mac's applied `tags` (the frontmatter set).
            // The multipart shim doesn't carry them, and the Mac's own derivation lands in
            // `tagSuggestions`, so without this the phone's tags never appear on the Mac.
            if !memo.tags.isEmpty { pf.tags = memo.tags }
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

    /// The audio filename the phone would have uploaded — `memo.audioFilename`, or the
    /// `memo_<uuid>.m4a` fallback (matching `UploadPayload.build`). Also the dedup key
    /// against a Bonjour-ingested row (whose id is random but whose filename embeds the UUID).
    static func audioFilename(for memo: Memo) -> String {
        memo.audioFilename.isEmpty ? "memo_\(memo.id.uuidString).m4a" : memo.audioFilename
    }

    /// True when this memo already has a PipelineFile — by memo-UUID id (a prior CloudKit
    /// ingest) OR by the embedded filename (a Bonjour AUDIO upload, which minted a random id
    /// but whose filename is `memo_<uuid>.m4a`).
    ///
    /// HISTORICAL (captures): Bonjour uploads are RETIRED (2026-07-06), so the old
    /// "same capture arriving via both transports double-creates" hazard can no longer
    /// occur for new data. The filename arm below is NOT dead though — it's what still
    /// matches the legacy Bonjour-era rows (random id, `memo_<uuid>.m4a` filename) in
    /// the store, so a CloudKit re-ingest of one of those keeps deduping correctly.
    static func alreadyIngested(id: String, filename: String, in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<PipelineFile>(
            predicate: #Predicate { $0.id == id || $0.filename == filename }
        )
        let count = (try? context.fetchCount(descriptor)) ?? 0
        return count > 0
    }

    /// Synthesize the multipart `parts` the phone's `UploadPayload` would have produced for
    /// this memo — so `UploadService.ingest` maps it identically. A capture memo (no audio
    /// asset, `sharedContent` present) yields no `files` part, hitting the capture branch.
    static func buildParts(memo: Memo, assets: [MemoAsset], filename: String) -> [MultipartPart] {
        var parts: [MultipartPart] = []

        // metadata (always) — the reconstructed UploadMetadata-shaped JSON.
        parts.append(MultipartPart(name: "metadata", filename: nil,
                                   contentType: "application/json", data: metadataJSON(for: memo)))

        // files (audio) — present unless this is a no-audio capture.
        if let audio = assets.first(where: { $0.kind == MemoAsset.Kind.audio }) {
            parts.append(MultipartPart(name: "files", filename: filename,
                                       contentType: "audio/mp4", data: audio.blob))
        }

        // transcript — sent whenever complete + non-empty (the phone's condition,
        // UploadPayload.build); UploadService applies the trust gate.
        if memo.transcriptStatus == .done, let transcript = memo.transcript, !transcript.isEmpty {
            parts.append(MultipartPart(name: "transcript", filename: nil,
                                       contentType: nil, data: Data(transcript.utf8)))
        }

        // Optional additive sidecars (only honored on a trusted transcript, like HTTP).
        if let wt = assets.first(where: { $0.kind == MemoAsset.Kind.wordTimings }), !wt.blob.isEmpty {
            parts.append(MultipartPart(name: "wordTimings", filename: nil,
                                       contentType: "application/json", data: wt.blob))
        }
        if let dz = assets.first(where: { $0.kind == MemoAsset.Kind.diarization }), !dz.blob.isEmpty {
            parts.append(MultipartPart(name: "diar", filename: nil,
                                       contentType: "application/json", data: dz.blob))
        }

        // images — one part per photo asset, in stable filename order (so the manifest
        // entries in the metadata line up with the parts, exactly as the phone sends them).
        let photos = assets.filter { $0.kind == MemoAsset.Kind.photo }.sorted { $0.filename < $1.filename }
        for photo in photos {
            parts.append(MultipartPart(name: "images", filename: photo.filename,
                                       contentType: "image/jpeg", data: photo.blob))
        }

        // document — a shared `.file` capture's PDF/doc (3b), materialized into the capture
        // folder so the Mac can OPEN the real file (not just show its extracted text).
        if let doc = assets.first(where: { $0.kind == MemoAsset.Kind.document }), !doc.blob.isEmpty {
            parts.append(MultipartPart(name: "document", filename: doc.filename,
                                       contentType: "application/octet-stream", data: doc.blob))
        }

        return parts
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
