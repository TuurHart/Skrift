import Foundation

/// The Mac list's click-selection rules, pure (Q77 / C115). `AppModel.handleClick` reads the
/// modifier keys and forwards here, so the rules are testable without an `NSEvent`.
///
/// Native list semantics:
/// - plain click → just this row, and it becomes the anchor;
/// - ⌘-click → toggle this row in/out, and it becomes the anchor;
/// - ⇧-click → the contiguous range from the ANCHOR to this row (replacing the selection),
///   anchor unchanged, so a second ⇧-click can shrink or move the range.
///
/// The range runs over what the user SEES (`displayOrder`: every row, quiet unrated notes
/// included, in on-screen order) but only `selectable` rows join the selection — a quiet note
/// has no selection semantics, and the bulk actions only act on pipeline rows. That is also what
/// lets a range start from a quiet note that was opened in the pane: before, an anchor that was
/// not itself a pipeline row silently turned every ⇧-click into a plain click.
enum ListSelection {
    enum Click: Equatable { case plain, toggle, range }

    struct State: Equatable {
        var selection: Set<String> = []
        /// The note open in the detail pane.
        var active: String?
        /// Where a ⇧-click range starts. Moves on plain and ⌘ clicks, never on ⇧.
        var anchor: String?
    }

    static func apply(_ click: Click, id: String, displayOrder: [String],
                      selectable: Set<String>, to state: State) -> State {
        var s = state
        switch click {
        case .toggle:
            if s.selection.contains(id) { s.selection.remove(id) } else { s.selection.insert(id) }
            s.active = id
            s.anchor = id
        case .range:
            // Fall back to the open note when nothing was clicked yet (a fresh launch).
            let from = state.anchor ?? state.active
            guard let from, let a = displayOrder.firstIndex(of: from),
                  let b = displayOrder.firstIndex(of: id) else {
                return apply(.plain, id: id, displayOrder: displayOrder, selectable: selectable, to: state)
            }
            let span = displayOrder[min(a, b)...max(a, b)].filter { selectable.contains($0) }
            s.selection = Set(span)
            s.active = id
            s.anchor = from
        case .plain:
            s.selection = [id]
            s.active = id
            s.anchor = id
        }
        return s
    }
}
