import AppKit

/// Q555: while the tag-removal Undo toast is on screen, Command-Z does what the toast's Undo
/// button does. AppKit-only so the host-less test bundle can compile it.
///
/// Why a local key monitor and not an Edit-menu command: the system Edit > Undo item is what
/// drives the note editor's own undo (typed text, "Undo Typing" names, Redo). Replacing it would
/// have to re-send `undo:` itself and would lose those. A monitor is installed ONLY while a toast
/// is showing, so with no toast nothing here runs and Command-Z reaches the editor untouched.
enum TagUndoKey {
    /// Plain Command-Z. Shift (Redo), Option or Control with it do not count.
    static func isUndoChord(characters: String?, flags: NSEvent.ModifierFlags) -> Bool {
        let held = flags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        return held == .command && characters?.lowercased() == "z"
    }

    /// Holds the event monitor for one toast's lifetime. `install` while the toast shows,
    /// `remove` when it goes (undone, timed out, or the view leaves).
    @MainActor
    final class Monitor {
        private var token: Any?
        private var onUndo: (() -> Void)?

        var isInstalled: Bool { token != nil }

        func install(onUndo: @escaping () -> Void) {
            self.onUndo = onUndo
            guard token == nil else { return }
            token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return MainActor.assumeIsolated { self.handle(event) }
            }
        }

        func remove() {
            if let token { NSEvent.removeMonitor(token) }
            token = nil
            onUndo = nil
        }

        /// nil = the key was taken as the toast's Undo; the event itself otherwise.
        /// A sheet (name editor, unlock) keeps its own Command-Z.
        func handle(_ event: NSEvent) -> NSEvent? {
            guard event.type == .keyDown, !event.isARepeat,
                  event.window?.sheetParent == nil,
                  let onUndo,
                  TagUndoKey.isUndoChord(characters: event.charactersIgnoringModifiers, flags: event.modifierFlags)
            else { return event }
            onUndo()
            return nil
        }

        deinit { if let token { NSEvent.removeMonitor(token) } }
    }
}
