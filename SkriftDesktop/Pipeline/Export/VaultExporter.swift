import Foundation

/// Writes a compiled note to the Obsidian vault: the `.md` (frontmatter + body) at
/// the vault root, the original audio into the audio subfolder, and any captured
/// images into the attachments subfolder. Pure (Compiler + FileManager), so the
/// coordinator and the `-runfile` harness share it and it host-tests.
enum VaultExporter {
    struct Result: Equatable {
        let markdownURL: URL
        let audioURL: URL?
        let imageCount: Int
    }

    enum ExportError: LocalizedError {
        case noVault
        var errorDescription: String? { "Set your Obsidian vault path in Settings first." }
    }

    @discardableResult
    static func export(_ pf: PipelineFile, settings: AppSettings) throws -> Result {
        let vault = settings.noteFolder.trimmingCharacters(in: .whitespaces)
        guard !vault.isEmpty else { throw ExportError.noVault }
        let vaultURL = URL(fileURLWithPath: vault)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let markdown = Compiler.compile(file: pf, author: settings.authorName)
        let stem = (pf.filename as NSString).deletingPathExtension
        let base = (pf.enhancedTitle?.isEmpty == false) ? pf.enhancedTitle! : stem
        var safe = base.replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))   // avoid "Title..md"
        if safe.isEmpty { safe = "note" }

        // Convert [[img_NNN]] markers → ![[<title>_NNN.ext]] Obsidian embeds and copy
        // the matched images into the attachments subfolder.
        var finalMarkdown = markdown
        var imageCount = 0
        let imagesDir = URL(fileURLWithPath: pf.path).deletingLastPathComponent().appendingPathComponent("images")
        if !settings.attachmentsFolder.isEmpty, !pf.path.isEmpty,
           FileManager.default.fileExists(atPath: imagesDir.path) {
            let attDir = vaultURL.appendingPathComponent(settings.attachmentsFolder, isDirectory: true)
            (finalMarkdown, imageCount) = convertImageMarkers(markdown, imagesDir: imagesDir, safe: safe, into: attDir)
        }

        // Apple-Note attachments: copy the note's `Attachments/` into the vault
        // attachments folder and convert `(Attachments/<name>)` refs → Obsidian
        // `![[<name>]]` embeds (robust to the renamed files' spaces).
        if pf.sourceType == .note, !settings.attachmentsFolder.isEmpty, !pf.path.isEmpty {
            let attSrc = URL(fileURLWithPath: pf.path).deletingLastPathComponent()
                .appendingPathComponent("Attachments", isDirectory: true)
            if FileManager.default.fileExists(atPath: attSrc.path) {
                let attDir = vaultURL.appendingPathComponent(settings.attachmentsFolder, isDirectory: true)
                let (rewritten, copied) = convertNoteAttachments(finalMarkdown, attachmentsSrc: attSrc, into: attDir)
                finalMarkdown = rewritten
                imageCount += copied
            }
        }

        let mdURL = vaultURL.appendingPathComponent(safe + ".md")
        try Data(finalMarkdown.utf8).write(to: mdURL)

        // Original audio → audio subfolder.
        var audioURL: URL?
        if !settings.audioFolder.isEmpty, pf.sourceType == .audio,
           !pf.path.isEmpty, FileManager.default.fileExists(atPath: pf.path) {
            let dir = vaultURL.appendingPathComponent(settings.audioFolder, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let ext = URL(fileURLWithPath: pf.path).pathExtension
            let dest = dir.appendingPathComponent(safe + "." + (ext.isEmpty ? "m4a" : ext))
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: pf.path), to: dest)
            audioURL = dest
        }

        return Result(markdownURL: mdURL, audioURL: audioURL, imageCount: imageCount)
    }

    /// Replace `[[img_NNN]]` markers with `![[<safe>_NNN.ext]]` Obsidian embeds,
    /// copying the matched image (by `img_NNN`/`_NNN.` name, else the NNN-th file)
    /// into `attDir` under the new name. Returns the rewritten markdown + copy count.
    static func convertImageMarkers(_ markdown: String, imagesDir: URL, safe: String, into attDir: URL) -> (String, Int) {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty, let rx = try? NSRegularExpression(pattern: "\\[\\[img_(\\d{3})\\]\\]") else {
            return (markdown, 0)
        }
        let ns = markdown as NSString
        var replacements: [(NSRange, String)] = []
        var copied = 0
        for m in rx.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
            let nnn = ns.substring(with: m.range(at: 1))
            let idx = (Int(nnn) ?? 1) - 1
            let file = files.first { $0.lastPathComponent.contains("_\(nnn).") || $0.lastPathComponent.hasPrefix("img_\(nnn)") }
                ?? ((0..<files.count).contains(idx) ? files[idx] : nil)
            guard let file else { continue }
            let ext = file.pathExtension.isEmpty ? "jpg" : file.pathExtension
            let newName = "\(safe)_\(nnn).\(ext)"
            try? fm.createDirectory(at: attDir, withIntermediateDirectories: true)
            let dest = attDir.appendingPathComponent(newName)
            try? fm.removeItem(at: dest)
            if (try? fm.copyItem(at: file, to: dest)) != nil { copied += 1 }
            replacements.append((m.range, "![[\(newName)]]"))
        }
        var out = markdown
        for (range, repl) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            out = (out as NSString).replacingCharacters(in: range, with: repl)
        }
        return (out, copied)
    }

    /// Copy an Apple Note's `Attachments/` files referenced as `![alt](Attachments/x)`
    /// or `[alt](Attachments/x)` into `attDir`, and convert the refs to Obsidian
    /// embeds/links (`![[x]]` / `[[x]]`). Robust to spaces in the renamed files (the
    /// wikilink form sidesteps markdown URL escaping). Returns rewritten md + copies.
    static func convertNoteAttachments(_ markdown: String, attachmentsSrc: URL, into attDir: URL) -> (String, Int) {
        let fm = FileManager.default
        guard let rx = try? NSRegularExpression(pattern: "(!?)\\[[^\\]]*\\]\\(Attachments/([^)]+)\\)") else {
            return (markdown, 0)
        }
        let ns = markdown as NSString
        var replacements: [(NSRange, String)] = []
        var copied = 0
        for m in rx.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
            let bang = ns.substring(with: m.range(at: 1))
            let raw = ns.substring(with: m.range(at: 2))
            let name = raw.removingPercentEncoding ?? raw
            let src = attachmentsSrc.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { continue }
            try? fm.createDirectory(at: attDir, withIntermediateDirectories: true)
            let dest = attDir.appendingPathComponent(name)
            try? fm.removeItem(at: dest)
            if (try? fm.copyItem(at: src, to: dest)) != nil { copied += 1 }
            replacements.append((m.range, "\(bang)[[\(name)]]"))
        }
        var out = markdown
        for (range, repl) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            out = (out as NSString).replacingCharacters(in: range, with: repl)
        }
        return (out, copied)
    }
}
