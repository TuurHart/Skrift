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

        var created: [PipelineFile] = []
        for audio in parts where audio.name == "files" && audio.filename != nil {
            let filename = audio.filename ?? "memo.m4a"
            let id = UUID().uuidString
            let folder = outputDir.appendingPathComponent("\(id)_\(filename)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            var ext = (filename as NSString).pathExtension
            if ext.isEmpty { ext = "m4a" }
            let original = folder.appendingPathComponent("original.\(ext)")
            try audio.data.write(to: original)

            let pf = PipelineFile(id: id, filename: filename, path: original.path,
                                  size: audio.data.count, sourceType: .audio)
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
