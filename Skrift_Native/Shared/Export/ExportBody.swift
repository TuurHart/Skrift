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
}
