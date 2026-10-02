import Foundation

/// The ONE export naming rule both exporters call (C25, C64, C165): the note's title, the
/// vault filename stem derived from it, and the `date:` line. The iPad used to name the file
/// from the user title / first body line while its frontmatter preferred the polished title,
/// the Mac named both from `enhancedTitle` else the audio filename, and `date:` was the
/// phone's local day vs the Mac's UTC `prefix(10)` — so one note could land as two files with
/// two dates (setexp-90, -91, -95). Both bridges now feed the same inputs through here.
enum ExportNaming {

    /// Longest derived title (first body line), in characters — the one number for display
    /// and filename (C25, C165).
    static let derivedLimit = 120

    /// The C25 title ladder: user title → suggested title → first body line (markers
    /// stripped, clipped at 120 on a word boundary) → share title → "Note" / "Voice note".
    /// A share capture with no annotation titles from urlTitle → first 8 words → file name →
    /// "Capture". Never empty, so the filename stem never falls to a synthetic file name.
    static func title(userTitle: String?, suggestedTitle: String?, body: String?,
                      shared: SharedContent?, isVoice: Bool) -> String {
        if let t = trimmed(userTitle) { return t }
        if let t = trimmed(suggestedTitle) { return t }
        if let line = firstLine(body) { return line }
        if shared != nil { return captureTitle(shared) }
        return isVoice ? "Voice note" : "Note"
    }

    /// The capture rung of the ladder (was the Mac-only `BatchRunner.captureFallbackTitle`):
    /// urlTitle → first 8 words of the shared text → file name → "Capture".
    static func captureTitle(_ sc: SharedContent?) -> String {
        if let title = sc?.urlTitle?.trimmingCharacters(in: .whitespaces), !title.isEmpty { return title }
        if let text = sc?.text?.trimmingCharacters(in: .whitespaces), !text.isEmpty {
            let words = text.split(separator: " ")
            let head = words.prefix(8).joined(separator: " ")
            return head.isEmpty ? text : head + (words.count > 8 ? "…" : "")
        }
        if let fileName = sc?.fileName?.trimmingCharacters(in: .whitespaces), !fileName.isEmpty { return fileName }
        return "Capture"
    }

    /// The vault filename stem (C165): title else filename stem, sanitized, capped at 120.
    static func stem(title: String?, filename: String) -> String {
        VaultName.stem(title: title, filename: filename)
    }

    /// The first non-empty line of `body` with markers stripped (`[[img_NNN]]`, name and
    /// memo links, `**Name:**`), clipped at `derivedLimit` on a word boundary. No ellipsis:
    /// the line also names the file, and a filename wants the plain cut.
    static func firstLine(_ body: String?) -> String? {
        guard let body, !body.isEmpty else { return nil }
        let line = NoteSnippet.plain(body)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
        guard let line else { return nil }
        guard line.count > derivedLimit else { return line }
        let head = line.prefix(derivedLimit)
        if let space = head.lastIndex(where: { $0.isWhitespace }) {
            let cut = head[..<space].trimmingCharacters(in: .whitespaces)
            if !cut.isEmpty { return cut }
        }
        return String(head).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - date: (C64)

    /// The recording's LOCAL day, `yyyy-MM-dd`, in `timeZone` (the device's). One rule for
    /// every device: a note recorded at 23:30 is that day everywhere it is exported.
    static func localDay(_ date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// `localDay` of a stored ISO-8601 string (the Mac keeps `recordedAt` as UTC text).
    /// nil when the string does not parse.
    static func localDay(iso: String, timeZone: TimeZone = .current) -> String? {
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

    private static func trimmed(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
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
