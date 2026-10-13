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

    /// The process-wide cache every Process run asks (Q365, G10).
    static let cached = VaultTagCache()

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

    /// Fixed pattern, no per-call variation — hoisted so `scan(root:)` doesn't rebuild
    /// it on every `.md` file (up to 5000× per scan; sweep E finding #4).
    private static let frontmatterRegex = try! NSRegularExpression(pattern: "^---\\n([\\s\\S]*?)\\n---")

    /// The leading `--- … ---` YAML block, if present.
    private static func frontmatter(_ text: String) -> String? {
        guard text.hasPrefix("---"),
              let m = frontmatterRegex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return nil }
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

/// The vault tag scan, cached across Process runs (Q365, D186; plan/perf2/g-mac-pipeline.md
/// G10). The first scan reads every `.md` once; later scans enumerate the vault for
/// modification dates and re-read only the files whose date or size moved, dropping files that
/// left. No file cap by default: the old 5,000-file `maxFiles` silently dropped every tag past
/// it. Answers exactly what a full `VaultTagScanner.scan` of every file answers.
final class VaultTagCache: @unchecked Sendable {
    private struct Seen { var modified: Date?; var size: Int?; var tags: Set<String> }

    private let lock = NSLock()
    private let maxFiles: Int?
    private var root: String?
    private var files: [String: Seen] = [:]
    private var reads = 0

    /// Work counter: `.md` files read from disk over this cache's life.
    var filesRead: Int { lock.lock(); defer { lock.unlock() }; return reads }

    init(maxFiles: Int? = nil) { self.maxFiles = maxFiles }

    func scan(root: URL) -> [String] {
        guard !root.path.isEmpty else { return [] }
        lock.lock(); defer { lock.unlock() }
        let key = root.standardizedFileURL.path
        if self.root != key { self.root = key; files = [:] }   // a new vault starts fresh
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                      options: [.skipsHiddenFiles]) else { return [] }
        var next: [String: Seen] = [:]
        var count = 0
        for case let url as URL in en {
            guard url.pathExtension.lowercased() == "md" else { continue }
            count += 1
            if let maxFiles, count > maxFiles { break }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let modified = values?.contentModificationDate
            let size = values?.fileSize
            if let known = files[url.path], modified != nil, known.modified == modified, known.size == size {
                next[url.path] = known
                continue
            }
            var tags = Set<String>()
            reads += 1
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                VaultTagScanner.collectTags(from: text, into: &tags)
            }
            next[url.path] = Seen(modified: modified, size: size, tags: tags)
        }
        files = next
        var all = Set<String>()
        for seen in next.values { all.formUnion(seen.tags) }
        return all.sorted()
    }
}
