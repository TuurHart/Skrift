import Foundation

/// Q286 (D171, C76, C77): what both apps read out of an imported `.md` file. Pure (Foundation
/// only), so the phone's share drain and the Mac's ingest give one file the same title and the
/// same date. Moved here from `IngestService`, which keeps thin forwarders.
enum MarkdownImport {

    /// First `# ` heading (trailing dots trimmed), else the fallback. Mirrors
    /// `apple_notes_importer.parse_markdown_note`.
    static func title(_ content: String, fallback: String) -> String {
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

    /// C76 / D18: the creation date a markdown file may carry INSIDE it: a YAML front matter key
    /// (`created`, `creation date`, `date created`, `created_at`, `date`) or one of the first lines
    /// written as `Created: <date>`. nil when there is none (the built-in Markdown export has
    /// none): the caller marks the note date-unknown, never the import moment.
    static func creationDate(_ content: String) -> Date? {
        let keys: Set<String> = ["created", "creation date", "creation_date", "date created", "created_at",
                                 "created at", "date"]
        func value(of line: Substring) -> String? {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let key = line[..<colon].trimmingCharacters(in: CharacterSet(charactersIn: " *_>-\t")).lowercased()
            guard keys.contains(key) else { return nil }
            let v = line[line.index(after: colon)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: " *_\"'\t"))
            return v.isEmpty ? nil : v
        }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
        var candidates: [Substring] = []
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            candidates = lines[1..<end].map { Substring($0) }
        } else {
            candidates = lines.prefix(8).map { Substring($0) }
        }
        for line in candidates {
            if let v = value(of: line), let d = parseDate(v) { return d }
        }
        return nil
    }

    /// ISO 8601 (with or without zone / fraction), `yyyy-MM-dd[ HH:mm[:ss]]`, or the AppleScript
    /// long form ("Monday, 14 September 2026 at 10:00:00"). Local time when no zone is given.
    static func parseDate(_ s: String) -> Date? {
        if let d = ISO8601.date(from: s) { return d }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm",
                       "yyyy-MM-dd", "EEEE, d MMMM yyyy 'at' HH:mm:ss", "d MMMM yyyy 'at' HH:mm:ss"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
