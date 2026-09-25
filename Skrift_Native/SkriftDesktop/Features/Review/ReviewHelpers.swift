import SwiftUI

extension PipelineFile {
    // `durationSeconds` moved to Models/PipelineFile.swift — it's a read of the stored
    // metadata blob, not a view helper, and Models/ is compiled into the host-less test
    // bundle so the two-shapes rule can actually be tested.

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
    // `seconds(fromHMS:)` is gone — parsing the stored value is
    // `PipelineFile.durationSeconds(fromMetadataValue:)`, which handles the numeric
    // shape too. This left a string-only parser sitting next to a reader that needed
    // both, which is how the synced-note duration went missing.
    //
    // `.clock(_:)` (m:ss only, no hours) is GONE (sweep E finding #10, sweep-d-mac.md
    // #10): it disagreed with `.duration(seconds:)` past 60 minutes — the header/
    // player read e.g. "125:33" for the SAME note the sidebar correctly read "2:05:33".
    // Every former `.clock` call site now routes through `.duration(seconds:)`.

    private static let breadcrumbDF: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, d MMM yyyy"
        f.locale = Locale(identifier: "en_GB")
        return f
    }()

    static func breadcrumbDate(_ d: Date) -> String { breadcrumbDF.string(from: d) }
}
