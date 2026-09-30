import Foundation

/// The one place a note body becomes the PLAIN text of a list-row snippet. A body is stored as
/// markup (`**Speaker 1:** …` turn headers, `[[Tiuri Hartog]]` name links, `[[img_001]]` picture
/// markers); a list row must show none of it (Tuur 2026-09-27: rows read `**Speaker 1:**` and
/// `[[Tiuri Hartog]]`). Both apps' rows go through here so they can't drift.
enum NoteSnippet {
    static func plain(_ text: String) -> String {
        var s = text
        let rules: [(String, String)] = [
            (#"\[\[img_\d+\]\]"#, ""),                                    // picture marker
            (#"\[\[memo:[0-9A-Fa-f\-]{36}\|([^\]\n]*)\]\]"#, "$1"),         // memo link → its title
            (#"\[\[([^\]\|\n]*)\|([^\]\n]*)\]\]"#, "$2"),                   // [[Canonical|spoken]] → spoken
            (#"\[\[([^\]\n]*)\]\]"#, "$1"),                                 // [[Name]] → Name
            (#"\*\*([^*\n]+)\*\*"#, "$1"),                                  // **bold** / **Name:**
        ]
        for (pattern, template) in rules {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return s
    }
}
