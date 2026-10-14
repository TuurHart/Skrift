import Foundation

/// Platform-neutral rulebook for the person editor (SharedKit wave 2) — the two
/// editors (phone `PersonEditorView`, Mac `PersonEditor`) keep their own chrome
/// and call ONE copy of the editing semantics. Extraction findings folded in:
/// the phone used to DROP voice enrollments on a rename (tombstone + fresh
/// upsert), and the Mac allowed saving a person with no alias (who then never
/// links) — both sides now share the desktop's voiceprint carry and the phone's
/// default-alias rule.
enum PersonEditCore {

    /// How a linked mention of this person reads: the explicit short name, else
    /// the first word of the full name.
    static func displayShort(fullName: String, short: String) -> String {
        let s = short.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { return s }
        let name = fullName.trimmingCharacters(in: .whitespaces)
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    /// The demo line under the aliases field: `saying “X” → recognised as BOLD`.
    /// BOLD is how the mention will actually READ (the short display, not the
    /// full canonical) — one rule for both apps.
    static func aliasDemo(firstAlias: String, fullName: String, short: String)
        -> (prefix: String, bold: String)? {
        let alias = firstAlias.trimmingCharacters(in: .whitespaces)
        guard !alias.isEmpty else { return nil }
        let bold = displayShort(fullName: fullName, short: short)
        return (prefix: "saying “\(alias)” → recognised as ", bold: bold.isEmpty ? alias : bold)
    }

    /// One rule for "has a voice": any stored embedding.
    static func isEnrolled(_ person: Person?) -> Bool {
        !(person?.voiceEmbeddings?.isEmpty ?? true)
    }

    /// Validate + materialise an edit into a finished `Person`, or nil when the
    /// name is empty. Rules (one copy, both apps):
    ///  • canonical = normalised full name
    ///  • aliases: trimmed, empties dropped, case-insensitive de-duped; a person
    ///    with NO alias never links, so empty defaults to the plain name
    ///  • short: nil if blank
    ///  • voiceprints CARRY from the original (a rename must not drop enrollment)
    ///  • `renamedFrom` = the original canonical when the canonical changed —
    ///    the caller tombstones it
    static func materialise(fullName: String, aliases: [String], short: String,
                            original: Person?) -> (person: Person, renamedFrom: String?)? {
        let canonical = NamesMerge.normaliseCanonical(fullName.trimmingCharacters(in: .whitespaces))
        let plainName = NamesMerge.bareName(canonical)
        guard !plainName.isEmpty else { return nil }

        var clean: [String] = []
        for a in aliases.map({ $0.trimmingCharacters(in: .whitespaces) }) where !a.isEmpty {
            if !clean.contains(where: { $0.caseInsensitiveCompare(a) == .orderedSame }) { clean.append(a) }
        }
        if clean.isEmpty { clean = [plainName] }

        let s = short.trimmingCharacters(in: .whitespaces)
        let person = Person(canonical: canonical, aliases: clean, short: s.isEmpty ? nil : s,
                            voiceEmbeddings: original?.voiceEmbeddings, lastModifiedAt: ISO8601.now())
        let renamedFrom: String? = original.flatMap { o in
            NamesMerge.normaliseCanonical(o.canonical) != canonical ? o.canonical : nil
        }
        return (person, renamedFrom)
    }

    /// The aliases every NEW person is born with when the user typed only a name: `[full, first
    /// word]` (de-duped, case-insensitive). C257/R66: a person with no alias never links, so no
    /// path that creates a person (speaker naming on either app, Add Person, voice enrolment of an
    /// unknown name) may leave `aliases` empty. One copy: `createIfNeeded` and
    /// `NamesStore.addVoiceEmbedding` both seed from here.
    static func defaultAliases(forName name: String) -> [String] {
        let plain = NamesMerge.bareName(NamesMerge.normaliseCanonical(name.trimmingCharacters(in: .whitespaces)))
        guard !plain.isEmpty else { return [] }
        var out = [plain]
        if let first = plain.split(separator: " ").first.map(String.init),
           first.caseInsensitiveCompare(plain) != .orderedSame { out.append(first) }
        return out
    }

    /// The ONE door for "a person who does not exist yet", on BOTH apps: speaker naming (phone
    /// `MemoPageView.assign`, Mac `ProcessingCoordinator.nameSpeaker`) and the Add Person sheet.
    /// Every new person is born with aliases `[full, first word]`, `short` = the typed short
    /// or the first word (R12/C83: an alias-less person never links). Runs BEFORE any voice
    /// enrolment, so a short clip or a missing sidecar still leaves the person behind.
    /// An existing live person is never overwritten: with no typed short it is returned
    /// untouched; with one, `upsert(_, replacing: nil)` merges (unions aliases, sets short).
    /// Returns the stored person, or nil for an empty name.
    /// Same full name = same person (C254): a typed name matching a live person, any case, is
    /// a merge and is announced (`RosterMergeNotice`). `announceMerge: false` is for callers
    /// that PICKED the existing person (the assign sheet's People list), where nothing merged.
    @discardableResult
    static func createIfNeeded(fullName: String, short: String = "", announceMerge: Bool = true,
                               in store: NamesStore) -> Person? {
        let trimmed = fullName.trimmingCharacters(in: .whitespaces)
        let existing = store.livePeople().first { NamesMerge.matchKey($0.canonical) == NamesMerge.matchKey(trimmed) }
        let typedShort = short.trimmingCharacters(in: .whitespaces)
        if let existing, typedShort.isEmpty {
            if announceMerge { RosterMergeNotice.post(into: existing.canonical) }
            return existing
        }
        let first = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        guard let r = materialise(fullName: trimmed, aliases: defaultAliases(forName: trimmed),
                                  short: typedShort.isEmpty ? first : typedShort,
                                  original: nil) else { return nil }
        store.upsert(r.person, replacing: nil)
        return store.livePeople().first { NamesMerge.matchKey($0.canonical) == NamesMerge.matchKey(r.person.canonical) }
    }
}
