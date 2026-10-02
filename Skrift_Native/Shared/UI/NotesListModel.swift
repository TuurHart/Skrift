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

    /// The ONE date a day header keys on (Q97, C70/C115). A header is a claim about WHEN THE
    /// NOTE HAPPENED, so it follows the note's `recordedAt` (the date its card shows) under
    /// every sort except "Recently edited", where the header names the edit day. It never
    /// follows `createdAt`: that is when the note entered Skrift (a Mac-authored import or a
    /// fresh device's CloudKit fill all share one arrival day), and grouping on it filed a
    /// whole archive under "Yesterday" (Tuur 2026-10-02). The Mac queue already keys on the
    /// content date (`QueueEntry.date`), so all three surfaces read the same day.
    static func groupDate(recordedAt: Date, lastEditedAt: Date, byEditTime: Bool) -> Date {
        byEditTime ? lastEditedAt : recordedAt
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
}
