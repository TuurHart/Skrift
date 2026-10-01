import Foundation

/// The ONE filename-date ladder step (C70): the date a messaging app / recorder wrote into a
/// file's NAME. Mac ingest and the phone's share drain both call it, so a Signal bundle dates
/// the same on both. Pure.
enum FilenameDate {

    /// Best-effort recording date parsed from common messaging/recorder filenames,
    /// e.g. "WhatsApp Audio 2025-12-18 at 18.30.44", "signal-2026-04-13-18-15-24-552",
    /// "signal-2026-10-01-080349" (compact), "AUDIO-2026-03-07-19-30-08". Local time; time
    /// defaults to noon if absent. nil when no `YYYY-MM-DD` is present (so a plain
    /// "New Recording 22" falls through).
    static func date(from name: String) -> Date? {
        guard let rx = try? NSRegularExpression(
            pattern: #"(\d{4})-(\d{2})-(\d{2})(?:[ _\-]?(?:at )?(?:(\d{2})[.\-:](\d{2})[.\-:](\d{2})|(\d{2})(\d{2})(\d{2})(?!\d)))?"#) else { return nil }
        let ns = name as NSString
        guard let m = rx.firstMatch(in: name, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func g(_ i: Int) -> Int? { let r = m.range(at: i); return r.location == NSNotFound ? nil : Int(ns.substring(with: r)) }
        guard let y = g(1), let mo = g(2), let d = g(3), (1...12).contains(mo), (1...31).contains(d) else { return nil }
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d
        // Separated (18.30.44) or compact (Signal pictures: `signal-2026-10-01-080349`).
        c.hour = g(4) ?? g(7) ?? 12; c.minute = g(5) ?? g(8) ?? 0; c.second = g(6) ?? g(9) ?? 0
        return Calendar.current.date(from: c)
    }

    /// Of several candidate names for ONE file (provider temp URL, suggestedName, …), the first
    /// that carries a date, else the first non-empty one.
    static func bestName(_ candidates: [String?]) -> String? {
        let names = candidates.compactMap { $0 }.filter { !$0.isEmpty }
        return names.first { date(from: $0) != nil } ?? names.first
    }

    /// The C70 ladder for one item: embedded date → date in the filename → file date.
    /// (`now` is the caller's last rung.) Pure: the caller supplies each rung.
    static func ladder(embedded: Date?, filename: String?, fileDate: Date?) -> Date? {
        embedded ?? filename.flatMap { date(from: $0) } ?? fileDate
    }
}
