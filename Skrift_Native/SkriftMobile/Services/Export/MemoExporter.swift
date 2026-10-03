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
        let input = compilerInput(for: memo, people: people, enhancement: enhancement,
                                  linkStems: linkStems)
        return Compiler.compile(input, author: author, date: MemoDate.isUnknown(memo.recordedAt) ? "" : dateString(memo.recordedAt),
                                knownPeople: people, profile: profile)
    }

    // MARK: - Memo → CompilerInput

    /// Map a `Memo` into the neutral `CompilerInput` through the ONE shared builder
    /// (`CompilerInput.make`, the Mac's too): body = the Mac's copy-edit when it has words, else
    /// the raw transcript / annotation, name-linked on-device with the note's own unlink / pick
    /// decisions (R37); `voice:` is `cleaned` only when that copy-edit is the body (Q155).
    static func compilerInput(for memo: Memo, people: [Person], enhancement: MemoEnhancement? = nil,
                              linkStems: [UUID: String] = [:]) -> CompilerInput {
        let capture = memo.isShareCapture
        let enh = (enhancement?.hasContent == true) ? enhancement : nil
        let raw = capture ? memo.annotationText : memo.transcript
        let meta = memo.metadata
        return CompilerInput.make(
            filename: "memo",                                  // unused: the title is always set
            raw: (raw ?? "").isEmpty ? nil : raw,
            copyedit: enh?.copyedit,
            people: people,
            resolutions: memo.nameResolutions,
            // The same C25 ladder that names the file (and that the Mac uses), so the
            // frontmatter title and the filename can no longer disagree.
            title: exportTitle(for: memo, people: people, enhancement: enhancement),
            summary: nonEmpty(enh?.summary),
            tags: memo.tags,
            significance: memo.significance,
            sourceType: capture ? .capture : .audio,
            mediaSource: (meta?.sourceType == MemoMetadata.Source.video) ? "video" : nil,
            metadata: meta.map(compilerMetadata),
            sharedContent: capture ? memo.sharedContent : nil,
            rawRecordedAt: nil,
            destination: memo.destination,
            spoken: !memo.audioFilename.isEmpty,
            kind: SourceKind.of(memo),                     // typed → `Typed-note` (Q142)
            linkStems: linkStems)
    }

    // MARK: - Title / body helpers

    /// The export title — the shared C25 ladder (`ExportNaming.title`, the Mac's rule too):
    /// user title → the Mac's suggested title (`enhancement.title`) → first body line →
    /// share title → "Note"/"Voice note". Always non-empty so the Compiler never falls back
    /// to the (synthetic) filename stem. `people` is kept for call-site stability: linking
    /// only wraps spoken words, so the plain first line is the same with or without it.
    static func exportTitle(for memo: Memo, people: [Person],
                            enhancement: MemoEnhancement? = nil) -> String {
        ExportNaming.title(for: memo, enhancement: enhancement)
    }

    /// The on-device name-linked body (transcript for audio, annotation for a share-capture).
    static func linkedBody(for memo: Memo, people: [Person]) -> String {
        let raw = memo.isShareCapture ? (memo.annotationText ?? "") : (memo.transcript ?? "")
        return CompilerInput.linkBody(raw, people: people, resolutions: memo.nameResolutions)
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

    // MARK: - Small helpers

    private static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// `date:` — the recording's local day, the ONE rule the Mac uses too (C64).
    static func dateString(_ date: Date) -> String { ExportNaming.localDay(date) }
}
