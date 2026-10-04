import Foundation

/// Single-sourced C93 tag rules (Q28/C241 revamp) — the ONE place that decides what
/// typed text becomes a tag, shared by the phone, iPad and Mac editors so the three
/// devices can never disagree on the same input again. Fixes three source bugs found
/// by the mock (BUGS §4): Mac `commitOne` lowercasing a picked/created tag while
/// Return kept case, no case-fold anywhere, and the old `splitTagInput` stripping
/// every `#` instead of one (that function is gone; `split` below is the only one).
enum TagRules {

    /// One raw entry-field string, split on comma/newline (a tag itself may contain
    /// spaces, so we never split on whitespace). Each piece: leading `#` stripped
    /// ONCE, trimmed, case KEPT. A piece needs at least one letter or digit or it's
    /// refused rather than silently dropped (`refused` carries the ORIGINAL text,
    /// so a caller can say what it rejected) — punctuation-only input like `[]`
    /// (2026-07-27 finding) is unrepresentable as a tag.
    static func split(_ raw: String) -> (accepted: [String], refused: [String]) {
        var accepted: [String] = []
        var refused: [String] = []
        for piece in raw.split(whereSeparator: { $0 == "," || $0 == "\n" }) {
            let original = piece.trimmingCharacters(in: .whitespaces)
            guard !original.isEmpty else { continue }
            var word = original
            if word.hasPrefix("#") { word.removeFirst() }
            word = word.trimmingCharacters(in: .whitespaces)
            guard word.contains(where: { $0.isLetter || $0.isNumber }) else {
                refused.append(original)
                continue
            }
            accepted.append(word)
        }
        return (accepted, refused)
    }

    /// The spelling a NEW tag should take (D139): when its case-folded form already
    /// exists ANYWHERE in `library` (every tag across the vault/notes — not just this
    /// note), the existing spelling wins — typing `Wood` when `wood` exists anywhere
    /// reuses `wood`. A tag new to the whole library keeps the case it was typed in
    /// (C93). This decides spelling for NEW input only — it never rewrites a tag
    /// already sitting on a note on disk.
    static func resolveSpelling(_ typed: String, library: [String]) -> String {
        let key = typed.lowercased()
        for existing in library where existing.lowercased() == key { return existing }
        return typed
    }

    /// Fold + de-dupe a batch of already-`split` tags against what's on the note
    /// (`existing`) and the wider `library`, in order. Returns the tags to actually
    /// append: new to the note, in the spelling `resolveSpelling` picks. A second
    /// same-batch variant (`["Wood", "wood"]`) is dropped, so the FIRST spelling wins.
    static func fold(_ accepted: [String], existing: [String], library: [String]) -> [String] {
        var have = Set(existing.map { $0.lowercased() })
        var toAdd: [String] = []
        let widerLibrary = library + existing
        for typed in accepted {
            let resolved = resolveSpelling(typed, library: widerLibrary)
            let key = resolved.lowercased()
            if have.contains(key) { continue }
            have.insert(key)
            toAdd.append(resolved)
        }
        return toAdd
    }

    /// The "already on this note as #x" line (mock `tag-ui-revamp.html`, `addNew`): the
    /// spelling ALREADY on the note that the first accepted tag case-folds onto, or nil
    /// when every accepted tag is new to the note. Walks the batch in order like `fold`,
    /// so a second same-batch variant (`["Wood", "wood"]`) reports the first spelling.
    static func alreadyOnNote(_ accepted: [String], existing: [String], library: [String]) -> String? {
        var have = existing
        for typed in accepted {
            let key = typed.lowercased()
            if let kept = have.first(where: { $0.lowercased() == key }) { return kept }
            have.append(resolveSpelling(typed, library: library + have))
        }
        return nil
    }

    /// The live line under the field while typing (mock `hit`): the note's own spelling
    /// when the typed text (one leading `#` ignored) case-folds onto a tag already on the
    /// note, else nil. Only meaningful when no suggestion row matches; the caller decides.
    static func typedAlreadyOnNote(_ typed: String, existing: [String]) -> String? {
        var t = typed.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { t.removeFirst() }
        t = t.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return existing.first { $0.lowercased() == t.lowercased() }
    }

    /// How many notes carry each tag (Q172, note-tags-04). The caller picks which notes
    /// count (phone: every live `Memo`; Mac: every live `PipelineFile`).
    static func counts<S: Sequence>(_ tagLists: S) -> [String: Int] where S.Element == [String] {
        var counts: [String: Int] = [:]
        for tags in tagLists {
            for tag in tags { counts[tag, default: 0] += 1 }
        }
        return counts
    }

    /// The tag library order (Q172, note-tags-04): most-used first, ties by key
    /// ascending. ONE ranking for the phone's `NotesRepository.allTags` and the Mac's
    /// `TagLibrary.mostUsedFirst` + the properties typeahead.
    static func mostUsedFirst(_ counts: [String: Int]) -> [String] {
        counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }
}
