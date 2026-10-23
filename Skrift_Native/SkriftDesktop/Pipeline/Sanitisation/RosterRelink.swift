import Foundation

/// C159 / C283 / D32 (Q489): a roster change — a person added, an alias added, a rename —
/// re-derives the links of EVERY processed row on the Mac once, deterministically, and hands
/// back the rows whose body or `people:` changed, so the caller re-exports the ones already in
/// the vault. Before, only the open note re-scanned (`OpenNoteRosterRefresh`) and the phone and
/// Mac exports drifted apart after a rename.
///
/// "Once" is the roster last applied, kept in UserDefaults: the re-link runs when the
/// link-relevant shape of the live roster (canonical, short, aliases; never voiceprints or
/// stamps) differs from it, then records the new one, so every trigger (each reconcile pass, a
/// Mac names edit) is cheap when nothing changed. The re-export goes through the engine's own
/// guards: an untouched file we own is rewritten, an edited, moved or foreign file never (C54).
@MainActor
enum RosterRelink {
    static let rosterKey = "rosterRelinkRoster"

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

    /// THE re-link of one row after a roster change, shared with `OpenNoteRosterRefresh`. A Mac
    /// body edit still only in `sanitised` is adopted first (`MacEditRoundTrip.settle`), judged
    /// under `linkedWith`, the roster that body was linked with, so a rename cannot hide it.
    static func rederive(_ pf: PipelineFile, linkedWith old: [Person], people: [Person], author: String) {
        MacEditRoundTrip.settle(pf, linkedWith: old)
        MemoCloudUpdate.resanitiseAndCompile(pf, people: people, author: author)
    }

    /// Re-link every processed live row from `linkedWith` to `people`. Returns the ids whose
    /// linked body or compiled note changed. Deterministic: the same rows and rosters give the
    /// same result, and a second run changes nothing.
    @discardableResult
    static func relink(_ files: [PipelineFile], linkedWith old: [Person], people: [Person],
                       author: String) -> [String] {
        var changed: [String] = []
        for pf in files where pf.deletedAt == nil && pf.sanitised != nil {
            let before = (pf.sanitised, pf.compiledText)
            rederive(pf, linkedWith: old, people: people, author: author)
            if pf.sanitised != before.0 || pf.compiledText != before.1 { changed.append(pf.id) }
        }
        return changed
    }

    /// Has the live roster changed since the last run (or never run)? Cheap: no rows read.
    static func hasChanged(_ people: [Person], defaults: UserDefaults = .standard) -> Bool {
        let last = defaults.data(forKey: rosterKey).flatMap { try? JSONDecoder().decode([Person].self, from: $0) }
        return last.map { fingerprint($0) != fingerprint(people.filter { !$0.isDeleted }) } ?? true
    }

    /// The trigger: re-link when the roster changed since the last run, record the new one,
    /// and return the changed ids (empty when nothing ran). The FIRST call on a Mac only
    /// records the roster — there is no earlier roster to have changed from, and re-linking
    /// every note on the first launch of this build would re-export whatever an older linker
    /// left behind.
    @discardableResult
    static func runIfChanged(_ files: [PipelineFile], people: [Person], author: String,
                             defaults: UserDefaults = .standard) -> [String] {
        let live = people.filter { !$0.isDeleted }
        let last = defaults.data(forKey: rosterKey).flatMap { try? JSONDecoder().decode([Person].self, from: $0) }
        if let last, fingerprint(last) == fingerprint(live) { return [] }
        defaults.set(try? JSONEncoder().encode(live), forKey: rosterKey)
        guard let last else { return [] }
        return relink(files, linkedWith: last, people: live, author: author)
    }
}
