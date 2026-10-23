import Foundation

/// C159 / C283 / D32 (Q489): a roster change — a person added, an alias added, a rename —
/// re-derives the links of EVERY processed row on the Mac once, deterministically, and hands
/// back the rows whose body or `people:` changed, so the caller re-exports the ones already in
/// the vault. Before, only the open note re-scanned (`OpenNoteRosterRefresh`) and the phone and
/// Mac exports drifted apart after a rename.
///
/// "Once" is a roster fingerprint: the link-relevant shape of the live roster (canonical, short,
/// aliases; never voiceprints or stamps). The re-link runs when it differs from the one last
/// applied, then records it, so every trigger (each reconcile pass, a Mac names edit) is cheap
/// when nothing changed. The re-export goes through the engine's own guards: an untouched file
/// we own is rewritten, an edited, moved or foreign file is never touched (C54).
@MainActor
enum RosterRelink {
    static let fingerprintKey = "rosterRelinkFingerprint"

    /// The link-relevant roster, order-free: two rosters that link every note the same way
    /// have the same fingerprint.
    static func fingerprint(_ people: [Person]) -> String {
        people.filter { !$0.isDeleted }
            .map { p in
                let aliases = p.aliases.map(NamesMerge.aliasKey).filter { !$0.isEmpty }.sorted()
                return [p.canonical, p.short ?? "", aliases.joined(separator: ",")].joined(separator: "|")
            }
            .sorted()
            .joined(separator: "\n")
    }

    /// Re-link every processed live row over `people`. Returns the ids whose linked body or
    /// compiled note changed. Deterministic: the same rows and roster give the same result,
    /// and a second run changes nothing.
    @discardableResult
    static func relink(_ files: [PipelineFile], people: [Person], author: String) -> [String] {
        var changed: [String] = []
        for pf in files where pf.deletedAt == nil && pf.sanitised != nil {
            let before = (pf.sanitised, pf.compiledText)
            MemoCloudUpdate.resanitiseAndCompile(pf, people: people, author: author)
            if pf.sanitised != before.0 || pf.compiledText != before.1 { changed.append(pf.id) }
        }
        return changed
    }

    /// The trigger: re-link when the roster changed since the last run, record the new
    /// fingerprint, and return the changed ids (empty when nothing ran). The FIRST call on a
    /// Mac only records the fingerprint — there is no earlier roster to have changed from, and
    /// re-linking every note on the first launch of this build would re-export whatever an
    /// older linker left behind.
    @discardableResult
    static func runIfChanged(_ files: [PipelineFile], people: [Person], author: String,
                             defaults: UserDefaults = .standard) -> [String] {
        let now = fingerprint(people)
        let last = defaults.string(forKey: fingerprintKey)
        guard last != now else { return [] }
        defaults.set(now, forKey: fingerprintKey)
        guard last != nil else { return [] }
        return relink(files, people: people, author: author)
    }
}
