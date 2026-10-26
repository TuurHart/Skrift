import Foundation

/// Q527 (Tuur 2026-10-26): "Add recording" has ONE door per open note. The + button when it
/// shows; the note's ⋯ entry only where it does not. The toolbar and both ⋯ menus read this
/// one rule so they cannot drift.
enum AddRecordingDoors {
    /// The + in the compact (phone) nav bar. Never at regular width (the iPad's chrome band
    /// has no +), never on a pending draft (a new note has no text yet), never on a share capture.
    static func showsPlusButton(isCompactWidth: Bool, isPendingDraft: Bool, isShareCapture: Bool) -> Bool {
        isCompactWidth && !isPendingDraft && !isShareCapture
    }

    /// The ⋯ menu's "Add recording" row: only where the + is not showing.
    static func showsMenuEntry(isCompactWidth: Bool, isPendingDraft: Bool, isShareCapture: Bool) -> Bool {
        !showsPlusButton(isCompactWidth: isCompactWidth, isPendingDraft: isPendingDraft,
                         isShareCapture: isShareCapture)
    }
}
