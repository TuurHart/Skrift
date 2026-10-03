import Foundation

/// HOW a note is written, as opposed to WHERE (`NoteDestination`). Two shapes, because the
/// two readers want opposite things:
///
/// - **`.obsidian`** — exactly today's behaviour, unchanged. The picked folder gets a
///   `Skrift/` home, notes are named after their title, media lives in `Recordings/`,
///   `Images/` and `Documents/`, and images are `![[wiki embeds]]`. That layout was signed
///   off (`mocks/vault-folder-model.html`, 2026-08-14) and it is right for a vault.
///
/// - **`.portfolio`** — flat. One markdown file per entry with its media BESIDE it sharing the
///   same basename, named by timestamp, inside a month folder, and images written as plain
///   `![](file.jpg)`. A vault-relative `![[image.png]]` is exactly what makes a note
///   un-shareable outside the vault that defines it; a relative markdown link renders in
///   Obsidian too AND survives being read by anything else. The portfolio's rule is that the
///   data has to be able to walk out whole.
///
/// The profile follows the note's destination, so nothing about the Obsidian path changes
/// when destinations are switched on.
enum ExportProfile: Sendable {
    case obsidian
    case portfolio

    static func of(_ destination: NoteDestination) -> ExportProfile {
        destination.isPortfolio ? .portfolio : .obsidian
    }

    /// Does Skrift create and own a `Skrift/` folder inside the folder you picked? The
    /// portfolio already has a home — the destination folder IS the destination.
    var ownsHomeFolder: Bool { self == .obsidian }

    /// Name the file by timestamp rather than by the note's title. A portfolio entry is
    /// identified by when it was captured; a vault note is found by its name.
    var usesTimestampNames: Bool { self == .portfolio }

    /// Media beside the note sharing its basename, rather than in `Recordings/` / `Images/`.
    /// This is the other half of "shareable": the pair travels together.
    var assetsBesideNote: Bool { self == .portfolio }

    /// `![[name]]` (Obsidian) vs `![](name)` (portable, and still rendered by Obsidian).
    var usesWikiEmbeds: Bool { self == .obsidian }

    /// Weather, pressure, day period, daylight, steps, and the importance rating —
    /// personal-notes furniture with nothing to say in a portfolio entry.
    var keepsSensorFrontmatter: Bool { self == .obsidian }

    /// PLACE wiki-links in the body (`[[Hotel Du Vin]]`). People links are kept in BOTH
    /// profiles — Tuur's call, 2026-08-26, and a deliberate reversal of my privacy advice:
    /// the portfolio becomes a public website and he wants to credit his friends by name.
    /// Places carry no such intent, and a dangling place link on a website is just a
    /// broken link, so they degrade to plain text.
    var keepsPlaceLinks: Bool { self == .obsidian }

    /// The portfolio's filename stem: `the-bench-outside-cafe-garrett`. Flat — no date folder
    /// either (Tuur, 2026-08-28: *"yes we dont need the month either"*), so an entry is
    /// `_ideas/<name>.md` exactly the way his 148 items are `Lamps/<name>/item.md`.
    ///
    /// NAME ONLY, no date (Tuur, 2026-08-28: *"I don't think we need timeframes, I think just
    /// the name is fine — because that's how the rest of my portfolio works, and all the dates
    /// are just in the metadata"*). His 148 items are named exactly this way —
    /// `voronoi-decimation-lamp`, `engagement-ring` — and `date:` is in the frontmatter.
    ///
    /// The TIMESTAMP survives as the fallback, for the one case that has no name: a thing he
    /// photographed and said nothing about. Something has to identify that file, and when it
    /// arrived is the only fact there is.
    static func entryStem(for date: Date, title: String?) -> String {
        slug(title) ?? timestampStem(for: date)
    }

    /// Title → filename slug: ASCII-folded, lowercased, hyphenated.
    ///
    /// The cap is 120, matching the vault's own rule (`VaultName.stem`) and chosen so it never
    /// bites a real title — a 42-char cap did, and produced
    /// `testing-the-functionality-of-the.md` (Tuur: *"full name is cut off"*). It exists only
    /// so a pasted monster can't become a 500-character filename, and it still cuts at a word
    /// boundary when it fires. nil when there is nothing usable left.
    static func slug(_ title: String?, maxLength: Int = 120) -> String? {
        guard let title else { return nil }
        // "Café" → "cafe": a filename that survives being copied between machines.
        let folded = title.folding(options: [.diacriticInsensitive, .widthInsensitive],
                                   locale: Locale(identifier: "en_US_POSIX")).lowercased()
        var out = ""
        for ch in folded {
            if ch.isLetter || ch.isNumber { out.append(ch) }
            else if !out.hasSuffix("-") { out.append("-") }
        }
        var slug = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.count > maxLength {
            let clipped = String(slug.prefix(maxLength))
            // Cut at the last whole word rather than mid-syllable, unless that leaves a stub.
            if let lastDash = clipped.lastIndex(of: "-"), clipped.distance(from: clipped.startIndex, to: lastDash) > 12 {
                slug = String(clipped[clipped.startIndex..<lastDash])
            } else {
                slug = clipped.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            }
        }
        return slug.isEmpty ? nil : slug
    }

    /// Just the time part: `2026-08-26-142312`. Local time on purpose — it is the
    /// moment HE captured it, and a portfolio browsed by a human should read in his day.
    static func timestampStem(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: date)
    }

    /// Render one image reference in this profile's syntax.
    func imageMarkdown(_ filename: String) -> String {
        usesWikiEmbeds ? "![[\(filename)]]" : "![](\(filename))"
    }
}

// MARK: - Picture markers (C57, C196, R51)

/// One picture an export placed: the manifest's source filename and the name the note embeds.
struct PlacedPicture: Equatable, Sendable {
    let source: String
    let embedName: String
}

extension ExportProfile {
    /// THE picture-marker converter, shared by the phone's `ObsidianPublisher` and the Mac's
    /// `VaultExporter` so both write the same note. `[[img_NNN]]` resolves through the
    /// manifest (the N-th entry's filename, the same rule as the body rendering on both apps)
    /// and becomes this profile's embed of `<stem>_NNN.<ext>` (`![[x]]` vault, `![](x)`
    /// portfolio). A marker with no manifest entry, or whose picture `place` cannot put
    /// down (missing file, failed copy), is DROPPED — never printed literally (C196).
    ///
    /// `place(source, preferredName)` returns the name actually written (the Mac may
    /// disambiguate around a foreign file, C58) or nil to drop the marker. The phone writes
    /// its blobs later through the engine, so its default accepts the preferred name.
    func convertPictureMarkers(_ markdown: String, manifest: [String], stem: String,
                               place: (_ source: String, _ preferredName: String) -> String? = { _, name in name })
        -> (markdown: String, placed: [PlacedPicture]) {
        guard let rx = try? NSRegularExpression(pattern: "\\[\\[img_(\\d{3})\\]\\]") else {
            return (markdown, [])
        }
        let ns = markdown as NSString
        var replacements: [(NSRange, String)] = []
        var placed: [PlacedPicture] = []
        for m in rx.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
            let nnn = ns.substring(with: m.range(at: 1))
            guard let n = Int(nnn), n >= 1, n <= manifest.count, !manifest[n - 1].isEmpty else {
                replacements.append((m.range, ""))   // dangling marker → drop
                continue
            }
            let source = manifest[n - 1]
            let ext = (source as NSString).pathExtension
            let preferred = "\(stem)_\(nnn).\(ext.isEmpty ? "jpg" : ext)"
            guard let written = place(source, preferred) else {
                replacements.append((m.range, ""))   // picture could not be placed → drop
                continue
            }
            placed.append(PlacedPicture(source: source, embedName: written))
            replacements.append((m.range, imageMarkdown(written)))
        }
        return (Sanitiser.nsReplace(markdown, edits: replacements), placed)
    }
}
