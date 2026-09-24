import Foundation

/// Single-sourced C93 tag rules (Q28/C241 revamp) — the ONE place that decides what
/// typed text becomes a tag, shared by the phone, iPad and Mac editors so the three
/// devices can never disagree on the same input again. Fixes three source bugs found
/// by the mock (BUGS §4): Mac `commitOne` lowercasing a picked/created tag while
/// Return kept case, no case-fold anywhere, and `Memo.splitTagInput` stripping every
/// `#` instead of one.
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

    /// One newly-typed/picked tag folded onto an existing spelling, if any.
    struct Fold: Equatable { let typed: String; let kept: String }

    /// Fold + de-dupe a batch of already-`split` tags against what's on the note
    /// (`existing`) and the wider `library`, in order. Returns tags to actually
    /// append plus, for any that already exist (on the note or in the library under
    /// a different case), the fold record (typed spelling → the spelling kept).
    static func fold(_ accepted: [String], existing: [String], library: [String]) -> (toAdd: [String], folds: [Fold]) {
        var have = Set(existing.map { $0.lowercased() })
        var toAdd: [String] = []
        var folds: [Fold] = []
        let widerLibrary = library + existing
        for typed in accepted {
            let resolved = resolveSpelling(typed, library: widerLibrary)
            let key = resolved.lowercased()
            if have.contains(key) {
                let kept = existing.first { $0.lowercased() == key } ?? resolved
                if kept != typed { folds.append(Fold(typed: typed, kept: kept)) }
                continue
            }
            have.insert(key)
            toAdd.append(resolved)
        }
        return (toAdd, folds)
    }
}
