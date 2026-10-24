import Foundation

/// What is left of v1's export compiler after Q437 (the compile half is at tag `v1-export`;
/// both apps export through `ExportV2`): the quote rendering the Mac's note view and the
/// capture splitter share, the capture block the Mac's capture view shows, and the `people:`
/// list `CompilerInput.make` derives.
enum Compiler {
    /// Spec 7: the captured quote block renders in ITALICS with the attribution
    /// line under it — "— [[Author]], *Book*, ch. N" (author/chapter omitted when
    /// absent). The `[[Author]]` wikilink is written HERE, at compile/export ONLY:
    /// authors never enter the names DB, and the Sanitiser ran before compile (and
    /// never touches links it doesn't know), so the link survives untouched. A
    /// capture body without a leading quote block is returned as-is.
    /// Q355: with `url` (a Library article) the place is the site, written as the link:
    /// `— *Title*, [site](URL)` (mock Q351 pick 3).
    static func audiobookBody(_ body: String, book: String, author: String?, chapter: String?,
                              url: String? = nil) -> String {
        guard let split = QuoteProtection.splitLeadingQuote(body) else { return body }

        // The block comes from the one splitter (`CaptureQuote.split` via the adapter), so it
        // may carry leading blank lines or an indented marker; both normalise to "> " here.
        let italicQuote = split.quote.components(separatedBy: "\n").compactMap { line -> String? in
            let marker = CaptureQuote.markerLength(ofLine: line)
            guard marker > 0 || !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let text = (line as NSString).substring(from: marker).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return ">" }
            // Already emphasised (a re-render or a hand edit) → don't double-wrap.
            if text.count > 1, text.hasPrefix("*"), text.hasSuffix("*") { return "> \(text)" }
            return "> *\(text)*"
        }.joined(separator: "\n")

        // ONE attribution builder (`CaptureQuote.attributionParts`, `.vault` punctuation): the
        // same empty-author guard and chapter rule as the in-app caption (C60 — a named
        // chapter as-is, only a numeric one gets "ch. ").
        let attribution: String
        if let url, !url.isEmpty {
            let named = chapter?.trimmingCharacters(in: .whitespaces) ?? ""
            let site = named.isEmpty ? (URL(string: url)?.host ?? url) : named
            attribution = "> — *\(book)*, [\(site)](\(url))"
        } else {
            attribution = "> " + (CaptureQuote.attribution(book: book, author: author, chapter: chapter, style: .vault)
                                  ?? "— *\(book)*")
        }

        let block = italicQuote + "\n>\n" + attribution
        return split.ramble.isEmpty ? block : block + "\n\n" + split.ramble
    }

    // MARK: Capture shared-content block

    /// Build the pinned shared-content Markdown block for the three capture types (C3).
    /// - url:   bold title + full URL on its own line (intact, Obsidian imports as a link).
    /// - text:  the snippet as a Markdown blockquote.
    /// - image: `![[filename]]` Obsidian embed (the actual file is copied by the exporter) —
    ///          UNLESS the body already places the photos via `[[img_NNN]]` markers (share
    ///          Wave 2: the phone inlines photos in the annotation like a recorded memo;
    ///          the pinned embed would double-embed photo 1 under a stale share-time name).
    static func captureSharedBlock(_ sc: SharedContent, body: String = "") -> String {
        var lines: [String] = []
        switch sc.type {
        case .url:
            if let title = sc.urlTitle, !title.isEmpty { lines.append("**\(title)**") }
            if let url = sc.url, !url.isEmpty { lines.append(url) }
            if !lines.isEmpty { lines.append("") }   // blank line before body
        case .text:
            if let text = sc.text, !text.isEmpty {
                // Multi-line snippets: prefix each line with "> ".
                let quoted = text.components(separatedBy: "\n")
                    .map { "> \($0)" }.joined(separator: "\n")
                lines.append(quoted)
                lines.append("")
            }
        case .image:
            if let name = sc.fileName, !name.isEmpty, !body.contains("[[img_") {
                lines.append("![[" + name + "]]")
                lines.append("")
            }
        case .file:
            break   // a file capture pins nothing above the body (the exporter copies the file)
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n")
    }

    /// The DISTINCT canonical names this note links — the `people:` graph list. Reads the
    /// body's `[[Name]]` wiki-links (`[[img_NNN]]` markers already excluded by
    /// `linkOccurrences`), takes each link's canonical TARGET (the part before any `|spoken`
    /// alias-display), and de-duplicates case-insensitively in reading order. Derived from
    /// the rendered body so it can never drift from what's actually linked (one-note-one-link
    /// → one entry per person, conversations include matched speakers).
    ///
    /// Image EMBEDS (`![[file]]`) are skipped (the `[[ ]]` is an embed, not a link), and when
    /// `knownPeople` is supplied the list is filtered to PERSONS — so a transcript/Apple-Note
    /// body carrying a place link (`[[Hotel Du Vin]]`) never lands in `people:`. nil
    /// `knownPeople` = no filter (engine-level callers/tests).
    static func peopleLinks(in body: String, knownPeople: [Person]? = nil) -> [String] {
        let allow: Set<String>? = knownPeople.map {
            Set($0.filter { !$0.isDeleted }.map { NamesMerge.matchKey($0.canonical) })
        }
        var seen = Set<String>()
        var out: [String] = []
        for link in Sanitiser.bodyLinks(in: body) {   // image embeds already skipped
            let target = Sanitiser.linkTarget(link.core)
            let key = target.lowercased()
            guard !target.isEmpty, allow?.contains(key) ?? true, seen.insert(key).inserted else { continue }
            out.append(target)
        }
        return out
    }
}
