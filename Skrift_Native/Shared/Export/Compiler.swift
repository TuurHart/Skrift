import Foundation

/// Assembles Obsidian-ready markdown (YAML frontmatter + body) from a neutral
/// `CompilerInput`. Pure (no IO) → host-testable, and `PipelineFile`-free so BOTH apps
/// compile the SAME engine (standalone Phase 2; desktop maps via `PipelineFile.compilerInput`,
/// mobile via `MemoExporter`). Ported from `enhancement.py:compile_file`. Body precedence:
/// sanitised → enhanced copy-edit → transcript (the name-linked text wins, since it's what
/// exports). The vault write/copy is the Export step.
enum Compiler {
    /// The `source:` / `capture:` value of a typed note (Q142) — one spelling for both apps.
    static let typedSource = "Typed-note"

    /// `knownPeople` (the live names DB) filters the `people:` list to actual persons —
    /// excluding non-person wiki-links (places like `[[Hotel Du Vin]]`, manual links) that a
    /// transcript/Apple-Note body may carry. nil = no filter (engine tests / minor call sites).
    static func compile(_ input: CompilerInput, author: String, date overrideDate: String? = nil,
                        knownPeople: [Person]? = nil,
                        profile: ExportProfile = .obsidian) -> String {
        let meta = input.metadata
        let sc = input.sharedContent   // nil for non-captures

        // For captures the annotation body comes from sanitised/transcript only — no copy-edit layer.
        // Memo↔memo links leave the app here: `[[memo:UUID|Title]]` → a real
        // wikilink (resolver-precise, or the readable [[Title]] fallback).
        var body = MemoLinkSyntax.exportRewrite(
            firstNonEmpty(input.sanitised, input.enhancedCopyedit, input.transcript) ?? "",
            resolveStem: input.memoLinkResolver)
        // PORTFOLIO: keep the PEOPLE links, drop every other one. Tuur's call (2026-08-26), and
        // a deliberate reversal of my privacy advice — the portfolio becomes a public site and
        // he wants his friends credited by name. A place (`[[Hotel Du Vin]]`) carries no such
        // intent, and a link to a note that isn't in the portfolio is just a broken link, so
        // both degrade to the plain word. Nothing is deleted; only the brackets go.
        if !profile.keepsPlaceLinks { body = plainifyNonPeopleLinks(in: body, knownPeople: knownPeople) }
        let summary = (input.enhancedSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawStem = (input.filename as NSString).deletingPathExtension
        // Both bridges pass the C25 ladder's title (`ExportNaming.title`); the stem is the
        // engine-test fallback only.
        let title = firstNonEmpty(input.enhancedTitle, rawStem) ?? rawStem

        // `date` from the phone's `recordedAt` (captures use this as the share
        // time); falls back to the raw metadata JSON when the metadata didn't decode.
        let recordedAt = meta?.recordedAt ?? input.rawRecordedAt
        // The recording's LOCAL day (C64), never the UTC text's first ten characters: the
        // Mac stores `recordedAt` as UTC, so `prefix(10)` moved a 23:30 note to tomorrow.
        // An unparseable string keeps the old prefix rule.
        let date = overrideDate
            ?? recordedAt.map { ExportNaming.localDay(iso: $0) ?? String($0.prefix(10)) } ?? ""

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
        } else if input.kind == .typedNote {
            // A note born typed (Q142). Each exporter sets `kind` from `SourceKind`; before
            // this the phone wrote `Voice-memo` (typed rides `.audio`) and the Mac
            // `Apple-Note` (typed rides `.note`) for the same note.
            source = Compiler.typedSource
        } else {
            switch input.sourceType {
            case .note: source = "Apple-Note"
            case .audio: source = "Voice-memo"
            case .capture:
                // Exhaustive over `ShareContentType`: a new capture type fails the build here
                // instead of silently exporting as a bare `capture`. nil = no shared content.
                switch sc?.type {
                case .url?:   source = "capture-url"
                case .text?:  source = "capture-text"
                case .image?: source = "capture-image"
                case .file?:  source = "capture-file"
                case nil:     source = "capture"
                }
            }
        }

        // FRONTMATTER ORDER, grouped by who each key is for (Tuur, 2026-08-14 — he asked
        // for the hash "in a more sensible order"). Obsidian's Properties panel renders in
        // this order, so the order IS the reading experience:
        //   1. what you read first — title / date / author / source (+ book, url)
        //   2. what the note is about — summary / tags / people / significance
        //   3. where you were — location, weather, pressure, daylight, steps
        //   4. Skrift's bookkeeping, last and TOGETHER — lastTouched / skriftID / skriftHash
        // The stamp used to be split: `lastTouched` sat third while its two siblings were
        // appended at the bottom, and `summary` — the one line worth reading — was buried
        // under a dozen sensor fields.
        var y: [String] = [
            "---",
            // Quoted: Gemma titles routinely carry ": " which is invalid in a
            // plain YAML scalar — Obsidian then rejects the whole frontmatter.
            "title: \(yamlQuoted(title))",
            "date: \(date)",
            // `author:` is the note's author. DROPPED on the portfolio (Tuur's brief, confirmed
            // 2026-08-27 against the real item frontmatter, which has no such key): everything
            // in the portfolio is his by that portfolio's hard rule, so the field could only ever
            // hold one value. `voice:` below carries what actually varies.
            profile == .portfolio ? nil : "author: \(author)",
            // `source:` in the VAULT only. The portfolio already owns that key for an item's
            // provenance (`source: Portfolio - OG/8 Lamps/…`), so writing "Voice-memo" into it
            // would be clobbered the moment an entry is sorted into an item. The portfolio gets
            // `capture:` instead — how the words arrived, which is what Skrift actually knows.
            profile == .portfolio ? "capture: \(source)" : "source: \(source)",
        ].compactMap { $0 }
        // Book frontmatter (C2 → spec 7). `bookAuthor:` not `author:` — that key is
        // the note's author (the user) above. Values quoted: titles carry colons.
        // Kept beside `source:` because that is what they describe.
        if let bookTitle { y.append("book: \"\(bookTitle)\"") }
        if let bookAuthor { y.append("bookAuthor: \"\(bookAuthor)\"") }
        if let bookChapter { y.append("chapter: \"\(bookChapter)\"") }
        // `url:` key only for url captures (C3 §compile).
        if input.sourceType == .capture, let url = sc?.url, !url.isEmpty {
            y.append("url: \(url)")
        }
        // `type:` is NOT ours. I shipped `type: idea` for a day; reading the portfolio on
        // 2026-08-27 killed it — `type:` is that repo's CATEGORY key, already on 100+ items
        // (`type: lamps`, `type: furniture`, `type: things that do something`), taken verbatim
        // from his own folder names. An entry sorted out of `_ideas/` into `Lamps/` would have
        // had one key meaning two things. The folder says which bucket a capture arrived in,
        // and once it is sorted that fact is spent.
        if profile == .portfolio {
            // `voice:` — the portfolio's own key, its own three values, and its own rule:
            // "cleaned means grammar and punctuation ONLY — his words, his order, diffable
            // against the raw capture", which is exactly what the copy-edit is.
            y.append("voice: \(input.voice.rawValue)")
            // `needs:` — also the portfolio's own key (an empty `Renders/` becomes a need). An
            // INSPIRATION is someone else's work by definition, so one without a maker is
            // always incomplete and always worth the punch-list line. Project and Idea are HIS,
            // so raising credit on them would be a false need — and a punch list of false
            // needs stops being a punch list.
            //
            // The TAG counts too (Tuur, 2026-08-27): "if I see a cool thing that inspires me…
            // it's just an idea with a hashtag inspiration as well." That note is filed Idea
            // because the intent is his, but the OBJECT is someone else's — so it owes a credit
            // exactly like an Inspiration does, and the folder alone would have lost it.
            let taggedInspiration = input.tags.contains {
                NoteDestination.reserved($0) == .inspiration
            }
            if input.destination == .inspiration || taggedInspiration {
                y.append("needs:")
                y.append("  - credit")
            }
        }

        // ── what the note is about ──
        y.append(summary.isEmpty ? "summary:" : "summary: \(yamlQuoted(summary))")
        y.append("tags:")
        for t in input.tags { y.append("  - \(t)") }
        // People this note is ABOUT: the distinct canonical wiki-links present in the body.
        // Carries the graph connection that the body's one-note-one-link rule keeps to a
        // single link per person.
        let peopleLinks = peopleLinks(in: body, knownPeople: knownPeople)
        y.append(peopleLinks.isEmpty ? "people:"
                 : "people: " + peopleLinks.map { "[[\($0)]]" }.joined(separator: ", "))
        if profile.keepsSensorFrontmatter {
            y.append(input.significance != nil ? "significance: \(String(format: "%.1f", input.significance!))" : "significance:")
        }

        // ── where you were ──
        if let place = meta?.location?.placeName, !place.isEmpty {
            y.append("location: \"\(place)\"")
        } else {
            y.append("location:")
        }
        // The sensor block is personal-notes furniture — weather and step counts have nothing
        // to say in a portfolio entry. `location:` above deliberately stays in BOTH: "do I care
        // where I took a thing? Sure" (Tuur, 2026-08-26).
        if profile.keepsSensorFrontmatter {
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
        }

        // ── Skrift's bookkeeping, last ──
        // `VaultStamp.apply` fills this in place and appends skriftID + skriftHash after
        // it, so the three land together at the bottom.
        y.append("lastTouched:")
        y.append("---")
        y.append("")

        let frontmatter = y.joined(separator: "\n") + "\n"

        // Captures pin the shared-content block ABOVE the annotation body (C3 §compile).
        if input.sourceType == .capture, let sc {
            return frontmatter + captureSharedBlock(sc, body: body) + body
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
        let attribution = "> " + (CaptureQuote.attribution(book: book, author: author, chapter: chapter, style: .vault)
                                  ?? "— *\(book)*")

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

    /// Every `[[link]]` whose target is not a known PERSON becomes its plain text. Image
    /// embeds (`![[file]]`) are left alone — they are embeds, not links, and the profile's
    /// own image syntax already governs them.
    static func plainifyNonPeopleLinks(in body: String, knownPeople: [Person]?) -> String {
        let allow: Set<String>? = knownPeople.map {
            Set($0.filter { !$0.isDeleted }
                .map { NamesMerge.matchKey($0.canonical) })
        }
        var edits: [(NSRange, String)] = []
        for link in Sanitiser.bodyLinks(in: body) {
            let target = Sanitiser.linkTarget(link.core)
            guard !target.isEmpty else { continue }
            if allow?.contains(target.lowercased()) == true { continue }   // a person — keep the link
            // `[[Target|spoken]]` renders as the spoken form, so that is the text to keep.
            let shown = Sanitiser.linkDisplay(link.core) ?? target
            edits.append((link.range, shown))
        }
        return Sanitiser.nsReplace(body, edits: edits)
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
