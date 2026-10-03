import Foundation

/// The Date chip's words (list-sidebar-44): "Date ▾", or "Date · 22 Sep–25 Sep ▾" once a range is live.
enum DateChipText {
    /// "22 Sep–25 Sep" / "from 22 Sep" / "to 25 Sep"; empty with no range.
    static func range(from: Date?, to: Date?) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        switch (from, to) {
        case let (from?, to?): return "\(f.string(from: from))\u{2013}\(f.string(from: to))"
        case let (from?, nil): return "from \(f.string(from: from))"
        case let (nil, to?):   return "to \(f.string(from: to))"
        default:               return ""
        }
    }

    static func title(from: Date?, to: Date?) -> String {
        from == nil && to == nil ? "Date \u{25BE}" : "Date \u{00B7} \(range(from: from, to: to)) \u{25BE}"
    }
}
