import Foundation

/// The Mac list's locked-row rules (Q100; C91/C161/C213, R88): a locked note shows
/// title + 🔒 and NOTHING else — no words, balls, chips or pill — the same placeholder
/// the phone's `MemosListView+Row.cardModel` builds. Pure so the host-less test bundle
/// can pin it; `SidebarView` routes both row kinds through here.
enum LockedRow {
    static let placeholderTitle = "Locked note"

    /// The explicit title only — never the first-line fallback, which is the note's words.
    static func title(for memo: Memo) -> String {
        clean(memo.title) ?? placeholderTitle
    }

    static func title(for file: PipelineFile) -> String {
        clean(file.enhancedTitle) ?? placeholderTitle
    }

    private static func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// The card for a locked row: stamp + 🔒 + title, nothing else.
    static func card(stamp: String, title: String, selected: Bool, quiet: Bool) -> NoteCardModel {
        var m = NoteCardModel(stamp: stamp)
        m.locked = true
        m.title = title
        m.balls = nil
        m.selected = selected
        m.quiet = quiet
        return m
    }
}
