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

// MARK: - New person from any selected word (D184)

extension NewPersonFromName {
    /// What the text menu's "New person…" item offers for a selection: the trimmed text to prefill
    /// the person editor with, or nil when the item is hidden. Hidden for empty/whitespace runs,
    /// runs spanning a line break or an inline attachment (photo / checkbox / memo-link chip), and
    /// any run that touches a name span the note already shows (linked, suggested, ambiguous or
    /// plain: those have their own tap flow) or that is already a person's name or alias.
    /// `knownRanges` are the name spans' display ranges in the same coordinate space as `selection`.
    static func selectionOffer(text: String, selection: NSRange, knownRanges: [NSRange],
                               people: [Person]) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, selection.length > 0 else { return nil }
        guard !trimmed.contains(where: { $0.isNewline || $0 == "\u{FFFC}" }) else { return nil }
        let selEnd = selection.location + selection.length
        for r in knownRanges where r.location < selEnd && selection.location < r.location + r.length {
            return nil
        }
        guard case .prefill(let name, _) = start(trimmed, people: people) else { return nil }
        return name
    }
}
