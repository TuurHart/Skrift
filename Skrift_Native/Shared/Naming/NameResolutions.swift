import Foundation

/// Per-note name-linking decisions — ONE shape on every device (SPEC C81 / D20 / R37).
///
/// The phone stores it on `Memo.nameResolutionsData`, the Mac on
/// `PipelineFile.nameResolutionsData`; both blobs are this struct, JSON-encoded, so the
/// Mac mirrors the field both ways (`MirroredNoteFields` "nameResolutions" + the event
/// write `MacCloudMetaSync.setNameResolutions`) and a decision made on either device is
/// honoured by the `Sanitiser` on the other. The two fields are exactly the `neverLink` /
/// `namePicks` inputs the shared `Sanitiser` accepts.
struct NameResolutions: Codable, Equatable {
    /// Canonical keys PRUNED for the whole note (the person stays in Names but does not
    /// auto-link here) — the `Sanitiser.neverLink` input.
    var unlinkedNames: [String] = []
    /// alias (trimmed, lowercased) → chosen canonical `[[Name]]` (a force-pick), or `""`
    /// to SILENCE the alias (it renders plain). The `Sanitiser.namePicks` input.
    var namePicks: [String: String] = [:]

    var isEmpty: Bool { unlinkedNames.isEmpty && namePicks.isEmpty }

    // MARK: Blob

    /// Decode a stored blob; nil / unreadable → empty.
    static func decode(_ data: Data?) -> NameResolutions {
        guard let data, let r = try? JSONDecoder().decode(NameResolutions.self, from: data) else {
            return NameResolutions()
        }
        return r
    }

    /// The stored blob: nil when empty (no blob = no decisions), sorted keys so equal
    /// values give equal bytes on every device.
    var encoded: Data? {
        guard !isEmpty else { return nil }
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return try? enc.encode(self)
    }

    // MARK: Decisions (the same rules on both apps)

    /// Normalised resolution key for an alias (the spoken word as displayed).
    static func aliasKey(_ alias: String) -> String {
        alias.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func personKey(_ canonical: String) -> String {
        NamesMerge.keyName(NamesMerge.normaliseCanonical(canonical))
            .trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Force-LINK an alias to a person for this note (resolve a suggestion / ambiguity, or
    /// change person). Clears any prune of that person so the pick takes effect.
    mutating func link(alias: String, to canonical: String) {
        let key = Self.aliasKey(alias)
        guard !key.isEmpty else { return }
        let canon = NamesMerge.normaliseCanonical(canonical)
        namePicks[key] = canon
        let pk = Self.personKey(canon)
        unlinkedNames.removeAll { Self.personKey($0) == pk }
    }

    /// SILENCE an alias for this note: it neither links nor suggests (renders plain).
    mutating func keepPlain(alias: String) {
        let key = Self.aliasKey(alias)
        guard !key.isEmpty else { return }
        namePicks[key] = ""
    }

    /// PRUNE a person for the whole note (every alias of theirs stops auto-linking here),
    /// dropping any pick that would re-promote them.
    mutating func unlinkPerson(_ canonical: String) {
        let canon = NamesMerge.normaliseCanonical(canonical)
        let pk = Self.personKey(canon)
        guard !pk.isEmpty else { return }
        if !unlinkedNames.contains(where: { Self.personKey($0) == pk }) { unlinkedNames.append(canon) }
        namePicks = namePicks.filter { Self.personKey($0.value) != pk }
    }

    /// Remove the per-note override for an alias (back to its default tier).
    mutating func clear(alias: String) {
        namePicks.removeValue(forKey: Self.aliasKey(alias))
    }
}

/// The name-action wording, ONE table for both apps (note-name-02). The words follow the
/// signed-off mocks (`mocks/phone-name-linking.html`, `mocks/naming-review.html`).
enum NameActionLabel {
    /// Linked name → stop linking it here.
    static let unlink = "Unlink — just a side-mention"
    /// Linked name → pick a different person who shares the alias (a disclosure/sheet).
    static let changePerson = "Change person…"
    /// One candidate inside "Change person…" where the UI lists them flat (the phone dialog).
    static func changePerson(to name: String) -> String { "Change person → \(name)" }
    /// Suggested / ambiguous name → link it to this person.
    static func link(to name: String) -> String { "Link to \(name)" }
    /// Suggested / ambiguous name → silence it for this note.
    static let keepPlain = "Keep as plain text"
    /// Suggested / ambiguous name → a person who is not in Names yet.
    static let newPerson = "New person…"
}

extension Memo {
    /// Typed per-note name decisions over the `nameResolutionsData` blob (shared shape).
    var nameResolutions: NameResolutions {
        get { NameResolutions.decode(nameResolutionsData) }
        set { nameResolutionsData = newValue.encoded }
    }

    /// Force-LINK an alias to a specific person for this note.
    func linkName(alias: String, to canonical: String) {
        var r = nameResolutions
        r.link(alias: alias, to: canonical)
        nameResolutions = r
        markEdited(stampWords: false)   // nameResolutions isn't title/body/tags (C98)
    }

    /// KEEP an alias plain for this note (silenced, still re-tappable).
    func keepNamePlain(alias: String) {
        var r = nameResolutions
        r.keepPlain(alias: alias)
        nameResolutions = r
        markEdited(stampWords: false)   // nameResolutions isn't title/body/tags (C98)
    }

    /// REVERT an alias to its default tier (undo a link / keep-plain).
    func clearNameResolution(alias: String) {
        var r = nameResolutions
        r.clear(alias: alias)
        guard r != nameResolutions else { return }
        nameResolutions = r
        markEdited(stampWords: false)   // nameResolutions isn't title/body/tags (C98)
    }
}
