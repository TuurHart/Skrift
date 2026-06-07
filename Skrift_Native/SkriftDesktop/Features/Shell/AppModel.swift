import SwiftUI
import AppKit
import Observation

enum QueueFilter: String, CaseIterable {
    case all = "All", needsWork = "Needs Work", done = "Done"
}

/// UI state for the review surface: which note is open, the multi-selection, and
/// the queue filter. Files themselves live in SwiftData (`@Query`), so this model
/// holds only the transient selection/navigation state.
@MainActor
@Observable
final class AppModel {
    var filter: QueueFilter = .all

    /// Multi-selection built with ⌘/⇧-click (native macOS list semantics).
    var selection: Set<String> = []
    /// The note open in the detail pane — the most recent single/anchor click.
    var activeID: String?

    func isComplete(_ f: PipelineFile) -> Bool {
        let s = f.steps
        return s.transcribe == .done && s.sanitise == .done && s.enhance == .done && s.export == .done
    }

    func matchesFilter(_ f: PipelineFile) -> Bool {
        switch filter {
        case .all:       return true
        case .needsWork: return !isComplete(f)
        case .done:      return isComplete(f)
        }
    }

    /// Click handling with native modifier semantics:
    /// - plain click → select + open just this row
    /// - ⌘-click → toggle this row in/out of the multi-selection
    /// - ⇧-click → extend the selection from the anchor to this row
    func handleClick(_ id: String, in ordered: [String]) {
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            activeID = id
        } else if mods.contains(.shift), let anchor = activeID,
                  let a = ordered.firstIndex(of: anchor), let b = ordered.firstIndex(of: id) {
            selection.formUnion(ordered[min(a, b)...max(a, b)])
            activeID = id
        } else {
            selection = [id]
            activeID = id
        }
    }
}
