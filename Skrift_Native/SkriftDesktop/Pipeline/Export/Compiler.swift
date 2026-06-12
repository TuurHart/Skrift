import Foundation

/// Phone-sent metadata, decoded from `PipelineFile.audioMetadataJSON` (the phone's
/// MemoMetadata shape) for the export frontmatter. All optional / lenient.
struct PhoneMetadata: Codable, Sendable {
    struct Location: Codable, Sendable { var placeName: String? }
    struct Weather: Codable, Sendable { var conditions: String?; var temperature: Double?; var temperatureUnit: String? }
    struct Pressure: Codable, Sendable { var hPa: Double?; var trend: String? }
    struct Daylight: Codable, Sendable { var sunrise: String?; var sunset: String?; var hoursOfLight: Double? }
    var location: Location?
    var weather: Weather?
    var pressure: Pressure?
    var dayPeriod: String?
    var daylight: Daylight?
    var steps: Int?
    var recordedAt: String?
    // Audiobook quote-capture (contract C2) — additive optional fields riding the
    // existing metadata JSON. Absent on every non-capture memo and on uploads from
    // older phone builds (synthesized Codable = decodeIfPresent / encodeIfPresent),
    // so the contract stays byte-compatible in both directions.
    var bookTitle: String?
    var bookAuthor: String?
    var bookChapter: String?
}

/// The `sharedContent` object from `PipelineFile.audioMetadataJSON` for C3 captures.
/// Mirrors mobile's `SharedContent` Codable — field names are intentionally identical.
/// Decoded on-demand (not stored on PipelineFile — avoids the SwiftData Codable trap).
struct SharedContent: Codable, Sendable {
    var type: String          // "url" | "text" | "image" | "file"
    var url: String?          // url captures
    var urlTitle: String?     // url captures (from share payload, no network fetch)
    var urlDescription: String?
    var text: String?         // text captures (the quoted snippet)
    var fileName: String?     // image captures (the image part's filename)
    var mimeType: String?     // image captures

    /// Decode from the raw metadata JSON blob.
    static func decode(from metadataJSON: Data?) -> SharedContent? {
        guard let data = metadataJSON else { return nil }
        // Try Codable first (standard JSON keys), then fall back to manual extraction
        // (the demo seeds use a raw dict with snake_case `shared_content` key).
        if let wrapper = try? JSONDecoder().decode(_Wrapper.self, from: data) { return wrapper.sharedContent }
        if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let sc = (obj["sharedContent"] ?? obj["shared_content"]) as? [String: Any] {
            return SharedContent(
                type: sc["type"] as? String ?? "",
                url: sc["url"] as? String,
                urlTitle: sc["urlTitle"] as? String,
                urlDescription: sc["urlDescription"] as? String,
                text: sc["text"] as? String,
                fileName: sc["fileName"] as? String,
                mimeType: sc["mimeType"] as? String
            )
        }
        return nil
    }

    private struct _Wrapper: Codable { var sharedContent: SharedContent? }
}

/// Assembles Obsidian-ready markdown (YAML frontmatter + body) from a PipelineFile.
/// Pure (no IO) → host-testable. Ported from `enhancement.py:compile_file`. Body
/// precedence: sanitised → enhanced copy-edit → transcript (the name-linked text
/// wins, since it's what exports). The vault write/copy is the Export step (Phase 8).
enum Compiler {
    static func compile(file pf: PipelineFile, author: String, date overrideDate: String? = nil) -> String {
        let meta = pf.audioMetadataJSON.flatMap { try? JSONDecoder().decode(PhoneMetadata.self, from: $0) }
        let body = firstNonEmpty(pf.sanitised, pf.enhancedCopyedit, pf.transcript) ?? ""
        let summary = (pf.enhancedSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawStem = (pf.filename as NSString).deletingPathExtension
        let title = firstNonEmpty(pf.enhancedTitle, rawStem) ?? rawStem
        let date = overrideDate ?? meta?.recordedAt.map { String($0.prefix(10)) } ?? ""

        // Audiobook quote-capture (spec 7): the presence of a book title marks the
        // memo as a capture from an actively-mined audiobook.
        let bookTitle = trimmedNonEmpty(meta?.bookTitle)
        let bookAuthor = trimmedNonEmpty(meta?.bookAuthor)
        let bookChapter = trimmedNonEmpty(meta?.bookChapter)

        let source: String
        if bookTitle != nil {
            source = "Audiobook-quote"
        } else {
            switch pf.sourceType {
            case .note: source = "Apple-Note"
            case .capture: source = "Capture"
            case .audio: source = "Voice-memo"
            }
        }

        var y: [String] = [
            "---",
            "title: \(title)",
            "date: \(date)",
            "lastTouched:",
            "author: \(author)",
            "source: \(source)",
        ]
        // Book frontmatter (C2 → spec 7). `bookAuthor:` not `author:` — that key is
        // the note's author (the user) above. Values quoted: titles carry colons.
        if let bookTitle { y.append("book: \"\(bookTitle)\"") }
        if let bookAuthor { y.append("bookAuthor: \"\(bookAuthor)\"") }
        if let bookChapter { y.append("chapter: \"\(bookChapter)\"") }
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
        for t in pf.tags { y.append("  - \(t)") }
        y.append(pf.significance != nil ? "significance: \(String(format: "%.1f", pf.significance!))" : "significance:")
        y.append(summary.isEmpty ? "summary:" : "summary: \(summary)")
        y.append("---")
        y.append("")

        let renderedBody = bookTitle.map {
            audiobookBody(body, book: $0, author: bookAuthor, chapter: bookChapter)
        } ?? body
        return y.joined(separator: "\n") + "\n" + renderedBody
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
