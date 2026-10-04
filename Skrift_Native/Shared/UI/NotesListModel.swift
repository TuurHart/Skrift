import Foundation

/// Cross-app rules for the unified notes list (Q26, mocks/one-notes-list.html,
/// D134–D137): the phone, iPad and Mac feed their OWN model (`Memo` on the
/// phone/iPad, `PipelineFile` + unrated `Memo` on the Mac) through these three
/// shared shapes, so a chip count, a day-group key, or a pill's visibility rule
/// can never mean something different on one device than another.
/// Which date a date-range filter applies to (the Recorded / Added picker on both apps'
/// `DateRangeStrip`, Q105 / C115).
enum MemoDateField: String, CaseIterable {
    case recorded = "Recorded"
    case added = "Added"
}

enum NotesListModel {

    /// The date the range filter reads for one row under the picked field (Q105): the note's
    /// content date (`recordedAt`) or the day it entered Skrift (`addedAt`, C70).
    static func filterDate(field: MemoDateField, recordedAt: Date, addedAt: Date) -> Date {
        field == .added ? addedAt : recordedAt
    }

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

    // MARK: - Q104: the three filter rules, applied to EVERY row kind (C115, D148)
    //
    // The phone feeds `Memo`s; the Mac feeds `PipelineFile` rows (rated) plus `Memo` rows
    // (unrated, stranded, locked-quiet, fading search hits). Each app says which chip a
    // row belongs to and which date the range reads; these rules decide membership, so no
    // row kind can skip the date range or the chip on one device and not the other.

    /// Rule 1 — the filter sheet every row passes: the active chip and the date range.
    /// `inChip` is the caller's chip answer for this row; `extra` carries any further
    /// filter terms one app offers (none today: D168 removed the phone's Unsynced / Photos / Place).
    static func passesFilter(inChip: Bool, date: Date, from: Date?, to: Date?, extra: Bool = true) -> Bool {
        inChip && extra && DateRangeFilter.contains(date, from: from, to: to)
    }

    /// Rule 2 — the list rows: live rows that match the search and pass the filter, and,
    /// only while searching, fading rows held to the SAME two tests (fading leaves the
    /// list, never search — no-bad-info 2026-07-21). A fading hit therefore shows under
    /// whichever chip it belongs to and inside the date range, on every device.
    static func listRows<T>(live: [T], fading: [T], searching: Bool,
                            matchesSearch: (T) -> Bool, passesFilter: (T) -> Bool) -> [T] {
        let keep: (T) -> Bool = { matchesSearch($0) && passesFilter($0) }
        var out = live.filter(keep)
        if searching { out += fading.filter(keep) }
        return out
    }

    /// Rule 3 — the Related rows: semantic hits minus the rows the exact search already
    /// shows, minus hidden (locked, not unlocked) notes, through the same filter as the
    /// list. Hit order (best first) is kept.
    static func relatedRows<T, ID: Hashable>(_ hits: [T], shown: Set<ID>, id: (T) -> ID,
                                             hidden: (T) -> Bool, passesFilter: (T) -> Bool) -> [T] {
        hits.filter { !shown.contains(id($0)) && !hidden($0) && passesFilter($0) }
    }

    /// Whether a query is live (the trim rule both apps already used).
    static func isSearching(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
