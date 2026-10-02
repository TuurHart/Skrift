import Foundation

/// "New person…" from a name in a note — ONE flow on the phone and the Mac (Q184, note-name-06).
/// 1. `start` checks the name against the roster ("already in your names" first).
/// 2. Otherwise the person editor opens with the name as the full name AND the first alias.
/// 3. Saving goes through `commit` (PersonEditCore rules + the store's rename-aware upsert);
///    the caller then re-derives the open note.
enum NewPersonFromName {
    enum Start: Equatable {
        /// Blank selection: nothing to do.
        case empty
        /// Already a live person's name or alias: tell the user, open no editor.
        case existing(canonical: String)
        /// Open the editor prefilled with these.
        case prefill(name: String, alias: String)
    }

    /// `someoneElse`: the user tapped a name that already offers people to link to and chose
    /// "New person…" on purpose (the two-Jacks case), so the already-known check is skipped.
    static func start(_ text: String, people: [Person], someoneElse: Bool = false) -> Start {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        if someoneElse { return .prefill(name: trimmed, alias: trimmed) }
        let key = NamesMerge.matchKey(trimmed)
        if let hit = people.first(where: { p in
            NamesMerge.matchKey(p.canonical) == key || p.aliases.contains { NamesMerge.matchKey($0) == key }
        }) {
            return .existing(canonical: hit.canonical)
        }
        return .prefill(name: trimmed, alias: trimmed)
    }

    /// The notice for `.existing` (the Mac flashes it, the phone shows an alert).
    static func alreadyKnownMessage(_ name: String) -> String {
        "“\(name.trimmingCharacters(in: .whitespacesAndNewlines))” is already in your names"
    }

    /// Save an edited person: materialise (default alias, voiceprint carry) and upsert,
    /// replacing `original` on a rename. Returns the stored canonical, nil for an empty name.
    @discardableResult
    static func commit(fullName: String, aliases: [String], short: String,
                       original: Person?, in store: NamesStore) -> String? {
        guard let r = PersonEditCore.materialise(fullName: fullName, aliases: aliases,
                                                 short: short, original: original) else { return nil }
        store.upsert(r.person, replacing: original?.canonical)
        return r.person.canonical
    }
}
