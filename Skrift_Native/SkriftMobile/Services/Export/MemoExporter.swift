import Foundation

/// Exports a `Memo` to Obsidian markdown so a phone-only note can leave the device (standalone
/// Phase 2). Reuses the shared `Compiler` (via the neutral `CompilerInput`) + on-device
/// `MemoLinking`, so the phone's markdown matches what the Mac would produce for the same
/// memo (no drift). Plain text, PDF and quote-card export were removed 2026-09-30 (Q80, D154).
///
/// `author` is the note's author (the user). The phone has no "your name" setting yet — that's
/// a Phase-3 Settings field; until then callers pass "" and the frontmatter `author:` is blank.
enum MemoExporter {

    // MARK: - Markdown (Obsidian)

    /// Full Obsidian markdown (YAML frontmatter + name-linked body) via the shared `Compiler`.
    /// `enhancement` (the Mac's CloudKit write-back) is preferred when present — a paired Mac
    /// auto-upgrades the export; nil = on-device raw + linking.
    static func markdown(for memo: Memo, people: [Person], author: String = "",
                         enhancement: MemoEnhancement? = nil,
                         linkStems: [UUID: String] = [:],
                         profile: ExportProfile = .obsidian) -> String {
        var input = compilerInput(for: memo, people: people, enhancement: enhancement)
        if !linkStems.isEmpty {
            input.memoLinkResolver = { linkStems[$0] }   // value capture — Sendable
        }
        return Compiler.compile(input, author: author, date: dateString(memo.recordedAt),
                                knownPeople: people, profile: profile)
    }

    // MARK: - Memo → CompilerInput

    /// Map a `Memo` into the neutral `CompilerInput` the shared `Compiler` consumes — the phone
    /// analogue of the desktop `PipelineFile.compilerInput`. The body is the on-device
    /// name-LINKED transcript (or annotation, for a share-capture), placed in `sanitised` so it
    /// wins the Compiler's body precedence; `transcript` keeps the RAW as the fallback.
    static func compilerInput(for memo: Memo, people: [Person], enhancement: MemoEnhancement? = nil) -> CompilerInput {
        let capture = memo.isShareCapture
        let enh = (enhancement?.hasContent == true) ? enhancement : nil
        // Body: prefer the Mac's polished copy-edit; else the raw transcript/annotation. Either
        // way it's re-linked on-device (no drift) and placed in `sanitised` so it wins the
        // Compiler's body precedence; `transcript` keeps the base text as the fallback.
        let baseBody: String = {
            if let c = enh?.copyedit, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return c }
            return capture ? (memo.annotationText ?? "") : (memo.transcript ?? "")
        }()
        let linked = MemoLinking.linkedTranscript(baseBody, people: people)
        let meta = memo.metadata
        return CompilerInput(
            filename: "memo",                                  // unused: enhancedTitle is always set
            transcript: baseBody.isEmpty ? nil : baseBody,
            sanitised: linked.isEmpty ? nil : linked,
            enhancedTitle: nonEmpty(enh?.title) ?? exportTitle(for: memo, people: people),
            enhancedSummary: nonEmpty(enh?.summary),
            tags: memo.tags,
            significance: memo.significance,
            sourceType: capture ? .capture : .audio,
            mediaSource: (meta?.sourceType == MemoMetadata.Source.video) ? "video" : nil,
            metadata: meta.map(compilerMetadata),
            sharedContent: capture ? memo.sharedContent.map(compilerShared) : nil,
            rawRecordedAt: nil,
            destination: memo.destination,
            // Said here, not guessed in the Compiler: the phone carries its polished body in
            // `sanitised` (re-linked on-device), so the Compiler cannot tell cleaned from raw.
            voice: memo.audioFilename.isEmpty ? .written : (enh != nil ? .cleaned : .raw)
        )
    }

    // MARK: - Title / body helpers

    /// The export title: the user's title if set, else the first non-empty line of the linked
    /// body (flattened, truncated), else a placeholder. Always non-empty so the Compiler never
    /// falls back to the (synthetic) filename stem.
    static func exportTitle(for memo: Memo, people: [Person]) -> String {
        if let t = nonEmpty(memo.title) { return t }
        let body = flattenLinks(linkedBody(for: memo, people: people))
        if let first = body.components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty }) {
            return String(first.prefix(80))
        }
        return "Untitled Memo"
    }

    /// The on-device name-linked body (transcript for audio, annotation for a share-capture).
    static func linkedBody(for memo: Memo, people: [Person]) -> String {
        let raw = memo.isShareCapture ? (memo.annotationText ?? "") : (memo.transcript ?? "")
        return MemoLinking.linkedTranscript(raw, people: people)
    }

    /// Flatten `[[Canonical|spoken]]` → "spoken", `[[Name]]` → "Name", and drop `[[img_NNN]]`
    /// markers — for plain-text / PDF / card surfaces that shouldn't show wiki syntax.
    static func flattenLinks(_ text: String) -> String {
        guard !text.isEmpty,
              let re = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else { return text }
        let ns = NSMutableString(string: text)
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let inner = ns.substring(with: m.range(at: 1))
            let replacement: String
            if inner.hasPrefix("img_") {
                replacement = ""
            } else if let pipe = inner.range(of: "|") {
                replacement = String(inner[pipe.upperBound...])
            } else {
                replacement = inner
            }
            ns.replaceCharacters(in: m.range, with: replacement)
        }
        return ns as String
    }

    // MARK: - Metadata mapping

    static func compilerMetadata(_ m: MemoMetadata) -> CompilerMetadata {
        CompilerMetadata(
            location: m.location.flatMap { loc in loc.placeName.map { CompilerMetadata.Location(placeName: $0) } },
            weather: m.weather.map { CompilerMetadata.Weather(conditions: $0.conditions, temperature: Double($0.temperature), temperatureUnit: $0.temperatureUnit) },
            pressure: m.pressure.map { CompilerMetadata.Pressure(hPa: Double($0.hPa), trend: $0.trend.rawValue) },
            dayPeriod: m.dayPeriod?.rawValue,
            daylight: m.daylight.map { CompilerMetadata.Daylight(sunrise: $0.sunrise, sunset: $0.sunset, hoursOfLight: $0.hoursOfLight) },
            steps: m.steps,
            recordedAt: nil,                                   // date supplied via the `date:` override
            bookTitle: m.bookTitle, bookAuthor: m.bookAuthor, bookChapter: m.bookChapter
        )
    }

    static func compilerShared(_ sc: SharedContent) -> CompilerSharedContent {
        CompilerSharedContent(type: sc.type.rawValue, url: sc.url, urlTitle: sc.urlTitle,
                              text: sc.text, fileName: sc.fileName)
    }

    // MARK: - Small helpers

    private static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dateString(_ date: Date) -> String { dateFormatter.string(from: date) }
}
