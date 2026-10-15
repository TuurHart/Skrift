import Foundation

/// The one place the export engines (Mac `VaultExporter`, phone `ObsidianPublisher`) run the
/// Q13 shown-body fallback over a compiled note (C239: no twin copy).
enum ExportBody {
    /// `BodyV2Legacy.shown` over the BODY only. Run over the whole compiled markdown, a body
    /// opening with a picture reads the frontmatter's closing `---` as the sentence before the
    /// marker, defers the photo to that sentence's end and fuses the fence onto the first
    /// sentence, so the note lost its stamp (Q445). The frontmatter block and the blank lines
    /// after it pass through untouched.
    static func shown(_ markdown: String) -> String {
        guard markdown.hasPrefix("---\n"),
              let close = markdown.range(of: "\n---\n", range: markdown.index(markdown.startIndex, offsetBy: 3)..<markdown.endIndex)
        else { return BodyV2Legacy.shown(markdown).text }
        var split = close.upperBound
        while split < markdown.endIndex, markdown[split] == "\n" { split = markdown.index(after: split) }
        return String(markdown[..<split]) + BodyV2Legacy.shown(String(markdown[split...])).text
    }

    /// `[[vid_NNN]]` / `[[file_NNN]]` markers -> this profile's embeds of the files copied beside
    /// the note (D199, C57/C58). The ONE conversion both engines run: the Mac (`MacNoteAttachments`)
    /// places each file through its ownership placer; the iPad (`ObsidianPublisher`) records the
    /// (source filename, embed name) pairs and hands the bytes to `VaultWriter.commit`, whose
    /// ownership pass (C58) settles the final names. `place(source, preferredName)` returns the
    /// name written, nil when the file is not there; a marker with no manifest entry or no file is
    /// DROPPED, never printed (C196).
    static func convertAttachmentMarkers(_ markdown: String, manifest: [NoteAttachmentEntry], stem: String,
                                         profile: ExportProfile,
                                         poster: (_ keptMovie: String, _ preferredName: String) -> String? = { _, _ in nil },
                                         place: (_ source: String, _ preferredName: String) -> String?)
        -> (markdown: String, placed: Int) {
        guard markdown.contains("[[vid_") || markdown.contains("[[file_") else { return (markdown, 0) }
        // C63 / D210: a video note's own kept movie never goes into the vault (only the portfolio
        // export copies it, by filename). Its marker becomes an image embed of the poster frame
        // (`VideoExportFrame`, named `<stem>_frame.jpg`) when the engine can make one (`poster`
        // answers the written name, nil = no frame), else it drops like a missing file's. Both engines.
        return NoteAttachment.convertMarkers(markdown, manifest: manifest, stem: stem, profile: profile) { source, preferred in
            NoteAttachment.isKeptMovie(source)
                ? poster(source, VideoExportFrame.exportName(stem: stem))
                : place(source, preferred)
        }
    }
}
