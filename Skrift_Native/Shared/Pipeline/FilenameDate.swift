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

    /// The file-date rung (C70): the EARLIER of the file's creation and modification dates. A
    /// copy restamps one of the two (creation on APFS/Finder copies, modification on some
    /// providers' temp copies), so the earlier one is the closer guess.
    static func fileDate(of url: URL) -> Date? {
        let v = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return [v?.creationDate, v?.contentModificationDate].compactMap { $0 }.min()
    }

    /// The ladder for a LOCAL file, every door's one call (Q134): `embedded` is the caller's read
    /// of the content's own date (AVAsset creation date, EXIF); `name` overrides the file's own
    /// name when the file is a renamed copy (a share's temp). nil = the caller's `now` rung.
    static func ladder(embedded: Date?, fileAt url: URL, name: String? = nil) -> Date? {
        ladder(embedded: embedded, filename: name ?? url.lastPathComponent, fileDate: fileDate(of: url))
    }

    /// Dates closer together than this are ONE moment (capture-share-14): WhatsApp stamps every
    /// shared temp copy at the share instant, so their order says nothing and the arrival order
    /// (the chat order) wins.
    static let sameMoment: TimeInterval = 2

    /// The indices of `dates` oldest → newest, STABLE. Keeps the arrival order when any date is
    /// missing or every date sits within `sameMoment` of the others; otherwise sorts by
    /// (date, index). The ONE ordering rule of a bundle on both apps (`MixedBundle.ordered`,
    /// the share extension's clip order).
    static func chronologicalOrder(_ dates: [Date?]) -> [Int] {
        let identity = Array(dates.indices)
        guard dates.count > 1 else { return identity }
        let known = dates.compactMap { $0 }
        guard known.count == dates.count, let lo = known.min(), let hi = known.max(),
              hi.timeIntervalSince(lo) >= sameMoment else { return identity }
        return identity.sorted {
            let a = dates[$0]!, b = dates[$1]!
            return a == b ? $0 < $1 : a < b
        }
    }
}
