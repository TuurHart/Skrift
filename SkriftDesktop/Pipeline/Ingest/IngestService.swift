import Foundation
import SwiftData

/// Desktop-side ingest for locally-picked files/folders (the +Upload button and
/// drag-drop). Mirrors `UploadService`'s on-disk layout — one `<id>_<filename>/`
/// folder per note with `original.<ext>` — so desktop and phone ingest produce
/// identical PipelineFiles. Pure (FileManager + ModelContext, no engines) so it
/// unit-tests host-less.
struct IngestService: Sendable {
    var outputDir: URL = AppPaths.audioOutputDirectory

    static let supportedAudio: Set<String> = ["m4a", "wav", "mp3", "mp4", "mov", "opus", "aac", "aiff", "caf"]

    @discardableResult
    func ingest(localURLs: [URL], into context: ModelContext) throws -> [PipelineFile] {
        var created: [PipelineFile] = []
        for url in localURLs {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                created.append(contentsOf: try ingestFolder(url, into: context))
            } else if let pf = try ingestFile(url, into: context) {
                created.append(pf)
            }
        }
        try context.save()
        return created
    }

    /// A single file → one PipelineFile (audio or Apple-Note markdown). Unsupported
    /// types are skipped (returns nil).
    func ingestFile(_ url: URL, into context: ModelContext) throws -> PipelineFile? {
        let ext = url.pathExtension.lowercased()
        if Self.supportedAudio.contains(ext) { return try ingestAudio(url, into: context) }
        if ext == "md" || ext == "markdown" { return try ingestNote(url, into: context) }
        return nil
    }

    private func ingestAudio(_ url: URL, into context: ModelContext) throws -> PipelineFile {
        let filename = url.lastPathComponent
        let id = UUID().uuidString
        let (folder, _) = try makeFolder(id: id, filename: filename)
        var ext = url.pathExtension
        if ext.isEmpty { ext = "m4a" }
        let dest = folder.appendingPathComponent("original.\(ext)")
        try FileManager.default.copyItem(at: url, to: dest)
        let size = ((try? FileManager.default.attributesOfItem(atPath: dest.path))?[.size] as? Int) ?? 0
        let pf = PipelineFile(id: id, filename: filename, path: dest.path, size: size, sourceType: .audio)
        context.insert(pf)
        return pf
    }

    private func ingestNote(_ url: URL, into context: ModelContext) throws -> PipelineFile {
        let filename = url.lastPathComponent
        let id = UUID().uuidString
        let (folder, _) = try makeFolder(id: id, filename: filename)
        let dest = folder.appendingPathComponent("original.md")
        try FileManager.default.copyItem(at: url, to: dest)
        let content = (try? String(contentsOf: dest, encoding: .utf8)) ?? ""
        let pf = PipelineFile(id: id, filename: filename, path: dest.path,
                              size: content.utf8.count, sourceType: .note)
        // Apple notes arrive already "transcribed" — the markdown body is the text.
        pf.transcript = content
        pf.transcribeStatus = .done
        // Title from the first `# ` heading, else the filename stem (apple_notes_importer.py).
        // BatchRunner won't clobber this; the LLM title becomes the suggestion.
        pf.enhancedTitle = Self.appleNoteTitle(content, fallback: (filename as NSString).deletingPathExtension)
        // (Attachment rename + HEIC→JPG conversion from the Python importer is a follow-up.)
        context.insert(pf)
        return pf
    }

    /// First `# ` heading (trailing dots trimmed), else the fallback. Mirrors
    /// `apple_notes_importer.parse_markdown_note`.
    static func appleNoteTitle(_ content: String, fallback: String) -> String {
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("# ") {
                let t = String(s.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if !t.isEmpty { return t }
            }
        }
        return fallback
    }

    /// A picked folder (e.g. an Apple Notes export) → ingest its `.md` files.
    private func ingestFolder(_ url: URL, into context: ModelContext) throws -> [PipelineFile] {
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        var created: [PipelineFile] = []
        for item in items where ["md", "markdown"].contains(item.pathExtension.lowercased()) {
            if let pf = try ingestFile(item, into: context) { created.append(pf) }
        }
        return created
    }

    private func makeFolder(id: String, filename: String) throws -> (URL, String) {
        let folder = outputDir.appendingPathComponent("\(id)_\(filename)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (folder, id)
    }
}
