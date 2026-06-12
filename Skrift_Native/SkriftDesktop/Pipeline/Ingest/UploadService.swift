import Foundation
import SwiftData

/// Turns a parsed multipart upload into PipelineFile rows + on-disk working
/// folders. Mirrors `backend/api/files.py:upload_files` trust logic. Does NOT run
/// the pipeline (transcribe/enhance) — that's Phase 3+. Pure of FluidAudio/mlx so
/// it unit-tests host-less with an in-memory ModelContext.
struct UploadService: Sendable {
    var outputDir: URL = AppPaths.audioOutputDirectory

    @discardableResult
    func ingest(parts: [MultipartPart], into context: ModelContext) throws -> [PipelineFile] {
        let metadataPart = parts.first { $0.name == "metadata" }
        let meta = metadataPart.flatMap { (try? JSONSerialization.jsonObject(with: $0.data)) as? [String: Any] }
        let transcript = parts.first { $0.name == "transcript" }
            .flatMap { String(data: $0.data, encoding: .utf8) }
        let trusted = isTranscriptTrusted(meta)

        let imageParts = parts.filter { $0.name == "images" && $0.filename != nil }
        let manifest = (meta?["imageManifest"] as? [[String: Any]]) ?? []

        // C3 CAPTURE discriminator: zero audio `files` parts + `sharedContent` present
        // in the metadata → this is a capture (URL/text/image shared into Skrift from
        // another app). The absence of audio is intentional — do NOT attempt ASR.
        // Memo uploads with audio remain BYTE-IDENTICAL in behavior (new branch only).
        let audioParts = parts.filter { $0.name == "files" && $0.filename != nil }
        if audioParts.isEmpty, let sharedContent = meta?["sharedContent"] as? [String: Any] {
            let pf = try ingestCapture(meta: meta, sharedContent: sharedContent,
                                       metadataPart: metadataPart,
                                       imageParts: imageParts, manifest: manifest)
            context.insert(pf)
            try context.save()
            return [pf]
        }

        var created: [PipelineFile] = []
        for audio in audioParts {
            let filename = audio.filename ?? "memo.m4a"
            let id = UUID().uuidString
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
            let pf = PipelineFile(id: id, filename: filename, path: original.path,
                                  size: size, sourceType: .audio)
            if let metaData = metadataPart?.data { pf.audioMetadataJSON = metaData }   // verbatim passthrough
            // Phone may send an optional user-set `title` — honor it (BatchRunner
            // won't clobber a pre-set enhancedTitle; the LLM title becomes the suggestion).
            if let title = (meta?["title"] as? String)?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
                pf.enhancedTitle = title
            }
            // Phone sends a `significance` rating (flag-to-send gating means it's
            // always > 0 when present) — pre-fill the review slider with it.
            if let sig = (meta?["significance"] as? NSNumber)?.doubleValue {
                pf.significance = sig
            }

            // Phone sends NO `sanitised` (Mac links names). Trusted transcript skips
            // the Mac's own transcribe step.
            if let transcript, trusted {
                pf.transcript = transcript
                pf.transcribeStatus = .done
            }

            try saveImages(imageParts, manifest: manifest, into: folder)
            context.insert(pf)
            created.append(pf)
        }
        try context.save()
        return created
    }

    // MARK: Capture ingest (C3)

    /// Build ONE PipelineFile for a capture upload. The annotation is already text (no
    /// ASR needed), so `transcribeStatus` is pre-set to `.done`. Images (for image-type
    /// captures) are saved under the working folder's `images/` using the same
    /// `saveImages` path as memo photo uploads — VaultExporter picks them up identically.
    private func ingestCapture(
        meta: [String: Any]?,
        sharedContent: [String: Any],
        metadataPart: MultipartPart?,
        imageParts: [MultipartPart],
        manifest: [[String: Any]]
    ) throws -> PipelineFile {
        let id = UUID().uuidString
        let folderName = "capture_\(id)"
        let folder = outputDir.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let annotation = (meta?["annotationText"] as? String) ?? ""
        let pf = PipelineFile(id: id, filename: folderName, path: folder.path, size: 0,
                              sourceType: .capture)
        if let metaData = metadataPart?.data { pf.audioMetadataJSON = metaData }   // verbatim passthrough

        // Annotation is already written text — treat it as the transcript so the
        // pipeline body-precedence chain (sanitised → copyedit → transcript) works
        // the same way it does for memos. ASR is permanently skipped.
        pf.transcript = annotation
        pf.transcribeStatus = .done

        // Significance from the sheet (flag-to-send gating means it's always > 0 here).
        if let sig = (meta?["significance"] as? NSNumber)?.doubleValue {
            pf.significance = sig
        }

        // Image captures travel with one `images` part; save it under `images/` so
        // VaultExporter's existing convertImageMarkers path can copy it on export.
        if !imageParts.isEmpty {
            try saveImages(imageParts, manifest: manifest, into: folder)
        }

        return pf
    }

    /// Trust = `transcriptUserEdited || transcriptConfidence >= 0.7` (api/files.py).
    func isTranscriptTrusted(_ meta: [String: Any]?) -> Bool {
        if (meta?["transcriptUserEdited"] as? Bool) == true { return true }
        if let n = meta?["transcriptConfidence"] as? NSNumber { return n.doubleValue >= 0.7 }
        return false
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
