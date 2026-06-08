import Foundation
import SwiftData
import ImageIO
import UniformTypeIdentifiers

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
        // Baseline date: a date in the filename (WhatsApp/Signal/recorder names),
        // else the source file's creation date (right for fresh memos), else now. The
        // app then backfills the EMBEDDED recording date (AudioMetadata) when present,
        // which is correct even for copied/ported Apple recordings.
        let recorded = Self.dateFromFilename(filename)
            ?? (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            ?? Date()
        let pf = PipelineFile(id: id, filename: filename, path: dest.path, size: size,
                              sourceType: .audio, uploadedAt: recorded)
        context.insert(pf)
        return pf
    }

    private func ingestNote(_ url: URL, into context: ModelContext) throws -> PipelineFile {
        let filename = url.lastPathComponent
        let id = UUID().uuidString
        let (folder, _) = try makeFolder(id: id, filename: filename)
        let dest = folder.appendingPathComponent("original.md")
        try FileManager.default.copyItem(at: url, to: dest)
        var content = (try? String(contentsOf: dest, encoding: .utf8)) ?? ""
        // Title from the first `# ` heading, else the filename stem (apple_notes_importer.py).
        let title = Self.appleNoteTitle(content, fallback: (filename as NSString).deletingPathExtension)

        // Copy the note's sibling `Attachments/` into the working folder, renamed to
        // "<safe title> - <index>.<ext>" (HEIC/HEIF → JPG via sips), and rewrite the
        // markdown refs. Mirrors apple_notes_importer.parse_markdown_note, but COPIES
        // (never mutates the user's source export). Re-persist the rewritten markdown.
        content = Self.importAttachments(
            content: content,
            from: url.deletingLastPathComponent().appendingPathComponent("Attachments", isDirectory: true),
            into: folder.appendingPathComponent("Attachments", isDirectory: true),
            safeTitle: Self.sanitizeTitle(title)
        )
        try? Data(content.utf8).write(to: dest)

        let pf = PipelineFile(id: id, filename: filename, path: dest.path,
                              size: content.utf8.count, sourceType: .note)
        // Apple notes arrive already "transcribed" — the markdown body is the text.
        pf.transcript = content
        pf.transcribeStatus = .done
        // BatchRunner won't clobber this; the LLM title becomes the suggestion.
        pf.enhancedTitle = title
        context.insert(pf)
        return pf
    }

    /// Best-effort recording date parsed from common messaging/recorder filenames,
    /// e.g. "WhatsApp Audio 2025-12-18 at 18.30.44", "signal-2026-04-13-18-15-24-552",
    /// "AUDIO-2026-03-07-19-30-08". Local time; time defaults to noon if absent. nil
    /// when no `YYYY-MM-DD` is present (so a plain "New Recording 22" falls through).
    static func dateFromFilename(_ name: String) -> Date? {
        guard let rx = try? NSRegularExpression(
            pattern: #"(\d{4})-(\d{2})-(\d{2})(?:[ _\-]?(?:at )?(\d{2})[.\-:](\d{2})[.\-:](\d{2}))?"#) else { return nil }
        let ns = name as NSString
        guard let m = rx.firstMatch(in: name, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func g(_ i: Int) -> Int? { let r = m.range(at: i); return r.location == NSNotFound ? nil : Int(ns.substring(with: r)) }
        guard let y = g(1), let mo = g(2), let d = g(3), (1...12).contains(mo), (1...31).contains(d) else { return nil }
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d
        c.hour = g(4) ?? 12; c.minute = g(5) ?? 0; c.second = g(6) ?? 0
        return Calendar.current.date(from: c)
    }

    /// Filename-safe title: illegal chars → "-", whitespace collapsed, edges trimmed.
    /// Mirrors `apple_notes_importer`'s `safe_title`.
    static func sanitizeTitle(_ title: String) -> String {
        let illegal = Set("\\/:*?\"<>|")
        let replaced = String(title.map { illegal.contains($0) ? "-" : $0 })
        let collapsed = replaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        return trimmed.isEmpty ? "note" : trimmed
    }

    /// Copy each file in `srcDir` into `destDir` renamed "<safeTitle> - <i>.<ext>"
    /// (HEIC/HEIF → JPG via `sips`), then rewrite the markdown `(Attachments/<orig>)`
    /// refs (plain + URL-encoded) to the new names. Returns the rewritten content;
    /// a no-op (returns `content`) when there's no Attachments dir. Copies — never
    /// mutates the source export.
    static func importAttachments(content: String, from srcDir: URL, into destDir: URL, safeTitle: String) -> String {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: srcDir.path, isDirectory: &isDir), isDir.boolValue else { return content }
        let files = ((try? fm.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { return content }
        try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        var updated = content
        for (i, src) in files.enumerated() {
            let ext = src.pathExtension.lowercased()
            let isHEIC = (ext == "heic" || ext == "heif")
            var outExt = (isHEIC ? "jpg" : ext)
            if outExt.isEmpty { outExt = "bin" }
            var newName = "\(safeTitle) - \(i + 1).\(outExt)"
            var dest = destDir.appendingPathComponent(newName)

            var ok = false
            if isHEIC {
                try? fm.removeItem(at: dest)
                ok = convertToJPEG(src: src, dst: dest)
                if !ok {   // sips unavailable/failed — keep the original file + ext
                    outExt = ext.isEmpty ? "bin" : ext
                    newName = "\(safeTitle) - \(i + 1).\(outExt)"
                    dest = destDir.appendingPathComponent(newName)
                }
            }
            if !ok {
                try? fm.removeItem(at: dest)
                ok = ((try? fm.copyItem(at: src, to: dest)) != nil)
            }
            guard ok else { continue }

            let orig = src.lastPathComponent
            let encoded = orig.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? orig
            for oldRef in Set(["Attachments/\(orig)", "Attachments/\(encoded)"]) {
                updated = updated.replacingOccurrences(of: "(\(oldRef))", with: "(Attachments/\(newName))")
            }
        }
        return updated
    }

    /// Convert an image (e.g. an Apple-Notes HEIC attachment) to JPEG using native
    /// ImageIO — no `/usr/bin/sips` subprocess (faster, dependency-free, survives a
    /// future sandbox). Returns false if the source can't be decoded or the write fails.
    private static func convertToJPEG(src: URL, dst: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let dest = CGImageDestinationCreateWithURL(dst as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(dest)
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

    /// A picked folder → ingest its top-level supported files: Apple-Note `.md`
    /// exports AND audio recordings (e.g. dropping a folder of voice memos). Skips
    /// subfolders (an Apple Notes export's `Attachments/` images aren't notes).
    private func ingestFolder(_ url: URL, into context: ModelContext) throws -> [PipelineFile] {
        let items = ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var created: [PipelineFile] = []
        for item in items {
            let ext = item.pathExtension.lowercased()
            guard ["md", "markdown"].contains(ext) || Self.supportedAudio.contains(ext) else { continue }
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
