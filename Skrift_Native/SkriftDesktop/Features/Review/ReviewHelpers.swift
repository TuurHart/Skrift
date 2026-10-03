import SwiftUI

extension PipelineFile {
    /// The share capture behind this row (its annotation lives in `transcript`), else nil.
    private var ladderShared: SharedContent? {
        sourceType == .capture ? SharedContent.decode(from: audioMetadataJSON) : nil
    }

    /// The note's DISPLAY name (header · queue list · link chips): the C25 ladder
    /// (`NoteTitle.display`) over the same inputs as `exportTitle` — `enhancedTitle` carries
    /// the user's / suggested title, the body is the RAW text. The last rung is "Note" /
    /// "Voice note"; a Mac-local import with a real file name keeps that name until it has
    /// words, but a synthetic `memo_<UUID>` name never shows.
    var displayTitle: String {
        let isVoice = sourceType == .audio && mediaSource != "typed"
        var fallback = isVoice ? "Voice note" : "Note"
        let name = SkriftFormat.cleanFilename(filename)
        if sourceType != .capture, !name.isEmpty, !name.lowercased().hasPrefix("memo_") { fallback = name }
        return NoteTitle.display(userTitle: nil, suggestedTitle: enhancedTitle, body: transcript,
                                 shared: ladderShared, emptyFallback: fallback)
    }

    /// What the header's empty title field ghosts (C25 + Q177): the ladder's derived title,
    /// nil when the note has nothing to derive from (the field shows "Add a title").
    var titleGhost: String? {
        NoteTitle.derived(userTitle: nil, suggestedTitle: enhancedTitle, body: transcript,
                          shared: ladderShared)
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
