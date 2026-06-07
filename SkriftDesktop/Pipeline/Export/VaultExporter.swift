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

        let mdURL = vaultURL.appendingPathComponent(safe + ".md")
        try Data(markdown.utf8).write(to: mdURL)

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

        // Captured images (the note's `images/` sidecar) → attachments subfolder.
        var imageCount = 0
        let imagesDir = URL(fileURLWithPath: pf.path).deletingLastPathComponent().appendingPathComponent("images")
        if !settings.attachmentsFolder.isEmpty, !pf.path.isEmpty,
           FileManager.default.fileExists(atPath: imagesDir.path) {
            let dir = vaultURL.appendingPathComponent(settings.attachmentsFolder, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for img in (try? FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil)) ?? [] {
                let dest = dir.appendingPathComponent(img.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: img, to: dest)
                imageCount += 1
            }
        }

        return Result(markdownURL: mdURL, audioURL: audioURL, imageCount: imageCount)
    }
}
