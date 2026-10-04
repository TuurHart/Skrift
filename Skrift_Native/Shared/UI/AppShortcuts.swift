import Foundation

/// The hardware-keyboard shortcut table, written ONCE (Q284, D169). Both apps' single
/// `.commands` block reads it, so the phone/iPad and the Mac can't bind the same chord to
/// different verbs again (iPad had ⌘N on both "New Recording" and "New note").
///
/// Foundation only, on purpose: the host-less Mac unit bundle compiles this file and
/// `AppShortcutsTests` asserts the table. The SwiftUI mapping lives in `AppShortcuts+SwiftUI`.
enum AppShortcuts {
    enum Modifier: Hashable { case command, shift }

    struct Chord: Hashable {
        let key: String
        let modifiers: Set<Modifier>

        /// "⇧⌘N" — for tests and menu/help copy.
        var glyphs: String {
            (modifiers.contains(.shift) ? "⇧" : "") + (modifiers.contains(.command) ? "⌘" : "") + key.uppercased()
        }
    }

    private static func cmd(_ key: String) -> Chord { Chord(key: key, modifiers: [.command]) }

    // ── every device ────────────────────────────────────────────────────────
    /// New (typed) note.
    static let newNote = cmd("n")
    /// Record. Shift-⌘N, so it never shares a chord with New note.
    static let record = Chord(key: "n", modifiers: [.command, .shift])
    /// Focus the notes search field.
    static let search = cmd("f")

    // ── Mac: two surfaces ───────────────────────────────────────────────────
    static let macNotes = cmd("1")
    static let macReview = cmd("2")

    // ── phone / iPad: four tabs ─────────────────────────────────────────────
    static let tabNotes = cmd("1")
    static let tabBooks = cmd("2")
    static let tabReview = cmd("3")
    static let tabSettings = cmd("4")

    /// Everything bound on the Mac / on the phone+iPad, for the "no chord twice" check.
    static let mac: [Chord] = [newNote, record, search, macNotes, macReview]
    static let phone: [Chord] = [newNote, record, search, tabNotes, tabBooks, tabReview, tabSettings]
}
