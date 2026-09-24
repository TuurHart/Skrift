import Foundation

/// Cross-app rules for the unified notes list (Q26, mocks/one-notes-list.html,
/// D134–D137): the phone, iPad and Mac feed their OWN model (`Memo` on the
/// phone/iPad, `PipelineFile` + unrated `Memo` on the Mac) through these three
/// shared shapes, so a chip count, a day-group key, or a pill's visibility rule
/// can never mean something different on one device than another.
enum NotesListModel {

    /// One count per triage chip. `.all` never carries a count (D135: "All
    /// carries no number") — the caller only fills in the three that do.
    static func chipCounts(needsWork: Int, done: Int, notRated: Int) -> [QueueFilter: Int] {
        [.needsWork: needsWork, .done: done, .notRated: notRated]
    }

    /// Day-group a list into `(title, items)` buckets, in the order items already
    /// arrive (so the caller's own sort decides group order) — ONE grouping pass
    /// instead of a hand-rolled reduce per app. `dayLabel` is each app's own
    /// `MemoDate.group` call over whatever date field it groups by.
    static func dayGroups<T>(_ items: [T], dayLabel: (T) -> String) -> [(title: String, items: [T])] {
        var order: [String] = []
        var bucket: [String: [T]] = [:]
        for item in items {
            let key = dayLabel(item)
            if bucket[key] == nil { order.append(key) }
            bucket[key, default: []].append(item)
        }
        return order.map { (title: $0, items: bucket[$0] ?? []) }
    }

    /// D136: a status pill shows ONLY while a note is being worked on or is
    /// broken — never for a calm/finished state (the always-on-badge-is-no-signal
    /// doctrine, locked before this list existed). Each app maps its own status
    /// enum to one of these three before deciding whether to render a pill.
    enum PillRule {
        case working, broken, calm
        var showsPill: Bool { self != .calm }
    }
}
