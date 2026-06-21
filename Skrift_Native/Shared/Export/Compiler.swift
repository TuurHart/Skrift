import Foundation

/// Assembles Obsidian-ready markdown (YAML frontmatter + body) from a neutral
/// `CompilerInput`. Pure (no IO) → host-testable, and `PipelineFile`-free so BOTH apps
/// compile the SAME engine (standalone Phase 2; desktop maps via `PipelineFile.compilerInput`,
/// mobile via `MemoExporter`). Ported from `enhancement.py:compile_file`. Body precedence:
/// sanitised → enhanced copy-edit → transcript (the name-linked text wins, since it's what
/// exports). The vault write/copy is the Export step.
enum Compiler {
    /// `knownPeople` (the live names DB) filters the `people:` list to actual persons —
    /// excluding non-person wiki-links (places like `[[Hotel Du Vin]]`, manual links) that a
    /// transcript/Apple-Note body may carry. nil = no filter (engine tests / minor call sites).
    static func compile(_ input: CompilerInput, author: String, date overrideDate: String? = nil,
                        knownPeople: [Person]? = nil) -> String {
        let meta = input.metadata
        let sc = input.sharedContent   // nil for non-captures

        // For captures the annotation body comes from sanitised/transcript only — no copy-edit layer.
        let body = firstNonEmpty(input.sanitised, input.enhancedCopyedit, input.transcript) ?? ""
        let summary = (input.enhancedSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawStem = (input.filename as NSString).deletingPathExtension
        let title = firstNonEmpty(input.enhancedTitle, rawStem) ?? rawStem

        // `date` from the phone's `recordedAt` (captures use this as the share
        // time); falls back to the raw metadata JSON when the metadata didn't decode.
        let recordedAt = meta?.recordedAt ?? input.rawRecordedAt
        let date = overrideDate ?? recordedAt.map { String($0.prefix(10)) } ?? ""

        // Audiobook quote-capture (spec 7): the presence of a book title marks the
        // memo as a capture from an actively-mined audiobook.
        let bookTitle = trimmedNonEmpty(meta?.bookTitle)
        let bookAuthor = trimmedNonEmpty(meta?.bookAuthor)
        let bookChapter = trimmedNonEmpty(meta?.bookChapter)

        // `source:` reflects the memo's true origin (matches the sidebar glyph +
        // detail "source" label). A video import + an audiobook quote both ride
        // `sourceType: .audio`, so the markers (`bookTitle`, `mediaSource`) win first.
        let source: String
        if bookTitle != nil {
            source = "Audiobook-quote"
        } else if input.mediaSource == "video" {
            source = "Video"
        } else {
            switch input.sourceType {
            case .note: source = "Apple-Note"
            case .audio: source = "Voice-memo"
            case .capture:
                switch sc?.type {
                case "url":   source = "capture-url"
                case "text":  source = "capture-text"
                case "image": source = "capture-image"
                case "file":  source = "capture-file"
                default:      source = "capture"
                }
            }
        }

        var y: [String] = [
            "---",
            // Quoted: Gemma titles routinely carry ": " which is invalid in a
            // plain YAML scalar — Obsidian then rejects the whole frontmatter.
            "title: \(yamlQuoted(title))",
            "date: \(date)",
            "lastTouched:",
            "author: \(author)",
            "source: \(source)",
        ]
        // People this note is ABOUT: the distinct canonical wiki-links present in the body.
        // Carries the graph connection that the body's one-note-one-link rule keeps to a
        // single link per person.
        let peopleLinks = peopleLinks(in: body, knownPeople: knownPeople)
        y.append(peopleLinks.isEmpty ? "people:"
                 : "people: " + peopleLinks.map { "[[\($0)]]" }.joined(separator: ", "))
        // Book frontmatter (C2 → spec 7). `bookAuthor:` not `author:` — that key is
        // the note's author (the user) above. Values quoted: titles carry colons.
        if let bookTitle { y.append("book: \"\(bookTitle)\"") }
        if let bookAuthor { y.append("bookAuthor: \"\(bookAuthor)\"") }
        if let bookChapter { y.append("chapter: \"\(bookChapter)\"") }
        // `url:` key only for url captures (C3 §compile).
        if input.sourceType == .capture, let url = sc?.url, !url.isEmpty {
            y.append("url: \(url)")
        }
        if let place = meta?.location?.placeName, !place.isEmpty {
            y.append("location: \"\(place)\"")
        } else {
            y.append("location:")
        }
        if let w = meta?.weather, let c = w.conditions, let t = w.temperature {
            y.append("weather: \"\(c), \(fmtNum(t))\(w.temperatureUnit ?? "°C")\"")
        }
        if let hPa = meta?.pressure?.hPa { y.append("pressure: \(fmtNum(hPa))") }
        if let trend = meta?.pressure?.trend, !trend.isEmpty { y.append("pressureTrend: \(trend)") }
        if let dp = meta?.dayPeriod, !dp.isEmpty { y.append("dayPeriod: \(dp)") }
        if let d = meta?.daylight, let sr = d.sunrise, let ss = d.sunset {
            y.append("daylight:")
            y.append("  sunrise: \"\(sr)\"")
            y.append("  sunset: \"\(ss)\"")
            if let h = d.hoursOfLight { y.append("  hoursOfLight: \(fmtNum(h))") }
        }
        if let steps = meta?.steps { y.append("steps: \(steps)") }

        y.append("tags:")
        for t in input.tags { y.append("  - \(t)") }
        y.append(input.significance != nil ? "significance: \(String(format: "%.1f", input.significance!))" : "significance:")
        y.append(summary.isEmpty ? "summary:" : "summary: \(yamlQuoted(summary))")
        y.append("---")
        y.append("")

        let frontmatter = y.joined(separator: "\n") + "\n"

        // Captures pin the shared-content block ABOVE the annotation body (C3 §compile).
        if input.sourceType == .capture, let sc {
            return frontmatter + captureSharedBlock(sc) + body
        }
        // Audiobook quote memos italicise the quote + add the attribution line.
        let renderedBody = bookTitle.map {
            audiobookBody(body, book: $0, author: bookAuthor, chapter: bookChapter)
        } ?? body
        return frontmatter + renderedBody
    }

    /// Spec 7: the captured quote block renders in ITALICS with the attribution
    /// line under it — "— [[Author]], *Book*, ch. N" (author/chapter omitted when
    /// absent). The `[[Author]]` wikilink is written HERE, at compile/export ONLY:
    /// authors never enter the names DB, and the Sanitiser ran before compile (and
    /// never touches links it doesn't know), so the link survives untouched. A
    /// capture body without a leading quote block is returned as-is.
    static func audiobookBody(_ body: String, book: String, author: String?, chapter: String?) -> String {
        guard let split = QuoteProtection.splitLeadingQuote(body) else { return body }

        let italicQuote = split.quote.components(separatedBy: "\n").map { line -> String in
            guard line.hasPrefix(">") else { return line }
            var content = String(line.dropFirst())
            if content.hasPrefix(" ") { content.removeFirst() }
            let text = content.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return ">" }
            // Already emphasised (a re-render or a hand edit) → don't double-wrap.
            if text.count > 1, text.hasPrefix("*"), text.hasSuffix("*") { return "> \(text)" }
            return "> *\(text)*"
        }.joined(separator: "\n")

        var parts: [String] = []
        if let author { parts.append("[[\(author)]]") }
        parts.append("*\(book)*")
        if let chapter { parts.append("ch. \(chapter)") }
        let attribution = "> — " + parts.joined(separator: ", ")

        let block = italicQuote + "\n>\n" + attribution
        return split.ramble.isEmpty ? block : block + "\n\n" + split.ramble
    }

    // MARK: Capture shared-content block

    /// Build the pinned shared-content Markdown block for the three capture types (C3).
    /// - url:   bold title + full URL on its own line (intact, Obsidian imports as a link).
    /// - text:  the snippet as a Markdown blockquote.
    /// - image: `![[filename]]` Obsidian embed (the actual file is copied by the exporter).
    static func captureSharedBlock(_ sc: CompilerSharedContent) -> String {
        var lines: [String] = []
        switch sc.type {
        case "url":
            if let title = sc.urlTitle, !title.isEmpty { lines.append("**\(title)**") }
            if let url = sc.url, !url.isEmpty { lines.append(url) }
            if !lines.isEmpty { lines.append("") }   // blank line before body
        case "text":
            if let text = sc.text, !text.isEmpty {
                // Multi-line snippets: prefix each line with "> ".
                let quoted = text.components(separatedBy: "\n")
                    .map { "> \($0)" }.joined(separator: "\n")
                lines.append(quoted)
                lines.append("")
            }
        case "image":
            if let name = sc.fileName, !name.isEmpty {
                lines.append("![[" + name + "]]")
                lines.append("")
            }
        default:
            break
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n")
    }

    // MARK: Helpers

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
        let ns = body as NSString
        let allow: Set<String>? = knownPeople.map {
            Set($0.filter { !$0.isDeleted }.map { NamesMerge.keyName($0.canonical).trimmingCharacters(in: .whitespaces).lowercased() })
        }
        var seen = Set<String>()
        var out: [String] = []
        for link in Sanitiser.linkOccurrences(in: body) {
            // Skip an Obsidian image embed: a `[[ ]]` immediately preceded by `!`.
            if link.range.location > 0, ns.substring(with: NSRange(location: link.range.location - 1, length: 1)) == "!" { continue }
            let target = Sanitiser.linkTarget(link.core)
            let key = target.lowercased()
            guard !target.isEmpty, allow?.contains(key) ?? true, seen.insert(key).inserted else { continue }
            out.append(target)
        }
        return out
    }

    /// Double-quote a YAML scalar, escaping embedded `\` and `"`. Plain scalars
    /// break on ": " (and other indicators) — always-quoting is simpler and safe.
    private static func yamlQuoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func firstNonEmpty(_ vals: String?...) -> String? {
        for v in vals {
            if let v, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return v }
        }
        return nil
    }

    private static func trimmedNonEmpty(_ v: String?) -> String? {
        guard let t = v?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        return t
    }

    /// Whole numbers print without a trailing `.0` (e.g. 21, 1013), fractions keep it.
    private static func fmtNum(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(d)
    }
}
