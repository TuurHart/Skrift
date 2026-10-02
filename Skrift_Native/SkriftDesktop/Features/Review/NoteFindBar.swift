import AppKit

/// Q125 (D125): find in the open note on the Mac. The system find bar on the note's NSTextView,
/// the way the phone has `isFindInteractionEnabled`. AppKit-only so the host-less test bundle
/// can compile it (the rest of `Features/Review` is SwiftUI).
///
/// Cmd+F is NOT a global key: the Edit command sends `performTextFinderAction(_:)` down the
/// responder chain, so it only reaches a text view that has focus. Whatever else claims
/// Cmd+F later (a list search field) decides the final key in the shortcut item.
enum NoteFindBar {
    /// The three actions the Edit menu sends. Raw values are `NSTextFinder.Action`'s; the
    /// responder reads them from the sender's `tag`.
    enum Verb: Int, CaseIterable {
        case show = 1          // NSTextFinder.Action.showFindInterface
        case next = 2          // .nextMatch
        case previous = 3      // .previousMatch

        var title: String {
            switch self {
            case .show: return "Find in Note…"
            case .next: return "Find Next"
            case .previous: return "Find Previous"
            }
        }
    }

    /// Turn the find bar on for a note text view (call once at creation).
    static func enable(on tv: NSTextView) {
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
    }

    /// Menu entry point: send `verb` to whichever responder has focus. Returns false when
    /// nothing in the chain handles it (no note focused), so the command is a harmless no-op.
    @discardableResult
    static func send(_ verb: Verb) -> Bool {
        let item = NSMenuItem()
        item.tag = verb.rawValue
        return NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: item)
    }
}
