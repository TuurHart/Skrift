import Foundation

// MARK: - Body (C56, C59, C60, C129, C196, R38)

extension ExportV2 {
    enum Body {
        /// The body below the fence, markers still in it (`compile` turns them into embeds).
        static func render(_ note: Note, profile: ExportProfile) -> String {
            let input = note.input, meta = input.metadata
            // C196: sanitised → copy-edit → transcript.
            var body = [input.sanitised, input.enhancedCopyedit, input.transcript]
                .compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
            if profile == .portfolio {
                // The portfolio keeps PEOPLE links and plainifies every other one (C62, C137).
                body = keepingOnlyPeople(MemoLinkSyntax.exportRewrite(body, resolveStem: input.memoLinkResolver),
                                         people: note.people)
            } else {
                // Memo-links leave as `[[stem|Title]]` (C59); any other `[[word]]` stays a link (D216).
                body = MemoLinkSyntax.exportRewrite(body, resolveStem: input.memoLinkResolver)
            }
            // A body stored before body v2 reads as it shows (Q13); a v2 body passes unchanged (C65).
            body = BodyV2Legacy.shown(body).text

            if input.sourceType == .capture, let sc = input.sharedContent {
                return captureBlock(sc, body: body, profile: profile, document: note.documentName,
                                    pictures: note.pictureManifest.count) + body
            }
            guard let book = Frontmatter.trimmed(meta?.bookTitle) else { return body }
            let author = Frontmatter.trimmed(meta?.bookAuthor), chapter = Frontmatter.trimmed(meta?.bookChapter)
            if let kind = input.kind, kind.isSourceLink {
                let line = sourceLine(kind: kind, title: book, author: author, chapter: chapter,
                                      position: meta?.bookPosition)
                let words = body.trimmingCharacters(in: .whitespacesAndNewlines)
                return words.isEmpty ? line + "\n" : line + "\n\n" + body
            }
            return quoted(body, book: book, author: author, chapter: chapter, url: Frontmatter.trimmed(meta?.bookURL))
        }

        /// Every link whose target is not a roster person becomes the text it shows. A video or
        /// file marker (`[[vid_NNN]]`, `[[file_NNN]]`) is no link: it stays for its embed (C63, D199).
        static func keepingOnlyPeople(_ body: String, people: [Person]) -> String {
            let roster = rosterKeys(people)
            let edits: [(NSRange, String)] = Sanitiser.bodyLinks(in: body).compactMap { link in
                let target = Sanitiser.linkTarget(link.core)
                guard !target.isEmpty, !roster.contains(target.lowercased()),
                      link.core.range(of: #"^(vid|file)_\d+$"#, options: .regularExpression) == nil else { return nil }
                return (link.range, Sanitiser.linkDisplay(link.core) ?? target)
            }
            return Sanitiser.nsReplace(body, edits: edits)
        }

        static func rosterKeys(_ people: [Person]) -> Set<String> {
            Set(people.filter { !$0.isDeleted }.map { NamesMerge.matchKey($0.canonical) })
        }

        /// A capture's shared content, pinned above his words: a link's title and address, a
        /// shared text as a quote, a shared picture (when the body places none) and a shared
        /// document (R38), both in this profile's embed (C129, R51).
        /// Q518 (C57): a shared picture leaves as its manifest's markers, so `convertPictures` names
        /// and places it like any other (`<stem>_001.jpg`, dropped when missing, C196). The shared
        /// file's own name is embedded only for a capture with no manifest.
        static func captureBlock(_ sc: SharedContent, body: String, profile: ExportProfile, document: String?,
                                 pictures: Int = 0) -> String {
            var lines: [String] = []
            switch sc.type {
            case .url:
                if let t = Frontmatter.trimmed(sc.urlTitle) { lines.append("**\(t)**") }
                if let u = Frontmatter.trimmed(sc.url) { lines.append(u) }
            case .text:
                if let t = sc.text, !t.isEmpty { lines.append(t.components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n")) }
            case .image:
                guard !body.contains("[[img_") else { break }
                if pictures > 0 { lines.append(BodyV2Marker.block(Array(1...pictures))) }
                else if let name = Frontmatter.trimmed(sc.fileName) { lines.append(profile.imageMarkdown(name)) }
            case .file:
                // A PDF shows in place; any other document is a link to the file beside it (R38).
                if let document {
                    lines.append(document.lowercased().hasSuffix(".pdf") ? profile.imageMarkdown(document)
                                 : profile == .portfolio ? "[\(document)](\(document))" : "[[\(document)]]")
                }
            }
            return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        }

        /// C60: the captured quote in italics with `— [[Author]], *Book*, ch. N` under it (a
        /// named chapter as-is); a Library article's place is its site, linked.
        static func quoted(_ body: String, book: String, author: String?, chapter: String?, url: String?) -> String {
            guard let split = QuoteProtection.splitLeadingQuote(body) else { return body }
            let lines = split.quote.components(separatedBy: "\n").compactMap { line -> String? in
                let marker = CaptureQuote.markerLength(ofLine: line)
                guard marker > 0 || !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                let text = (line as NSString).substring(from: marker).trimmingCharacters(in: .whitespaces)
                if text.isEmpty { return ">" }
                return text.count > 1 && text.hasPrefix("*") && text.hasSuffix("*") ? "> \(text)" : "> *\(text)*"
            }
            let attribution: String
            if let url {
                let site = Frontmatter.trimmed(chapter) ?? URL(string: url)?.host ?? url
                attribution = "> — *\(book)*, [\(site)](\(url))"
            } else {
                attribution = "> " + (CaptureQuote.attribution(book: book, author: author, chapter: chapter, style: .vault)
                                      ?? "— *\(book)*")
            }
            let block = lines.joined(separator: "\n") + "\n>\n" + attribution
            return split.ramble.isEmpty ? block : block + "\n\n" + split.ramble
        }

        /// A source-link note's one line (D138): PDF `— *Title*, p. N`; episode
        /// `— *Show*, Episode, mm:ss`; audiobook / article the vault attribution plus the clock.
        static func sourceLine(kind: SourceKind, title: String, author: String?, chapter: String?,
                               position: Double?) -> String {
            let clock = position.flatMap { s -> String? in
                guard s.isFinite, s >= 0 else { return nil }
                let t = Int(s.rounded(.down)), h = t / 3600, m = (t % 3600) / 60, sec = t % 60
                return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
            }
            let tail = clock.map { ", \($0)" } ?? ""
            switch kind {
            case .pdfLink: return "— *\(title)*" + (chapter.map { ", \($0)" } ?? "")
            case .episodeLink: return (author.map { "— *\($0)*, \(title)" } ?? "— *\(title)*") + tail
            default:
                return (CaptureQuote.attribution(book: title, author: author, chapter: chapter, style: .vault)
                        ?? "— *\(title)*") + tail
            }
        }
    }
}
