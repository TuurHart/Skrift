import Foundation

/// The ONE export naming rule both exporters call (C25, C64, C165): the note's title, the
/// vault filename stem derived from it, and the `date:` line. The iPad used to name the file
/// from the user title / first body line while its frontmatter preferred the polished title,
/// the Mac named both from `enhancedTitle` else the audio filename, and `date:` was the
/// phone's local day vs the Mac's UTC `prefix(10)` — so one note could land as two files with
/// two dates (setexp-90, -91, -95). Both bridges now feed the same inputs through here.
enum ExportNaming {
    /// Longest derived title, in characters — display AND filename (C25, C165). Lives in `NoteTitle`.
    static let derivedLimit = NoteTitle.derivedLimit

    /// The C25 title ladder — `NoteTitle.display`, the same rule the lists and headers read.
    /// Never empty, so the filename stem never falls to a synthetic file name.
    static func title(userTitle: String?, suggestedTitle: String?, body: String?,
                      shared: SharedContent?, isVoice: Bool) -> String {
        NoteTitle.display(userTitle: userTitle, suggestedTitle: suggestedTitle, body: body,
                          shared: shared, emptyFallback: isVoice ? "Voice note" : "Note")
    }

    /// The capture rung of the ladder (`NoteTitle.captureTitle`).
    static func captureTitle(_ sc: SharedContent?) -> String { NoteTitle.captureTitle(sc) }

    /// The ladder's first-body-line rung (`NoteTitle.firstLine`).
    static func firstLine(_ body: String?) -> String? { NoteTitle.firstLine(body) }

    /// The vault filename stem (C165): title else filename stem, sanitized, capped at 120.
    static func stem(title: String?, filename: String) -> String {
        VaultName.stem(title: title, filename: filename)
    }


    // MARK: - date: (C64)

    /// The device's zone: `NSTimeZone.default` is the system zone unless the app (or a test)
    /// set one; `TimeZone.current` ignores that override.
    static var deviceZone: TimeZone { NSTimeZone.default }

    /// The recording's LOCAL day, `yyyy-MM-dd`, in `timeZone` (the device's). One rule for
    /// every device: a note recorded at 23:30 is that day everywhere it is exported.
    static func localDay(_ date: Date, timeZone: TimeZone = deviceZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// `localDay` of a stored ISO-8601 string (the Mac keeps `recordedAt` as UTC text).
    /// nil when the string does not parse.
    static func localDay(iso: String, timeZone: TimeZone = deviceZone) -> String? {
        parseISO(iso).map { localDay($0, timeZone: timeZone) }
    }

    /// Parses ISO-8601 with or without fractional seconds (phone builds wrote both).
    static func parseISO(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let d = ISO8601.date(from: t) { return d }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: t)
    }
}

extension ExportNaming {
    /// The phone/iPad side of the ladder, from the synced `Memo` + the Mac's write-back
    /// (`MemoEnhancement.title` is the suggested title). Shared so the Mac's tests can run
    /// the iPad's exact input next to its own.
    static func title(for memo: Memo, enhancement: MemoEnhancement?) -> String {
        let capture = memo.audioFilename.isEmpty && memo.sharedContent != nil
        return title(userTitle: memo.title,
                     suggestedTitle: enhancement?.title,
                     body: capture ? memo.annotationText : memo.transcript,
                     shared: capture ? memo.sharedContent : nil,
                     isVoice: !memo.audioFilename.isEmpty)
    }
}
