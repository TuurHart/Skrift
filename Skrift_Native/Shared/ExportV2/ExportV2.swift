import Foundation

/// Export compiler v2 (Q434, C2): one pure function from a note to the file both destinations
/// get — frontmatter, body with every marker turned into its embed, and the pictures it placed.
/// Beside v1 (`Compiler`) until the swap; the apps still call v1. I/O, ownership, stamps, the
/// layout of the picked folder and the ledger stay the shared writer's (`VaultWriter`,
/// `VaultStamp`, `VaultLayout.home`, `DestinationMove`): v2 decides WHAT is written, the writer
/// WHERE and WHETHER.
///
/// Rules (plan/reads/export-v2.md): C56 frontmatter (+ `created`, `duration`, D12; `editedAt`,
/// C284), the one title (C25), quoted titles and tags (R50), the portfolio key list and flat
/// YAML (C130, R51: `people:` as a block list of plain names), the portfolio's embeds `![](file)`
/// everywhere including a capture's picture (C129, R51), pictures named by the note stem (C57,
/// Q488's `ExportProfile.pictureName`), a dangling marker dropped (C196), memo-links (C59) and a
/// hand-typed `[[word]]` that resolves to nothing escaped (R49), the quote attribution (C60),
/// `date:` the recording's local day (C64), OCR text and a shared document exported (R38).
enum ExportV2 {

    /// What v2 reads about a note. `input` is the one shared `CompilerInput` both apps build
    /// (body precedence, voice, name-linking, memo-link stems: `CompilerInput.make`); the rest
    /// is what v1 never carried.
    struct Note: Sendable {
        var input: CompilerInput
        /// The C25 ladder's title — the same one the file is named by.
        var title: String
        /// He typed this title himself (C130: the portfolio writes `title:` only then).
        var heGaveTitle = false
        /// D12: when the note was made, and how long the recording runs (nil = no recording).
        var createdAt: Date? = nil
        var duration: TimeInterval? = nil
        /// The live roster: `people:` lists these, a link to one of them is kept.
        var people: [Person] = []
        var author = ""
        /// The picture manifest: the N-th entry is `[[img_NNN]]`'s file; `pictureText[N]` its OCR.
        var pictureManifest: [String] = []
        var pictureText: [Int: String] = [:]
        var attachments: [NoteAttachmentEntry] = []
        /// A `.file` capture's document as the writer will name it (R38), nil when none.
        var documentName: String? = nil
    }

    /// The compiled note: pre-stamp markdown (the writer stamps it) and what it placed.
    struct Output: Equatable, Sendable {
        var markdown: String
        var pictures: [PlacedPicture] = []
        var attachments = 0
        /// C158: manifest pictures the body no longer shows, named as an earlier export placed them.
        var removedPictures: [PlacedPicture] = []
    }

    /// Places one asset: `(source filename, preferred name) -> name written`, nil = not placed
    /// (the embed is dropped, C196). The pure default accepts every preferred name.
    typealias Place = (_ source: String, _ preferredName: String) -> String?

    static func compile(_ note: Note, profile: ExportProfile, stem: String,
                        placePicture: Place = { _, name in name },
                        placeAttachment: Place = { _, name in name },
                        poster: Place = { _, _ in nil }) -> Output {
        let body = Body.render(note, profile: profile)
        var out = Output(markdown: "")
        let pictures = convertPictures(body, note: note, profile: profile, stem: stem, place: placePicture)
        out.pictures = pictures.placed
        // A legacy capture with no markers keeps its pictures under their own names (no `<stem>_NNN`).
        if !(note.input.sourceType == .capture && !body.contains("[[img_")) {
            out.removedPictures = profile.removedPictures(body, manifest: note.pictureManifest, stem: stem)
        }
        let attached = NoteAttachment.convertMarkers(pictures.markdown, manifest: note.attachments, stem: stem,
                                                     profile: profile) { source, preferred in
            NoteAttachment.isKeptMovie(source) ? poster(source, VideoExportFrame.exportName(stem: stem))
                                               : placeAttachment(source, preferred)
        }
        out.attachments = attached.placed
        out.markdown = Frontmatter.render(note, profile: profile, body: body) + attached.markdown
        return out
    }

    /// `[[img_NNN]]` → this profile's embed of `<stem>_NNN.ext` (Q488's one naming rule, C57),
    /// dangling or unplaceable → dropped (C196). In the vault a picture's OCR text follows it as
    /// an Obsidian comment — searchable, hidden when reading (R38). Never on the portfolio: the
    /// text below the fence is his (C131).
    static func convertPictures(_ markdown: String, note: Note, profile: ExportProfile, stem: String,
                                place: Place) -> (markdown: String, placed: [PlacedPicture]) {
        let ns = markdown as NSString
        var edits: [(NSRange, String)] = []
        var placed: [PlacedPicture] = []
        for m in BodyV2Marker.regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
            guard let n = Int(ns.substring(with: m.range(at: 1))), n >= 1, n <= note.pictureManifest.count,
                  case let source = note.pictureManifest[n - 1], !source.isEmpty,
                  let name = place(source, ExportProfile.pictureName(stem: stem, number: n, source: source))
            else { edits.append((m.range, "")); continue }
            placed.append(PlacedPicture(source: source, embedName: name))
            var embed = profile.imageMarkdown(name)
            if profile == .obsidian, let text = note.pictureText[n]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                embed += "\n%% " + text.replacingOccurrences(of: "%%", with: "%") + " %%"
            }
            edits.append((m.range, embed))
        }
        return (Sanitiser.nsReplace(markdown, edits: edits), placed)
    }
}

// MARK: - Frontmatter (C56, C130)

extension ExportV2 {
    enum Frontmatter {
        static func render(_ note: Note, profile: ExportProfile, body: String) -> String {
            let input = note.input, meta = input.metadata
            let portfolio = profile == .portfolio
            var y = ["---"]
            func add(_ key: String, _ value: String?) { y.append(value.map { "\(key): \($0)" } ?? "\(key):") }
            func list(_ key: String, _ items: [String]) {
                y.append("\(key):")
                y += items.map { "  - \($0)" }
            }
            // One line, always (C130): a capture's derived title can carry its text's line breaks.
            let title = note.title.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: " ")
            if !portfolio || note.heGaveTitle { add("title", quoted(title)) }
            add("date", day(input))
            if portfolio {
                add("capture", source(input))
                add("voice", input.voice.rawValue)
                list("tags", input.tags.compactMap { tag($0, portfolio: true) })
                list("people", peopleNames(in: body, people: note.people))
                add("location", place(meta).map(quoted))
                if taggedInspiration(input.tags) { list("needs", ["credit"]) }
            } else {
                add("editedAt", input.editedAt.map { ExportNaming.localDateTime($0) })
                add("created", note.createdAt.map { ExportNaming.localDateTime($0) })
                add("duration", note.duration.flatMap { $0 > 0 ? String(Int($0.rounded())) : nil })
                add("author", note.author)
                add("source", source(input))
                if let b = trimmed(meta?.bookTitle) {
                    add("book", quoted(b))
                    if let a = trimmed(meta?.bookAuthor) { add("bookAuthor", quoted(a)) }
                    if let c = trimmed(meta?.bookChapter), trimmed(meta?.bookURL) == nil { add("chapter", quoted(c)) }
                }
                if input.sourceType == .capture, let url = trimmed(input.sharedContent?.url) { add("url", url) }
                add("summary", trimmed(input.enhancedSummary).map(quoted))
                list("tags", input.tags.compactMap { tag($0, portfolio: false) })
                let names = peopleNames(in: body, people: note.people)
                add("people", names.isEmpty ? nil : names.map { "[[\($0)]]" }.joined(separator: ", "))
                add("significance", input.significance.map { String(format: "%.1f", $0) })
                add("location", place(meta).map(quoted))
                sensors(meta, into: &y)
            }
            y += ["lastTouched:", "---", ""]
            return y.joined(separator: "\n") + "\n"
        }

        /// C64: the recording's local day; an unparseable stored string keeps its first ten characters.
        static func day(_ input: CompilerInput) -> String {
            guard let iso = input.metadata?.recordedAt ?? input.rawRecordedAt else { return "" }
            return ExportNaming.localDay(iso: iso) ?? String(iso.prefix(10))
        }

        /// `source:` (vault) / `capture:` (portfolio): where the words came from.
        static func source(_ input: CompilerInput) -> String {
            let meta = input.metadata
            if let link = input.kind?.linkExportSource { return link }
            if trimmed(meta?.bookTitle) != nil {
                if let url = trimmed(meta?.bookURL) { return url }
                return SourceKind.isPDFPageLabel(trimmed(meta?.bookChapter)) ? "PDF-quote" : "Audiobook-quote"
            }
            if input.mediaSource == "video" { return "Video" }
            if input.kind == .typedNote { return typedSource }
            switch input.sourceType {
            case .note: return "Apple-Note"
            case .audio: return "Voice-memo"
            case .capture:
                switch input.sharedContent?.type {
                case .url?: return "capture-url"
                case .text?: return "capture-text"
                case .image?: return "capture-image"
                case .file?: return "capture-file"
                case nil: return "capture"
                }
            }
        }

        /// One tag line's value, nil when nothing is left: never a leading `#` (Obsidian's own
        /// mark, and a YAML comment); a `: ` quoted in the vault (R50) and reworded on the
        /// portfolio, which never quotes (C130).
        static func tag(_ raw: String, portfolio: Bool) -> String? {
            var t = raw.trimmingCharacters(in: .whitespaces)
            while t.hasPrefix("#") { t.removeFirst() }
            t = t.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return nil }
            if portfolio { return reworded(t) }
            return t.contains(": ") || "&*!|>%@`'\"{[?-".contains(t.first!) ? quoted(t) : t
        }

        /// The DISTINCT people the body links, reading order, as plain canonical names. Only
        /// roster people count, so a place or a manual link never lands in `people:`.
        static func peopleNames(in body: String, people: [Person]) -> [String] {
            let roster = Dictionary(people.filter { !$0.isDeleted }.map { (NamesMerge.matchKey($0.canonical), $0) },
                                    uniquingKeysWith: { a, _ in a })
            var seen = Set<String>()
            return Sanitiser.bodyLinks(in: body).compactMap { link in
                let target = Sanitiser.linkTarget(link.core)
                let key = target.lowercased()
                guard roster[key] != nil, seen.insert(key).inserted else { return nil }
                return target
            }
        }

        static func sensors(_ meta: CompilerMetadata?, into y: inout [String]) {
            guard let meta else { return }
            if let w = meta.weather, let c = w.conditions, let t = w.temperature {
                y.append("weather: \"\(c), \(num(t))\(w.temperatureUnit ?? "°C")\"")
            }
            if let p = meta.pressure?.hPa { y.append("pressure: \(num(p))") }
            if let tr = trimmed(meta.pressure?.trend) { y.append("pressureTrend: \(tr)") }
            if let dp = trimmed(meta.dayPeriod) { y.append("dayPeriod: \(dp)") }
            if let d = meta.daylight, let sr = d.sunrise, let ss = d.sunset {
                y += ["daylight:", "  sunrise: \"\(sr)\"", "  sunset: \"\(ss)\""]
                if let h = d.hoursOfLight { y.append("  hoursOfLight: \(num(h))") }
            }
            if let s = meta.steps { y.append("steps: \(s)") }
        }

        static func taggedInspiration(_ tags: [String]) -> Bool {
            tags.contains {
                $0.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
                    .caseInsensitiveCompare(PortfolioTagPresets.inspiration) == .orderedSame
            }
        }

        static func place(_ meta: CompilerMetadata?) -> String? { trimmed(meta?.location?.placeName) }

        /// Double-quoted YAML scalar, `\` and `"` escaped (R50: any `: ` stays one value).
        static func quoted(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }

        /// C130: a plain portfolio value never carries `: ` — reworded, never quoted.
        static func reworded(_ s: String) -> String { s.replacingOccurrences(of: ": ", with: " - ") }

        static func num(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }

        static func trimmed(_ s: String?) -> String? {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return t
        }

        /// The `source:` of a typed note (Q142), one spelling on both apps.
        static let typedSource = "Typed-note"
    }
}

