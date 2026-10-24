import Foundation

/// Memo↔memo link syntax (note feature wave, chunk 5) — SHARED by both apps.
///
/// In the RAW transcript a link is `[[memo:<UUID>|<title snapshot>]]`: the UUID
/// is the durable handle (titles change), the snapshot is the display/export
/// fallback when the target can't be resolved (deleted, other library, or a
/// compile path without a lookup — e.g. the Mac before its resolver is wired).
///
/// On EXPORT the syntax must never reach the vault: `exportRewrite` turns each
/// link into a real Obsidian wikilink — `[[<target note stem>|<title>]]` when
/// the resolver knows the target's exported filename, else `[[<title>]]`.
enum MemoLinkSyntax {
    private static let regex = try! NSRegularExpression(
        pattern: #"\[\[memo:([0-9A-Fa-f\-]{36})\|([^\]\n|]*)\]\]"#)

    /// The raw syntax for a link to `id` displaying `title` (pipes/brackets are
    /// stripped from the snapshot so the syntax can't be broken from inside).
    static func link(id: UUID, title: String) -> String {
        let safe = title
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "[[memo:\(id.uuidString)|\(safe.isEmpty ? "Untitled" : safe)]]"
    }

    struct Occurrence: Equatable {
        let range: NSRange       // the whole [[memo:…]] token in the text
        let id: UUID
        let title: String        // the stored snapshot
    }

    static func occurrences(in text: String) -> [Occurrence] {
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let id = UUID(uuidString: ns.substring(with: m.range(at: 1))) else { return nil }
            return Occurrence(range: m.range, id: id, title: ns.substring(with: m.range(at: 2)))
        }
    }

    /// The distinct link targets in a text (backlink scans).
    static func targets(in text: String) -> Set<UUID> {
        Set(occurrences(in: text).map(\.id))
    }

    /// Export pass: every `[[memo:UUID|Title]]` becomes a real wikilink.
    /// `resolveStem` returns the target's exported note stem (filename without
    /// extension) — nil falls back to `[[Title]]`, which still reads correctly
    /// in the vault even if it doesn't resolve to a note.
    static func exportRewrite(_ text: String, resolveStem: ((UUID) -> String?)? = nil) -> String {
        let occs = occurrences(in: text)
        guard !occs.isEmpty else { return text }
        let ns = NSMutableString(string: text)
        for occ in occs.reversed() {
            let title = occ.title.isEmpty ? "Untitled" : occ.title
            let replacement: String
            if let stem = resolveStem?(occ.id), !stem.isEmpty, stem != title {
                replacement = "[[\(stem)|\(title)]]"
            } else {
                replacement = "[[\(title)]]"
            }
            ns.replaceCharacters(in: occ.range, with: replacement)
        }
        return ns as String
    }
}
