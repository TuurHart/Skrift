import SwiftUI
import UIKit

// Shared presentation pieces for the note page: the audiobook capture-quote
// framing (with live karaoke during playback), the inline photo embed used by
// speaker turns, and the name-tier attributed styling. (Moved here from the
// retired TranscriptBodyView/TranscriptEditor when the body was re-founded on
// the scrolling NoteBodyView.)

// MARK: - Capture quote block

/// The styled C1 quote FRAMING — accent bar on the left + plain-text attribution
/// caption from the C2 book metadata ("— Author, Book · ch. N" — the `[[Author]]`
/// wikilink stays export-side). Shared by every mode so the block doesn't jump
/// when playback starts and the book's words always read as the book's.
struct CaptureQuoteFrame<Content: View>: View {
    let attribution: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            if let attribution {
                Text(attribution)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.skTextDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Color.skAccent.opacity(0.65))
                .frame(width: 3)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-quote-block")
    }
}

/// The frame with the STATIC quote text (paused / transcribing). Non-editable by
/// design: the ramble below it is the editable part.
struct CaptureQuoteBlock: View {
    let quote: String
    let attribution: String?

    var body: some View {
        CaptureQuoteFrame(attribution: attribution) {
            Text(quote)
                .font(.system(size: 15.5))
                .italic()
                .lineSpacing(4)
                .foregroundStyle(Color.skText.opacity(0.78))
        }
    }
}

/// Tap-a-word → seek target for the quote block. The quote text carries no markers, so
/// tapped word N IS sidecar word N (the quote's spoken words run from index 0, and the
/// timings are clip-relative — `QuoteCaptureProcessor` rebases the book's times by the span
/// start). Same shared seek lookup a voice-note tap uses (`Karaoke.seekTime`); a tap on
/// whitespace seeks to the word just read. nil = no timed word there.
enum QuoteWordSeek {
    static func seekTime(atChar charIndex: Int, text: String, timings: [WordTiming]) -> TimeInterval? {
        let ranges = KaraokeMap.wordRanges(in: text as NSString)
        guard let word = KaraokeMap.wordIndex(at: charIndex, in: ranges) else { return nil }
        return Karaoke.seekTime(forWord: word, in: timings)
    }
}

/// The quote text with the LIVE karaoke highlight during playback — the quote's
/// spoken words run from sidecar index 0 (the ramble's continue after, painted by
/// the editor itself). Tapping a word seeks the quote clip there (Q83), like a voice
/// note. A small view on purpose: it observes the player clock, so only THIS text
/// re-evaluates per highlight step, not the page.
struct QuoteKaraokeText: View {
    let text: String
    let timings: [WordTiming]
    @ObservedObject var player: AudioPlayerModel
    @ObservedObject var clock: PlayerClock

    var body: some View {
        let active = player.isPlaying && !timings.isEmpty ? Karaoke.activeWordIndex(timings, at: clock.time) : nil
        QuoteKaraokeTextView(text: text, active: active) { charIndex in
            guard let t = QuoteWordSeek.seekTime(atChar: charIndex, text: text, timings: timings) else { return }
            player.seek(to: t)
        }
        .accessibilityIdentifier("quote-karaoke-text")
    }
}

/// UIKit text for the quote: SwiftUI `Text` can't say which word was tapped. A
/// non-scrolling, non-selectable UITextView with one tap recognizer, sized to its width.
private struct QuoteKaraokeTextView: UIViewRepresentable {
    let text: String
    let active: Int?
    let onTap: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tv.addGestureRecognizer(tap)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.onTap = onTap
        guard context.coordinator.rendered?.text != text || context.coordinator.rendered?.active != active else { return }
        context.coordinator.rendered = (text, active)
        tv.attributedText = Self.attributed(text, active: active)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let w = proposal.width ?? UIScreen.main.bounds.width
        let h = uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
        return CGSize(width: w, height: ceil(h))
    }

    /// Same look as the old SwiftUI text: italic 15.5, line spacing 4, 78% text; words before
    /// the active one dim, the active one accent.
    static func attributed(_ text: String, active: Int?) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 4
        let base = UIFont.systemFont(ofSize: 15.5)
        let font = base.fontDescriptor.withSymbolicTraits(.traitItalic).map { UIFont(descriptor: $0, size: 15.5) } ?? base
        let out = NSMutableAttributedString(string: text, attributes: [
            .font: font, .paragraphStyle: para,
            .foregroundColor: UIColor(Color.skText.opacity(0.78)),
        ])
        guard let active else { return out }
        for (i, r) in KaraokeMap.wordRanges(in: text as NSString).enumerated() {
            if i < active { out.addAttribute(.foregroundColor, value: UIColor(Color.skTextDim), range: r) }
            else if i == active { out.addAttribute(.foregroundColor, value: UIColor(Color.skAccent), range: r) }
            else { break }
        }
        return out
    }

    final class Coordinator: NSObject {
        var onTap: (Int) -> Void = { _ in }
        var rendered: (text: String, active: Int?)?

        @objc func tapped(_ gr: UITapGestureRecognizer) {
            guard gr.state == .ended, let tv = gr.view as? UITextView else { return }
            let p = gr.location(in: tv)
            let lm = tv.layoutManager
            let inset = tv.textContainerInset
            let point = CGPoint(x: p.x - inset.left, y: p.y - inset.top)
            let idx = lm.characterIndex(for: point, in: tv.textContainer,
                                        fractionOfDistanceBetweenInsertionPoints: nil)
            onTap(idx)
        }
    }
}

// MARK: - Inline photo embed (speaker turns)

/// An inline photo from the transcript markers; placeholder if the file is gone
/// (e.g. seeded demo memos) or still downloading from iCloud.
struct ImageEmbed: View {
    let url: URL?
    // Observe CloudKit sync: when an import completes the monitor materializes
    // the photo + re-publishes, so this swaps the placeholder for the real image.
    @ObservedObject private var sync = CloudSyncMonitor.shared

    var body: some View {
        let image = url.flatMap { MemoImageLoader.thumbnail(at: $0, maxWidth: UIScreen.main.bounds.width) }
        let state = MediaSyncState.of(
            filePresent: image != nil,
            hasAsset: url.map { NotesRepository.shared.hasAsset(filename: $0.lastPathComponent) } ?? false)
        return Group {
            switch state {
            case .present:
                Image(uiImage: image!)
                    .resizable().scaledToFill()
            case .downloading:
                LinearGradient(colors: [Color(hex: 0x2b3350), Color(hex: 0x161a29)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(
                        VStack(spacing: 8) {
                            ProgressView().tint(Color.skTextFaint)
                            Text("Downloading from iCloud…")
                                .font(.caption).foregroundStyle(Color.skTextFaint)
                        })
            case .missing:
                LinearGradient(colors: [Color(hex: 0x2b3350), Color(hex: 0x161a29)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "photo").font(.title).foregroundStyle(Color.skTextFaint))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle.sk(14).stroke(Color.skBorder, lineWidth: 1))
    }
}

// MARK: - Name-tier attributed styling

/// Maps a `NameSpan.Tier` to attributed-text attributes over a token range,
/// matching the signed-off mock (`mocks/phone-name-linking.html`): LINKED solid
/// accent; SUGGESTED tan + dotted tan underline; AMBIGUOUS accent wash + dotted
/// purple underline; PLAIN (leftplain) a faint dotted underline.
enum NameTierStyle {
    private static let dotted = NSNumber(value: NSUnderlineStyle([.single, .patternDot]).rawValue)

    static func apply(_ tier: NameSpan.Tier, to storage: NSTextStorage, range: NSRange) {
        switch tier {
        case .linked:
            storage.addAttribute(.foregroundColor, value: UIColor(Color.skNameLinked), range: range)
        case .suggested:
            storage.addAttributes([
                .foregroundColor: UIColor(Color.skNameSuggest),
                .underlineStyle: dotted,
                .underlineColor: UIColor(Color.skNameSuggestLine),
            ], range: range)
        case .ambiguous:
            storage.addAttributes([
                .backgroundColor: UIColor(Color.skAccentSoft),
                .underlineStyle: dotted,
                .underlineColor: UIColor(Color.skNameAmbigLine),
            ], range: range)
        case .plain:
            storage.addAttributes([
                .underlineStyle: dotted,
                .underlineColor: UIColor(Color.skNamePlainLine),
            ], range: range)
        }
    }
}
