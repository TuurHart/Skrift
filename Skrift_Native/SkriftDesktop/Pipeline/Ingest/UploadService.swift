import Foundation
import SwiftData

/// Turns a parsed multipart upload into PipelineFile rows + on-disk working
/// folders (the old Python backend's `upload_files` trust logic). Does NOT run the
/// pipeline (transcribe/enhance). Pure of FluidAudio/mlx so it unit-tests host-less with
/// an in-memory ModelContext.
///
/// TWO-PHASE by design: `prepare` does ALL the disk I/O (write the audio/images/sidecars,
/// extract video) and returns Sendable descriptors; `commit` does only the SwiftData
/// insert/save — so a big upload's file writes can run off the main actor while SwiftData
/// is still touched from ONE actor with the UI's own `mainContext` (live @Query).
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
        /// transcript, or a capture's annotation). nil → leave transcribe `.pending`.
        var transcript: String? = nil
        var wordTimings: [WordTiming] = []
        var diarizationSegments: [DiarizedSegment] = []
    }

    /// One-shot ingest (disk I/O + DB) — used by tests and the CloudKit read bridge.
    /// Both phases run on the caller's thread. `memoID` forces the row id (the CloudKit
    /// bridge keys on the memo UUID, the contract spine); nil = a random id.
    ///
    /// This file does not author Memos (Q5): `Pipeline/` compiles host-less into the test
    /// bundle, so it must not reach a container-resolving gate. `MacMemoAuthor.backfill`,
    /// hooked into the reconcile sweep, picks up a row from ANY local path.
    @discardableResult
    func ingest(parts: [MultipartPart], into context: ModelContext, memoID: String? = nil,
                textOnly: Bool = false) throws -> [PipelineFile] {
        try commit(prepare(parts: parts, memoID: memoID, textOnly: textOnly), into: context)
    }

    // MARK: Phase 1 — disk I/O (no ModelContext; safe off the main actor)

    /// Write every upload part to disk and return the row descriptors. NO SwiftData
    /// here, so this can run off the main actor.
    func prepare(parts: [MultipartPart], memoID: String? = nil,
                 textOnly: Bool = false) throws -> [PreparedUpload] {
        let metadataPart = parts.first { $0.name == "metadata" }
        let meta = metadataPart.flatMap { (try? JSONSerialization.jsonObject(with: $0.data)) as? [String: Any] }
        let transcript = parts.first { $0.name == "transcript" }
            .flatMap { String(data: $0.data, encoding: .utf8) }
        let trusted = isTranscriptTrusted(meta)

        let imageParts = parts.filter { $0.name == "images" && $0.filename != nil }
        let manifest = (meta?["imageManifest"] as? [[String: Any]]) ?? []
        let documentPart = parts.first { $0.name == "document" && $0.filename != nil }   // .file capture (3b)
        let thumbnailPart = parts.first { $0.name == "thumbnail" && $0.filename != nil }  // link card image (Q260)

        // C3 CAPTURE discriminator: zero audio `files` parts + `sharedContent` present
        // in the metadata → this is a capture (URL/text/image shared into Skrift from
        // another app). The absence of audio is intentional — do NOT attempt ASR.
        // Memo uploads with audio remain BYTE-IDENTICAL in behavior (new branch only).
        let audioParts = parts.filter { $0.name == "files" && $0.filename != nil }
        if audioParts.isEmpty, meta?["sharedContent"] is [String: Any] {
            return [try prepareCapture(id: memoID ?? UUID().uuidString, meta: meta,
                                       metadataPart: metadataPart,
                                       imageParts: imageParts, manifest: manifest,
                                       documentPart: documentPart, thumbnailPart: thumbnailPart)]
        }

        // TEXT-ONLY: a note somebody TYPED (the ✎/⌘N verb on either app, `Memo.newTyped`) —
        // no audio and no `sharedContent`. Before this branch both arms above missed it and
        // `prepare` returned an EMPTY array, so `MemoCloudIngest.ingest` handed back nil on
        // every sweep, forever: rating such a note produced no row (no Process verb, no queue
        // section) while the rating removed it from the quiet unrated rows — invisible in
        // every list section, which reads exactly like data loss (Tuur, 2026-08-19). An
        // Apple-Note-shaped `.note` row is the honest answer: the text IS the body, and the
        // pipeline (enhance → compile → export) then runs it like any imported note.
        //
        // `textOnly` is the CALLER's answer, never sniffed from the parts: "no audio part"
        // also describes a voice memo whose `MemoAsset` blob hasn't synced yet (CloudKit
        // delivers assets independently — the 2026-07-25 case trailed by 10½ hours), and
        // turning one of those into a text row would strand its audio permanently, since the
        // row then exists and no later sweep re-ingests it. Only `MemoCloudIngest`, which can
        // see that the memo has no audio AT ALL, passes true.
        if audioParts.isEmpty, textOnly, let id = memoID {
            return [try prepareText(id: id, meta: meta, metadataPart: metadataPart,
                                    transcript: transcript,
                                    imageParts: imageParts, manifest: manifest)]
        }

        var out: [PreparedUpload] = []
        for audio in audioParts {
            out.append(try prepareAudio(audio, id: memoID ?? UUID().uuidString, meta: meta,
                                        metadataPart: metadataPart, transcript: transcript,
                                        trusted: trusted, parts: parts,
                                        imageParts: imageParts, manifest: manifest))
        }
        return out
    }

    private func prepareAudio(_ audio: MultipartPart, id: String, meta: [String: Any]?,
                              metadataPart: MultipartPart?, transcript: String?, trusted: Bool,
                              parts: [MultipartPart], imageParts: [MultipartPart],
                              manifest: [[String: Any]]) throws -> PreparedUpload {
        let filename = audio.filename ?? "memo.m4a"
        let folder = outputDir.appendingPathComponent("\(id)_\(filename)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var ext = (filename as NSString).pathExtension
        if ext.isEmpty { ext = "m4a" }
        var original = folder.appendingPathComponent("original.\(ext)")
        try audio.data.write(to: original)

        // A directly-uploaded VIDEO (a future share-extension might send one):
        // strip its audio to `original.m4a` so the pipeline only ever transcribes
        // audio. The phone's own video import already extracts audio before
        // uploading, so this is a belt-and-braces path. Falls through to treating
        // the file as audio if it's audio-only or extraction fails.
        if IngestService.supportedVideo.contains(ext.lowercased()), IngestService.hasVideoTrack(original) {
            let extracted = folder.appendingPathComponent("original.m4a")
            if (try? IngestService.extractAudioSync(from: original, to: extracted)) != nil {
                try? FileManager.default.removeItem(at: original)
                original = extracted
            }
        }

        let size = ((try? FileManager.default.attributesOfItem(atPath: original.path))?[.size] as? Int) ?? audio.data.count
        var prepared = PreparedUpload(id: id, filename: filename, path: original.path,
                                      size: size, sourceType: .audio)
        prepared.metadataJSON = metadataPart?.data   // verbatim passthrough
        // Use the phone's CONTENT date (recordedAt), not the upload time — a video
        // imported from Photos keeps its filming date (e.g. yesterday), so the Mac
        // must show that, not "today". (The phone's extracted m4a has no embedded
        // date to backfill from, so this is the only correct source.)
        if let rec = (meta?["recordedAt"] as? String).flatMap(ISO8601.date(from:)) {
            prepared.uploadedAt = rec
        }
        // Unified source taxonomy marker (e.g. "video") → source glyph + label.
        // Either spelling: the phone's `MemoMetadata` writes `sourceType`, the Mac author `mediaSource`.
        if let src = SourceKind.mediaMarker(in: meta) {
            prepared.mediaSource = src
        }
        // Phone may send an optional user-set `title` — honor it (BatchRunner
        // won't clobber a pre-set enhancedTitle; the LLM title becomes the suggestion).
        if let title = (meta?["title"] as? String)?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
            prepared.title = title
        }
        // Phone sends a `significance` rating (flag-to-send gating means it's
        // always > 0 when present) — pre-fill the review slider with it.
        if let sig = (meta?["significance"] as? NSNumber)?.doubleValue {
            prepared.significance = sig
        }

        // Phone sends NO `sanitised` (Mac links names). Trusted transcript skips
        // the Mac's own transcribe step.
        if let transcript, trusted {
            prepared.transcript = transcript   // → commit marks transcribe .done

            // Optional ADDITIVE parts (older builds omit them — byte-compatible):
            // `wordTimings` (the phone's ASR word-timings) drives Mac karaoke/read-along
            // on a trusted memo the Mac never re-transcribes; `diar` (the phone's
            // diarization sidecar) lets the Mac enroll a speaker's voice from a
            // phone-diarized conversation WITHOUT re-diarizing. Both only meaningful
            // for a trusted transcript (the Mac would otherwise re-ASR + re-diarize).
            if let wt = parts.first(where: { $0.name == "wordTimings" && $0.filename == nil }),
               let words = try? JSONDecoder().decode([WordTiming].self, from: wt.data) {
                prepared.wordTimings = words
            }
            if let dz = parts.first(where: { $0.name == "diar" && $0.filename == nil }),
               let data = try? JSONDecoder().decode(DiarizationData.self, from: dz.data) {
                prepared.diarizationSegments = data.segments
                DiarizationSidecar().write(data, in: folder, id: id)   // portable + enroll copy
            }
        }

        try saveImages(imageParts, manifest: manifest, into: folder)
        return prepared
    }

    /// Build ONE text-note descriptor — a memo with words but no media of its own.
    /// Shaped exactly like `IngestService.ingestNote` (an Apple Note import): the body is
    /// written to `original.md` inside the row's working folder and set as the transcript,
    /// so `transcribe` is `.done` (there is nothing to hear) and every downstream reader —
    /// the body-precedence chain, `VaultExporter`, the working-folder machinery — works
    /// through its ordinary path with no special case.
    ///
    /// Only reachable from the CloudKit bridge (`textOnly` + an explicit `memoID`): an
    /// HTTP-shaped upload carrying neither audio nor `sharedContent` is a malformed
    /// request, and keeping it at zero rows preserves that.
    private func prepareText(id: String, meta: [String: Any]?, metadataPart: MultipartPart?,
                             transcript: String?, imageParts: [MultipartPart],
                             manifest: [[String: Any]]) throws -> PreparedUpload {
        let body = transcript ?? ""
        let folder = outputDir.appendingPathComponent("\(id)_note", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appendingPathComponent("original.md")
        try Data(body.utf8).write(to: dest)

        var prepared = PreparedUpload(id: id, filename: "\(id).md", path: dest.path,
                                      size: body.utf8.count, sourceType: .note)
        prepared.metadataJSON = metadataPart?.data   // verbatim passthrough
        // The typed marker (`mediaSource: "typed"`, written by `Memo.newTyped`) is what
        // keeps the row's glyph + label "Note" instead of "Apple Note" — a `.note` row's
        // only other population. Read from `mediaSource`, the key the memo blob actually
        // carries (`SourceKind.of`); `prepareAudio`'s `sourceType` key is the phone's
        // separate upload-metadata spelling.
        if let media = (meta?["mediaSource"] as? String)?.trimmingCharacters(in: .whitespaces),
           !media.isEmpty {
            prepared.mediaSource = media
        }
        if let rec = (meta?["recordedAt"] as? String).flatMap(ISO8601.date(from:)) {
            prepared.uploadedAt = rec
        }
        if let title = (meta?["title"] as? String)?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
            prepared.title = title
        }
        if let sig = (meta?["significance"] as? NSNumber)?.doubleValue {
            prepared.significance = sig
        }
        // A typed note is somebody's own writing — the trust gate has nothing to weigh, so
        // the text is the transcript outright (→ transcribe `.done` in `commit`), exactly
        // as a capture's annotation is.
        prepared.transcript = body
        // Photos pasted into a typed note: same `images/` folder + manifest every other
        // row uses, so the `[[img_NNN]]` markers resolve and reach the vault on export.
        if !imageParts.isEmpty {
            try saveImages(imageParts, manifest: manifest, into: folder)
        }
        return prepared
    }

    /// Build ONE capture descriptor. The annotation is already text (no ASR needed),
    /// so the transcript is set (→ transcribe `.done` in `commit`). Images (for
    /// image-type captures) are saved under the working folder's `images/` using the
    /// same `saveImages` path as memo photo uploads.
    private func prepareCapture(id: String, meta: [String: Any]?, metadataPart: MultipartPart?,
                                imageParts: [MultipartPart], manifest: [[String: Any]],
                                documentPart: MultipartPart? = nil,
                                thumbnailPart: MultipartPart? = nil) throws -> PreparedUpload {
        let folderName = "capture_\(id)"
        let folder = outputDir.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // A shared `.file` capture's document (3b): write it under the working folder's `files/`
        // so the Mac can OPEN the real file — the phone's A6 already put its text in the body.
        if let doc = documentPart, let name = doc.filename {
            let dir = folder.appendingPathComponent("files", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? doc.data.write(to: dir.appendingPathComponent(name))
        }
        // A link capture's thumbnail (Q260): beside the capture, where `captureThumbnailURL`
        // looks — never under `images/`, which is the photo manifest's folder.
        if let thumb = thumbnailPart, let name = thumb.filename,
           !name.isEmpty, !name.contains("/") {
            try? thumb.data.write(to: folder.appendingPathComponent(name))
        }

        let annotation = (meta?["annotationText"] as? String) ?? ""
        var prepared = PreparedUpload(id: id, filename: folderName, path: folder.path,
                                      size: 0, sourceType: .capture)
        prepared.metadataJSON = metadataPart?.data   // verbatim passthrough
        // Annotation is already written text — treat it as the transcript so the
        // pipeline body-precedence chain (sanitised → copyedit → transcript) works
        // the same way it does for memos. ASR is permanently skipped (transcript
        // non-nil, even when empty → transcribe .done in commit).
        prepared.transcript = annotation
        // Significance from the sheet (flag-to-send gating means it's always > 0 here).
        if let sig = (meta?["significance"] as? NSNumber)?.doubleValue {
            prepared.significance = sig
        }
        // Image captures travel with one `images` part; save it under `images/` so
        // VaultExporter's existing convertImageMarkers path can copy it on export.
        if !imageParts.isEmpty {
            try saveImages(imageParts, manifest: manifest, into: folder)
        }
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

    /// The shared trust gate (`Memo.isTrustedTranscript`) read off the upload metadata.
    func isTranscriptTrusted(_ meta: [String: Any]?) -> Bool {
        Memo.isTrustedTranscript(
            userEdited: (meta?["transcriptUserEdited"] as? Bool) == true,
            confidence: (meta?["transcriptConfidence"] as? NSNumber)?.doubleValue)
    }

    private func saveImages(_ images: [MultipartPart], manifest: [[String: Any]], into folder: URL) throws {
        guard !images.isEmpty else { return }
        let dir = folder.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var saved: [[String: Any]] = []
        for (i, img) in images.enumerated() {
            let entry = i < manifest.count ? manifest[i] : [:]
            let name = (entry["filename"] as? String) ?? img.filename ?? String(format: "img_%03d.jpg", i + 1)
            try img.data.write(to: dir.appendingPathComponent(name))
            saved.append(["filename": name, "offsetSeconds": entry["offsetSeconds"] ?? 0])
        }
        let data = try JSONSerialization.data(withJSONObject: saved, options: [.prettyPrinted])
        try data.write(to: folder.appendingPathComponent("image_manifest.json"))
    }
}
