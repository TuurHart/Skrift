import AppKit

/// Q180 (note-menu-13): the Mac's Copy, through the SAME rule as the phone's `GatedCopy`
/// (`CopyTranscriptRule`): a locked note authenticates (device-owner auth) and then copies,
/// an empty one says "Nothing to copy yet". It used to grey the item out when locked, which
/// left no way to copy short of unlocking the note first.
@MainActor
enum MacGatedCopy {
    /// - Parameter text: evaluated AFTER auth, so a locked note's text (and a compiled
    ///   Markdown pass) is not even built before the user has proved who they are.
    static func copy(id: String, locked: Bool, lockGate: LockGate = .shared,
                     text: @escaping () -> String?, flash: @escaping (String) -> Void) {
        Task { @MainActor in
            if CopyTranscriptRule.step(needsAuth: locked, text: nil) == .authenticate {
                guard await lockGate.unlock(id) else { return }
            }
            switch CopyTranscriptRule.step(needsAuth: false, text: text()) {
            case .copy(let t):
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(t, forType: .string)
            case .nothingToCopy:
                flash(CopyTranscriptRule.emptyMessage)
            case .authenticate:
                break
            }
        }
    }

    static func copy(_ file: PipelineFile, text: @escaping () -> String?, flash: @escaping (String) -> Void) {
        copy(id: file.id, locked: LockGate.shared.isLocked(file), text: text, flash: flash)
    }

    static func copy(_ memo: Memo, text: @escaping () -> String?, flash: @escaping (String) -> Void) {
        copy(id: memo.id.uuidString, locked: LockGate.shared.isLocked(memo), text: text, flash: flash)
    }
}
