import Foundation

/// Roster-collision re-scan (NAMING_MODEL.md NON-NEGOTIABLE build-guard). The day a SECOND
/// same-name person is added, every memo that previously auto-linked that first name now
/// resolves to the WRONG / ambiguous person — and nothing warns you. This finds the aliases
/// that newly collided and the already-processed memos affected, so they can be re-derived
/// (the now-ambiguous `[[link]]` falls back to a dotted suggestion the user re-picks).
///
/// Pure + deterministic (rosters + files → sets), so it host-tests without a backend.
enum RosterAudit {
    private static func ownerCounts(_ people: [Person]) -> [String: Int] {
        var m: [String: Int] = [:]
        for p in people where !p.isDeleted {
            // Count DISTINCT people per alias (a person listing an alias twice still counts once).
            var seenForPerson = Set<String>()
            for a in p.aliases {
                let al = a.trimmingCharacters(in: .whitespaces).lowercased()
                guard !al.isEmpty, seenForPerson.insert(al).inserted else { continue }
                m[al, default: 0] += 1
            }
        }
        return m
    }

    /// Aliases (lowercased) that went from at most one owner to 2+ owners between the OLD and
    /// NEW rosters — a newly-introduced same-name collision (the formerly-unambiguous name is
    /// now ambiguous, so any auto-link of it is suspect).
    static func newlyAmbiguous(old: [Person], new: [Person]) -> Set<String> {
        let o = ownerCounts(old), n = ownerCounts(new)
        return Set(n.filter { $0.value >= 2 && (o[$0.key] ?? 0) < 2 }.keys)
    }

    /// The files whose CURRENT sanitised body auto-links a person who owns one of the
    /// newly-ambiguous aliases — they need a name re-check. Soft-deleted files are skipped.
    static func affectedFiles(_ files: [PipelineFile], newlyAmbiguous aliases: Set<String>,
                              people: [Person]) -> [PipelineFile] {
        guard !aliases.isEmpty else { return [] }
        // Canonical keys of the people who own a newly-ambiguous alias.
        let affectedCanon = Set(people.filter { p in
            p.aliases.contains { aliases.contains($0.trimmingCharacters(in: .whitespaces).lowercased()) }
        }.map { NamesMerge.keyName($0.canonical).trimmingCharacters(in: .whitespaces).lowercased() })
        guard !affectedCanon.isEmpty else { return [] }
        return files.filter { f in
            guard f.deletedAt == nil, let body = f.sanitised else { return false }
            return Sanitiser.linkOccurrences(in: body).contains {
                affectedCanon.contains(Sanitiser.linkTarget($0.core).trimmingCharacters(in: .whitespaces).lowercased())
            }
        }
    }
}
