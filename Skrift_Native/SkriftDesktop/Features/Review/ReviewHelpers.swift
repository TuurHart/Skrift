import SwiftUI

extension PipelineFile {
    /// Body text precedence — matches the web `getBestText`: the name-linked
    /// `sanitised` (what exports), then the copy-edit, then the raw transcript.
    var bestBodyText: String { sanitised ?? enhancedCopyedit ?? transcript ?? "" }

    /// First non-empty body line, `[[img]]`/`[[memo:]]` markers stripped, capped — the phone's
    /// `firstTranscriptLine` idiom, so a title-less note reads as its opening words.
    var firstBodyLine: String? {
        let cleaned = bestBodyText
            .replacingOccurrences(of: #"\[\[img_\d+\]\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[\[memo:[0-9A-Fa-f\-]{36}\|([^\]\n]*)\]\]"#, with: "$1", options: .regularExpression)
        let line = cleaned.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
        guard let line, !line.isEmpty else { return nil }
        return NoteTitle.clip(line)
    }

    /// The note's DISPLAY name (header · queue list · link chips): enhanced title → first body line
    /// → cleaned filename. Matches the phone (`title ?? firstTranscriptLine`), so an untitled note
    /// reads as its opening words instead of the raw `memo_<UUID>` filename.
    var displayTitle: String {
        if let t = enhancedTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        return firstBodyLine ?? SkriftFormat.cleanFilename(filename)
    }
}

extension SkriftFormat {
    private static let breadcrumbDF: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, d MMM yyyy"
        f.locale = Locale(identifier: "en_GB")
        return f
    }()

    static func breadcrumbDate(_ d: Date) -> String { breadcrumbDF.string(from: d) }
}
