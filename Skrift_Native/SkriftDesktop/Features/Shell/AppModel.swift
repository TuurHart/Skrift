import SwiftUI
import AppKit
import Observation

// `QueueFilter` (the All/Needs Work/Done/Unrated chips) now lives in
// Shared/Model/QueueFilter.swift — ONE label set shared with the iPad Notes
// column, so a chip reads the same word on both apps.

// `SidebarSort` + `SidebarEntry` live in Pipeline/MacListFilter.swift (host-less, Q105).

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
    /// Date-range filter over the row's uploaded date — the Mac half of the
    /// iPad's Filter sheet (Tuur 2026-07-23: "add Date to the Mac"). nil = open.
    var dateFrom: Date?
    var dateTo: Date?
    /// Q105: which date the range filters on (the phone's Recorded / Added picker).
    var dateField: MemoDateField = .recorded
    /// `Memo.addedAt` per note id, set by the sidebar next to its memo fetch (Newest sorts on it).
    var addedAtByID: [String: Date] = [:]
    var dateFilterActive: Bool { dateFrom != nil || dateTo != nil }

    /// Multi-selection built with ⌘/⇧-click (native macOS list semantics).
    var selection: Set<String> = []
    /// The note open in the detail pane — the most recent single/anchor click. Holds
    /// the id of EITHER kind of note: a pipelined row, or an unrated memo (whose
    /// `PipelineFile` would carry that same UUID once a rating creates one). There used
    /// to be a second `paneMemoID` beside this, because an unrated memo was a different
    /// kind of thing shown a different way; it isn't — see `UnratedNotePane`.
    var activeID: String? {
        didSet {
            // Leaving a new typed note: one that was typed in and emptied again is deleted;
            // one never typed in never existed (C43/D91). Every way of changing the open
            // note passes through here.
            if oldValue != activeID, typedNotes.isDraft(oldValue), let ctx = MemoCloudStore.container?.mainContext {
                typedNotes.leave(context: ctx)
                NotificationCenter.default.post(name: .cloudMemosDidChangeFromSync, object: nil)
            }
        }
    }

    /// The Mac's new typed note (✎/⌘N): the rules are the phone quick note's (`QuickNoteDraft`).
    let typedNotes = MacTypedNoteSession()
    /// Set when New note opens a draft: the pane puts the cursor in the body once for this id.
    var focusBodyID: String?

    /// ✎/⌘N. Opens an empty note with the cursor in the body. Creates NO `Memo` — the first
    /// keystroke does (`UnratedNotePane.commit`) — so clicking and leaving leaves nothing behind.
    func beginTypedNote() {
        guard let ctx = MemoCloudStore.container?.mainContext else { return }
        let id = typedNotes.begin(context: ctx).uuidString
        focusBodyID = id
        select(id)
    }

    func isComplete(_ f: PipelineFile) -> Bool { MacListFilter.isComplete(f) }

    /// The list's filter state as the Mac adapter onto the shared list rules (Q104): chip,
    /// search, date range — applied to EVERY row kind (pipeline rows, unrated, stranded,
    /// locked-quiet, fading search hits, Related rows), not just pipeline rows.
    var listFilter: MacListFilter {
        MacListFilter(chip: filter, query: searchText, from: dateFrom, to: dateTo,
                      dateField: dateField, addedAtByID: addedAtByID,
                      isUnlocked: { LockGate.shared.isUnlocked($0) })
    }

    /// The queue as displayed: filter → search → sort (Newest = the note's added date, Q105).
    /// Single source of truth for both the rows and the shift-click range order.
    func visible(_ files: [PipelineFile]) -> [PipelineFile] {
        let f = listFilter
        return f.sort(f.fileRows(files), by: sort, title: { $0.queueTitle })
    }

    /// Where a ⇧-click range starts (`ListSelection`); moves on plain and ⌘ clicks only.
    var selectionAnchor: String?

    /// Click handling with native modifier semantics (rules in `ListSelection`, pure and tested):
    /// - plain click → select + open just this row
    /// - ⌘-click → toggle this row in/out of the multi-selection
    /// - ⇧-click → the range from the anchor to this row
    /// `displayOrder` is every row as drawn (quiet notes included); `selectable` the rows that
    /// can join a selection (the pipeline rows).
    func handleClick(_ id: String, displayOrder: [String], selectable: Set<String>) {
        let mods = NSEvent.modifierFlags
        let kind: ListSelection.Click = mods.contains(.command) ? .toggle : (mods.contains(.shift) ? .range : .plain)
        let next = ListSelection.apply(kind, id: id, displayOrder: displayOrder, selectable: selectable,
                                       to: .init(selection: selection, active: activeID, anchor: selectionAnchor))
        selection = next.selection
        activeID = next.active
        selectionAnchor = next.anchor
    }

    /// Open one note, replacing the selection. The id is a note id whichever kind it
    /// is: a synced memo's `PipelineFile` carries the memo UUID as its id, so a
    /// pipelined row and an unrated memo share one id space and one selection.
    func select(_ id: String) {
        activeID = id
        selectionAnchor = id
        selection = [id]
    }
}
