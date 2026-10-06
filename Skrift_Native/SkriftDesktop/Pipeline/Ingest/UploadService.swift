import Foundation
import SwiftData

/// Turns a synced `Memo` (+ its `MemoAsset` blobs) into a PipelineFile row + an on-disk
/// working folder (the trust logic the old Python backend's `upload_files` had). Does NOT
/// run the pipeline (transcribe/enhance). Pure of FluidAudio/mlx so it unit-tests host-less
/// with an in-memory ModelContext.
///
/// TWO-PHASE by design: `prepare` does ALL the disk I/O (write the audio/images/sidecars)
/// and returns a Sendable descriptor; `commit` does only the SwiftData insert/save — so a
/// big memo's file writes can run off the main actor while SwiftData is still touched from
/// ONE actor with the UI's own `mainContext` (live @Query).
struct UploadService: Sendable {
    var outputDir: URL = AppPaths.audioOutputDirectory

    /// Everything `commit` needs to build one `PipelineFile` row — the on-disk paths
    /// are already written by `prepare`. Sendable so it can cross from a background queue
    /// to the main actor.
    struct PreparedUpload: Sendable {
        var id: String
        var filename: String
        var path: String
        var size: Int
        var sourceType: SourceType
        var metadataJSON: Data? = nil
        /// nil → keep the `PipelineFile` default (upload time).
        var uploadedAt: Date? = nil
        var mediaSource: String? = nil
        var title: String? = nil
        var significance: Double? = nil
        /// Non-nil → set the transcript AND mark transcribe `.done` (a trusted phone
        /// transcript, a typed note's text, or a capture's annotation). nil → leave transcribe `.pending`.
        var transcript: String? = nil
        var wordTimings: [WordTiming] = []
        var diarizationSegments: [DiarizedSegment] = []
    }

    /// What a synced memo becomes — decided once, in `shape`.
    enum Shape {
        case audio(MemoAsset)
        case text
        case capture
    }

    /// One-shot ingest (disk I/O + DB) — used by tests and the CloudKit read bridge.
    /// Both phases run on the caller's thread. The row id is the memo UUID (the contract
    /// spine), so a memo dedups to one row. nil = nothing to ingest yet (see `shape`).
    ///
    /// This file does not author Memos (Q5): `Pipeline/` compiles host-less into the test
    /// bundle, so it must not reach a container-resolving gate. `MacMemoAuthor.backfill`,
    /// hooked into the reconcile sweep, picks up a row from ANY local path.
    @discardableResult
    func ingest(memo: Memo, assets: [MemoAsset], into context: ModelContext) throws -> PipelineFile? {
        guard let prepared = try prepare(memo: memo, assets: assets) else { return nil }
        return try commit([prepared], into: context).first
    }

    // MARK: Phase 1 — disk I/O (no ModelContext; safe off the main actor)

    /// The ONE decision of audio, text or capture.
    /// - audio: an audio asset is present.
    /// - capture: no audio asset and a `sharedContent` blob that parses (URL/text/image/file
    ///   shared into Skrift from another app). Never ASR'd.
    /// - text: no audio asset, no audio FILENAME and no capture payload — a note somebody
    ///   TYPED (`Memo.newTyped`). The `audioFilename.isEmpty` half keeps a voice memo whose
    ///   `MemoAsset` blob has not synced yet from becoming a text row (CloudKit delivers
    ///   assets independently — the 2026-07-25 case trailed by 10½ hours): that row would
    ///   exist, no later sweep would re-ingest it, and its audio would be lost for good.
    /// - nil: a named audio file whose asset is not here yet. No row; the next sweep retries.
    ///
    /// A capture whose payload does not parse falls to text (no audio filename) or nil, so it
    /// can never land between branches into "no row, forever" — the 2026-08-19 hole.
    static func shape(memo: Memo, assets: [MemoAsset]) -> Shape? {
        if let audio = assets.first(where: { $0.kind == MemoAsset.Kind.audio }) { return .audio(audio) }
        if jsonObject(memo.sharedContentData) != nil { return .capture }
        return memo.audioFilename.isEmpty ? .text : nil
    }

    /// Write the memo's files to disk and return the row descriptor, or nil when there is
    /// nothing to ingest yet. NO SwiftData here, so this can run off the main actor.
    func prepare(memo: Memo, assets: [MemoAsset]) throws -> PreparedUpload? {
        guard let shape = Self.shape(memo: memo, assets: assets) else { return nil }
        let id = memo.id.uuidString
        // Raw metadata blob: only the keys `MemoMetadata` does not model are read from it
        // (the `sourceType` / `mediaSource` marker, the photo manifest).
        let blob = Self.jsonObject(memo.metadataData)
        let manifest = (blob?["imageManifest"] as? [[String: Any]]) ?? []
        let photos = assets.filter { $0.kind == MemoAsset.Kind.photo }.sorted { $0.filename < $1.filename }
        let words = memo.transcriptStatus == .done ? (memo.transcript ?? "") : ""

        var prepared: PreparedUpload
        let folder: URL
        switch shape {
        case .audio(let audio):
            let filename = MemoCloudIngest.audioFilename(for: memo)
            folder = outputDir.appendingPathComponent("\(id)_\(filename)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var ext = (filename as NSString).pathExtension
            if ext.isEmpty { ext = "m4a" }
            let original = folder.appendingPathComponent("original.\(ext)")
            try audio.blob.write(to: original)
            // C63 / C148 / D172: a video filed Inspiration / Idea / Project brings its movie
            // (a synced `video` asset). Written as `source.<ext>`, where `VaultExporter` looks.
            if let movie = assets.first(where: { $0.kind == MemoAsset.Kind.video }), !movie.blob.isEmpty {
                try? movie.blob.write(to: folder.appendingPathComponent(
                    VideoKeep.macSourceName(forAssetFilename: movie.filename)))
            }
            let size =((try? FileManager.default.attributesOfItem(atPath: original.path))?[.size] as? Int)
                ?? audio.blob.count
            prepared = PreparedUpload(id: id, filename: filename, path: original.path,
                                      size: size, sourceType: .audio)
            // Unified source taxonomy marker (e.g. "video") → source glyph + label.
            // Either spelling: the phone's `MemoMetadata` writes `sourceType`, the Mac author `mediaSource`.
            prepared.mediaSource = SourceKind.mediaMarker(in: blob)
            // The phone sends NO `sanitised` (the Mac links names). The trust gate decides
            // whether its transcript stands in for the Mac's own transcribe step.
            if !words.isEmpty,
               Memo.isTrustedTranscript(userEdited: memo.transcriptUserEdited,
                                        confidence: memo.transcriptConfidence) {
                prepared.transcript = words   // → commit marks transcribe .done
                // Optional ADDITIVE sidecars, only meaningful for a trusted transcript (the Mac
                // would otherwise re-ASR + re-diarize): the phone's word-timings drive Mac
                // karaoke/read-along; its diarization lets the Mac enroll a speaker's voice
                // from a phone-diarized conversation WITHOUT re-diarizing.
                if let wt = assets.first(where: { $0.kind == MemoAsset.Kind.wordTimings }), !wt.blob.isEmpty,
                   let decoded = try? JSONDecoder().decode([WordTiming].self, from: wt.blob) {
                    prepared.wordTimings = decoded
                }
                if let dz = assets.first(where: { $0.kind == MemoAsset.Kind.diarization }), !dz.blob.isEmpty,
                   let data = try? JSONDecoder().decode(PhoneDiarizationBlob.self, from: dz.blob) {
                    prepared.diarizationSegments = data.segments
                }
            }

        case .text:
            // A memo with words but no media of its own, shaped exactly like
            // `IngestService.ingestNote` (an Apple Note import): the body is written to
            // `original.md` in the row's working folder and set as the transcript, so
            // `transcribe` is `.done` (nothing to hear) and every downstream reader — the
            // body-precedence chain, `VaultExporter`, the working-folder machinery — works
            // through its ordinary path with no special case.
            folder = outputDir.appendingPathComponent("\(id)_note", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let dest = folder.appendingPathComponent("original.md")
            try Data(words.utf8).write(to: dest)
            prepared = PreparedUpload(id: id, filename: "\(id).md", path: dest.path,
                                      size: words.utf8.count, sourceType: .note)
            // The typed marker (`mediaSource: "typed"`, written by `Memo.newTyped`) keeps the
            // row's glyph + label "Note" instead of "Apple Note" — a `.note` row's only other
            // population. Read from `mediaSource`, the key the memo blob actually carries.
            if let media = (blob?["mediaSource"] as? String)?.trimmingCharacters(in: .whitespaces),
               !media.isEmpty {
                prepared.mediaSource = media
            }
            // A typed note is somebody's own writing — the trust gate has nothing to weigh, so
            // the text is the transcript outright (→ transcribe `.done` in `commit`).
            prepared.transcript = words

        case .capture:
            let folderName = "capture_\(id)"
            folder = outputDir.appendingPathComponent(folderName, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // A shared `.file` capture's document (3b): written under `files/` so the Mac can
            // OPEN the real file — the phone's A6 already put its text in the body.
            if let doc = assets.first(where: { $0.kind == MemoAsset.Kind.document }), !doc.blob.isEmpty {
                let dir = folder.appendingPathComponent("files", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? doc.blob.write(to: dir.appendingPathComponent(doc.filename))
            }
            // A link capture's thumbnail (Q260): beside the capture, where `captureThumbnailURL`
            // looks — never under `images/`, which is the photo manifest's folder.
            if let thumb = assets.first(where: { $0.kind == MemoAsset.Kind.thumbnail }), !thumb.blob.isEmpty,
               !thumb.filename.isEmpty, !thumb.filename.contains("/") {
                try? thumb.blob.write(to: folder.appendingPathComponent(thumb.filename))
            }
            prepared = PreparedUpload(id: id, filename: folderName, path: folder.path,
                                      size: 0, sourceType: .capture)
            // The annotation is already written text — the transcript, so the body-precedence
            // chain (sanitised → copyedit → transcript) works as for memos. Non-nil even when
            // empty, so ASR is permanently skipped (transcribe .done in `commit`).
            prepared.transcript = memo.annotationText ?? ""
        }

        prepared.metadataJSON = MemoCloudIngest.metadataJSON(for: memo)   // → pf.audioMetadataJSON
        if case .capture = shape {
            // A capture keeps the upload-time date and carries no title of its own.
        } else {
            // The memo's CONTENT date, not the upload time: a video imported from Photos keeps
            // its filming date (the extracted m4a has no embedded date to backfill from).
            prepared.uploadedAt = memo.recordedAt
            // A user-set title: BatchRunner won't clobber a pre-set enhancedTitle (the LLM
            // title becomes the suggestion).
            if let title = memo.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                prepared.title = title
            }
        }
        // Flag-to-process: pre-fill the review slider. 0 (a "process everything" memo) stays nil.
        if memo.significance > 0 { prepared.significance = memo.significance }

        // Photos (a memo's, a typed note's pasted ones, an image capture's): the same `images/`
        // folder + manifest for every row, so `[[img_NNN]]` markers resolve and reach the vault.
        try saveImages(photos, manifest: manifest, into: folder)
        return prepared
    }

    // MARK: Phase 2 — SwiftData insert/save (main actor in the app)

    /// Insert the prepared descriptors as `PipelineFile` rows and save. The only
    /// SwiftData touch — the app marshals this onto the main actor with the UI's
    /// own `mainContext`, so phone uploads appear live via @Query.
    @discardableResult
    func commit(_ prepared: [PreparedUpload], into context: ModelContext) throws -> [PipelineFile] {
        var created: [PipelineFile] = []
        for p in prepared {
            let pf = PipelineFile(id: p.id, filename: p.filename, path: p.path,
                                  size: p.size, sourceType: p.sourceType)
            if let m = p.metadataJSON { pf.audioMetadataJSON = m }
            if let d = p.uploadedAt { pf.uploadedAt = d }
            if let s = p.mediaSource { pf.mediaSource = s }
            if let t = p.title { pf.enhancedTitle = t }
            if let sig = p.significance { pf.significance = sig }
            if let tr = p.transcript {
                pf.transcript = tr
                pf.transcribeStatus = .done
            }
            if !p.wordTimings.isEmpty { pf.wordTimings = p.wordTimings }
            if !p.diarizationSegments.isEmpty { pf.diarizationSegments = p.diarizationSegments }
            context.insert(pf)
            created.append(pf)
        }
        try context.save()
        return created
    }

    private static func jsonObject(_ data: Data?) -> [String: Any]? {
        data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
    }

    private func saveImages(_ images: [MemoAsset], manifest: [[String: Any]], into folder: URL) throws {
        guard !images.isEmpty else { return }
        let dir = folder.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var saved: [[String: Any]] = []
        for (i, img) in images.enumerated() {
            let entry = i < manifest.count ? manifest[i] : [:]
            let name = (entry["filename"] as? String)
                ?? (img.filename.isEmpty ? String(format: "img_%03d.jpg", i + 1) : img.filename)
            try img.blob.write(to: dir.appendingPathComponent(name))
            saved.append(["filename": name, "offsetSeconds": entry["offsetSeconds"] ?? 0])
        }
        let data = try JSONSerialization.data(withJSONObject: saved, options: [.prettyPrinted])
        try data.write(to: folder.appendingPathComponent("image_manifest.json"))
    }
}
