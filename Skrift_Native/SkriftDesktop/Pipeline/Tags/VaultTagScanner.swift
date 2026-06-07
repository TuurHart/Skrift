import Foundation

/// Scans an Obsidian vault for the tag names already in use, so `TagMatcher` can
/// suggest REAL vault tags (not just spoken `#hashtags`). The app's own FileManager
/// scan: each note's YAML frontmatter `tags:` (block list, inline `[a, b]`, or
/// `a, b`) plus inline `#tags`. Returns a deduped, lowercased, sorted list.
///
/// PRIVACY: app code scanning the vault is fine (the offline app is the only thing
/// that reads the vault); never hand vault contents to an external agent.
enum VaultTagScanner {
    /// Recursively scan `root` for `.md` files and collect their tag names.
    /// `maxFiles` bounds the work on large vaults.
    static func scan(root: URL, maxFiles: Int = 5000) -> [String] {
        guard !root.path.isEmpty,
              let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles]) else { return [] }
        var tags = Set<String>()
        var count = 0
        for case let url as URL in en {
            guard url.pathExtension.lowercased() == "md" else { continue }
            count += 1
            if count > maxFiles { break }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            collectTags(from: text, into: &tags)
        }
        return tags.sorted()
    }

    /// Collect tag names from one note's text (frontmatter `tags:` + inline `#tags`).
    static func collectTags(from text: String, into tags: inout Set<String>) {
        if let fm = frontmatter(text) {
            for raw in frontmatterTags(fm) { add(raw, to: &tags) }
        }
        for t in TagMatcher.spokenHashtags(in: text) { add(t, to: &tags) }
    }

    private static func add(_ raw: String, to tags: inout Set<String>) {
        let t = raw.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces)).lowercased()
        if !t.isEmpty, !t.allSatisfy(\.isNumber) { tags.insert(t) }
    }

    /// The leading `--- … ---` YAML block, if present.
    private static func frontmatter(_ text: String) -> String? {
        guard text.hasPrefix("---"),
              let rx = try? NSRegularExpression(pattern: "^---\\n([\\s\\S]*?)\\n---"),
              let m = rx.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return nil }
        return (text as NSString).substring(with: m.range(at: 1))
    }

    /// Parse `tags:` from a frontmatter block — inline `[a, b]` / `a, b`, or a block
    /// list (`- a` on the following indented lines).
    static func frontmatterTags(_ fm: String) -> [String] {
        var out: [String] = []
        let lines = fm.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            guard let r = lines[i].range(of: #"^\s*tags\s*:"#, options: .regularExpression) else { i += 1; continue }
            let rest = String(lines[i][r.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty {
                let cleaned = rest.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                out.append(contentsOf: cleaned.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            }
            var j = i + 1
            while j < lines.count, let lr = lines[j].range(of: #"^\s*-\s+"#, options: .regularExpression) {
                out.append(String(lines[j][lr.upperBound...]).trimmingCharacters(in: .whitespaces))
                j += 1
            }
            i = j
        }
        return out.filter { !$0.isEmpty }
    }
}
