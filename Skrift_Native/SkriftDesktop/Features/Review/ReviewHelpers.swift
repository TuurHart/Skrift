import SwiftUI

extension PipelineFile {
    /// The share capture behind this row (its annotation lives in `transcript`), else nil.
    private var ladderShared: SharedContent? {
        sourceType == .capture ? SharedContent.decode(from: audioMetadataJSON) : nil
    }

    /// The note's DISPLAY name (header · queue list · link chips): the C25 ladder
    /// (`NoteTitle.display`) over the same inputs as `exportTitle` — `enhancedTitle` carries
    /// the user's / suggested title, the body is the RAW text. The last rung is "Note" /
    /// "Voice note"; an import with a real file name keeps that name until it has words (D176).
    var displayTitle: String {
        let isVoice = sourceType == .audio && mediaSource != "typed"
        // D176: a real file name shows until the note has words (a phone import's name rides the
        // metadata; a Mac-local import's is its own file name); a generic default or a synthetic
        // `memo_<UUID>` falls back to "Voice note" (`NoteTitle.importName`).
        return NoteTitle.display(userTitle: nil, suggestedTitle: enhancedTitle, body: transcript,
                                 shared: ladderShared,
                                 importFileName: NoteTitle.importFileName(metadataJSON: audioMetadataJSON, workingFilename: filename,
                                                                          isCapture: sourceType == .capture),
                                 emptyFallback: isVoice ? "Voice note" : "Note")
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
