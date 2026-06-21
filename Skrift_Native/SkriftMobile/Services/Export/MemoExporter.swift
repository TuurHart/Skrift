import Foundation
import CoreText
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

/// Exports a `Memo` to shareable artifacts so a phone-only note can leave the device as more
/// than copy-paste (standalone Phase 2). Reuses the shared `Compiler` (via the neutral
/// `CompilerInput`) + on-device `MemoLinking`, so the phone's Obsidian markdown matches what
/// the Mac would produce for the same memo (no drift).
///
/// Formats: Obsidian **Markdown**, **plain text**, **PDF**, and a shareable **quote-card**
/// image (the App-Store marketing asset, pulled from Phase 6 per the user's pick).
///
/// `author` is the note's author (the user). The phone has no "your name" setting yet — that's
/// a Phase-3 Settings field; until then callers pass "" and the frontmatter `author:` is blank.
enum MemoExporter {

    // MARK: - Markdown (Obsidian)

    /// Full Obsidian markdown (YAML frontmatter + name-linked body) via the shared `Compiler`.
    static func markdown(for memo: Memo, people: [Person], author: String = "") -> String {
        Compiler.compile(compilerInput(for: memo, people: people),
                         author: author, date: dateString(memo.recordedAt), knownPeople: people)
    }

    /// Convenience over the live on-device names DB.
    static func markdown(for memo: Memo, author: String = "") -> String {
        markdown(for: memo, people: NamesStore.shared.load().people, author: author)
    }

    // MARK: - Plain text

    /// Human-readable text — title + body with `[[Name|x]]` flattened to the spoken word and
    /// `[[img_NNN]]` markers stripped. No frontmatter. For "copy as text" / `.txt` export.
    static func plainText(for memo: Memo, people: [Person]) -> String {
        let title = exportTitle(for: memo, people: people)
        let body = flattenLinks(linkedBody(for: memo, people: people))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? title : "\(title)\n\n\(body)"
    }

    static func plainText(for memo: Memo) -> String {
        plainText(for: memo, people: NamesStore.shared.load().people)
    }

    // MARK: - Memo → CompilerInput

    /// Map a `Memo` into the neutral `CompilerInput` the shared `Compiler` consumes — the phone
    /// analogue of the desktop `PipelineFile.compilerInput`. The body is the on-device
    /// name-LINKED transcript (or annotation, for a share-capture), placed in `sanitised` so it
    /// wins the Compiler's body precedence; `transcript` keeps the RAW as the fallback.
    static func compilerInput(for memo: Memo, people: [Person]) -> CompilerInput {
        let capture = memo.isShareCapture
        let rawBody = capture ? (memo.annotationText ?? "") : (memo.transcript ?? "")
        let linked = MemoLinking.linkedTranscript(rawBody, people: people)
        let meta = memo.metadata
        return CompilerInput(
            filename: "memo",                                  // unused: enhancedTitle is always set
            transcript: rawBody.isEmpty ? nil : rawBody,
            sanitised: linked.isEmpty ? nil : linked,
            enhancedTitle: exportTitle(for: memo, people: people),
            tags: memo.tags,
            significance: memo.significance,
            sourceType: capture ? .capture : .audio,
            mediaSource: (meta?.sourceType == MemoMetadata.Source.video) ? "video" : nil,
            metadata: meta.map(compilerMetadata),
            sharedContent: capture ? memo.sharedContent.map(compilerShared) : nil,
            rawRecordedAt: nil
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

#if canImport(UIKit)
extension MemoExporter {

    // MARK: - PDF

    /// Render the memo (title + flattened body) to a paged US-Letter PDF via CoreText.
    @MainActor
    static func pdf(for memo: Memo, people: [Person]) -> Data {
        let pageW: CGFloat = 612, pageH: CGFloat = 792, margin: CGFloat = 56
        let title = exportTitle(for: memo, people: people)
        let body = flattenLinks(linkedBody(for: memo, people: people))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let para = NSMutableParagraphStyle(); para.lineSpacing = 4; para.paragraphSpacing = 8
        let attr = NSMutableAttributedString()
        attr.append(NSAttributedString(string: title + "\n\n", attributes: [
            .font: UIFont.boldSystemFont(ofSize: 22),
            .foregroundColor: UIColor.label, .paragraphStyle: para
        ]))
        if !body.isEmpty {
            attr.append(NSAttributedString(string: body, attributes: [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.label, .paragraphStyle: para
            ]))
        }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        return renderer.pdfData { ctx in
            let framesetter = CTFramesetterCreateWithAttributedString(attr)
            let total = attr.length
            var pos = 0
            let textRect = CGRect(x: margin, y: margin, width: pageW - 2 * margin, height: pageH - 2 * margin)
            while pos < total {
                ctx.beginPage()
                let cg = ctx.cgContext
                cg.textMatrix = .identity
                cg.translateBy(x: 0, y: pageH)
                cg.scaleBy(x: 1, y: -1)
                let path = CGMutablePath(); path.addRect(textRect)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: pos, length: 0), path, nil)
                CTFrameDraw(frame, cg)
                let visible = CTFrameGetVisibleStringRange(frame)
                if visible.length == 0 { break }               // guard against a non-advancing page
                pos += visible.length
            }
        }
    }

    // MARK: - Quote card (shareable image)

    /// A shareable square-ish quote card (quote + attribution on a branded gradient). For a
    /// book capture the attribution is "Author, Book"; otherwise the memo's title.
    @MainActor
    static func quoteCardImage(for memo: Memo, people: [Person]) -> UIImage? {
        let quote = flattenLinks(linkedBody(for: memo, people: people))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let attribution: String
        if let bt = nonEmpty(memo.metadata?.bookTitle) {
            attribution = [nonEmpty(memo.metadata?.bookAuthor), bt].compactMap { $0 }.joined(separator: ", ")
        } else {
            attribution = exportTitle(for: memo, people: people)
        }
        let renderer = ImageRenderer(content: QuoteCard(quote: quote, attribution: attribution))
        renderer.scale = 2
        return renderer.uiImage
    }
}

/// The shareable quote-card layout (rendered to an image via `ImageRenderer`).
private struct QuoteCard: View {
    let quote: String
    let attribution: String

    private var trimmedQuote: String {
        quote.count > 320 ? String(quote.prefix(317)) + "…" : quote
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("\u{201C}")                                   // opening quote glyph
                .font(.system(size: 120, weight: .bold, design: .serif))
                .foregroundStyle(.white.opacity(0.85))
                .frame(height: 70, alignment: .top)
            Text(trimmedQuote.isEmpty ? attribution : trimmedQuote)
                .font(.system(size: 40, weight: .medium, design: .serif))
                .foregroundStyle(.white)
                .lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                if !trimmedQuote.isEmpty {
                    Text(attribution)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Text("Skrift")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(72)
        .frame(width: 1080, height: 1080, alignment: .topLeading)
        .background(
            LinearGradient(colors: [Color(red: 0.10, green: 0.09, blue: 0.20),
                                    Color(red: 0.28, green: 0.22, blue: 0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }
}
#endif
