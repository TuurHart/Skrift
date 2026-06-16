import Foundation

/// Reads person-note TITLES from the Obsidian vault's `People/` folder — the OPTIONAL
/// seed that bootstraps Skrift's portable names roster (NAMING_MODEL.md decision 5: the
/// DB is the home, the `People/` folder is a seed/sink). The user already keeps one note
/// per person (Jack Hutton, Hendri van Niekerk, …); their FILENAMES are the canonical
/// names, so importing them grows the roster with zero typing.
///
/// PRIVACY (CLAUDE.md hard rule + the NON-NEGOTIABLE build-guard): app code, **titles
/// only** — it lists filenames, never opens or scans a note's CONTENTS, and never touches
/// AI. The canonical must match the note title EXACTLY so the exported `[[ ]]` link
/// resolves (decision 1), which is exactly what a filename gives us.
enum PeopleFolderScanner {
    /// The vault subfolder that holds one note per person. (Hardcoded for now — the user's
    /// convention; a setting can follow in a later chunk if needed.)
    static let folderName = "People"

    /// The `.md` note titles in `<vaultRoot>/People/`, trimmed, non-empty, de-duplicated
    /// (case-insensitively), sorted. Empty when there's no vault or no `People/` folder.
    /// Only the TOP level is listed (a person note isn't nested); never recurses, never reads.
    static func titles(vaultRoot: URL) -> [String] {
        let peopleDir = vaultRoot.appendingPathComponent(folderName, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: peopleDir.path, isDirectory: &isDir), isDir.boolValue,
              let items = try? FileManager.default.contentsOfDirectory(
                at: peopleDir, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else { return [] }

        var seen = Set<String>()
        var out: [String] = []
        for url in items where url.pathExtension.lowercased() == "md" {
            let title = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespaces)
            let key = title.lowercased()
            if !title.isEmpty, seen.insert(key).inserted { out.append(title) }
        }
        return out.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
