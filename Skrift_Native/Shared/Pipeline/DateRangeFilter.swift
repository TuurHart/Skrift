import Foundation

/// Inclusive date-range membership — ONE rule for both apps' Filter sheets (the
/// iPad's `MemoFilter` from/to and the Mac sidebar's uploaded-date filter). A nil
/// bound is open; `to` includes the whole day it names.
enum DateRangeFilter {
    static func contains(_ date: Date, from: Date?, to: Date?, calendar: Calendar = .current) -> Bool {
        if let from, date < calendar.startOfDay(for: from) { return false }
        if let to,
           let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to)),
           date >= end { return false }
        return true
    }
}
