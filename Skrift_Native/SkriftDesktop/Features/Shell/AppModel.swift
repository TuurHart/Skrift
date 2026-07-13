import SwiftUI
import AppKit
import Observation

enum QueueFilter: String, CaseIterable {
    case all = "All", needsWork = "Needs Work", done = "Done"
}

/// Sidebar queue ordering. Desktop-appropriate subset of the phone's `MemoSort`
/// (the Mac queue has no "edited" notion and durations are strings, so the useful
/// axes are recency + alphabetical).
enum SidebarSort: String, CaseIterable {
    case newest = "Newest first", oldest = "Oldest first", title = "Title (A–Z)"
    /// Compact label for the inline sort control.
    var short: String {
        switch self {
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        case .title:  return "Title"
        }
    }
    /// The next sort in the cycle (the inline control advances on tap).
    var next: SidebarSort {
        let all = Self.allCases
        return all[(all.firstIndex(of: self).map { $0 + 1 } ?? 0) % all.count]
    }
}

/// UI state for the review surface: which note is open, the multi-selection, and
/// the queue filter. Files themselves live in SwiftData (`@Query`), so this model
/// holds only the transient selection/navigation state.
@MainActor
@Observable
final class AppModel {
    /// Which main surface fills the window: the processing Queue or the Journal
    /// (mock journal-desktop.html — the Queue | Journal switch at the sidebar top).
    enum MainSurface { case queue, journal }
    var surface: MainSurface = .queue

    var filter: QueueFilter = .all
    /// Free-text query over the queue (title + transcript + summary). Empty = no filter.
    var searchText: String = ""
    /// Queue ordering (default newest-first).
    var sort: SidebarSort = .newest

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

    /// Free-text match over the row title, transcript, summary, and photo OCR text.
    /// Empty query matches everything (mirrors the phone's `matchesSearch`).
    func matchesSearch(_ f: PipelineFile) -> Bool {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        if f.queueTitle.lowercased().contains(q) { return true }
        if f.transcript?.lowercased().contains(q) == true { return true }
        if f.enhancedSummary?.lowercased().contains(q) == true { return true }
        // Photo OCR (phone-authored, synced) — find a note by what's IN its photos.
        if f.imageOCRText?.lowercased().contains(q) == true { return true }
        return false
    }

    /// The queue as displayed: filter → search → sort. Single source of truth for
    /// both the rows and the shift-click range order.
    func visible(_ files: [PipelineFile]) -> [PipelineFile] {
        files.filter { matchesFilter($0) && matchesSearch($0) }.sorted(by: sortComparator)
    }

    private func sortComparator(_ a: PipelineFile, _ b: PipelineFile) -> Bool {
        switch sort {
        case .newest: return a.uploadedAt > b.uploadedAt
        case .oldest: return a.uploadedAt < b.uploadedAt
        case .title:  return a.queueTitle.localizedCaseInsensitiveCompare(b.queueTitle) == .orderedAscending
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
