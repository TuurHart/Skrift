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

    /// D183: the quote is editable, so the shown words may no longer be the sidecar's. The
    /// same lookup through the shared `QuoteKaraokeMap` — nil for a word that no longer lines
    /// up with the audio.
    static func seekTime(atChar charIndex: Int, text: String, map: QuoteKaraokeMap) -> TimeInterval? {
        let ranges = KaraokeMap.wordRanges(in: text as NSString)
        guard let word = KaraokeMap.wordIndex(at: charIndex, in: ranges) else { return nil }
        return map.seekTime(forWord: word)
    }
}

/// The quote text, EDITABLE like the rest of the note (D183: "it's just text, just fix it as
/// normal text") and carrying the live karaoke highlight during playback — the quote's spoken
/// words run from sidecar index 0 (the ramble's continue after, painted by the editor
/// itself). While playing it is read-only and a tap on a word seeks the quote clip there
/// (Q83), like a voice note; while paused it edits. Words an edit moved off the audio simply
/// don't light (`QuoteKaraokeMap`). A small view on purpose: it observes the player clock,
/// so only THIS text re-evaluates per highlight step, not the page.
struct CaptureQuoteText: View {
    /// The quote as shown (`> ` stripped).
    let text: String
    /// Spoken words in the note text under the quote (the sidecar split's other half).
    let rambleWordCount: Int
    let timings: [WordTiming]
    @ObservedObject var player: AudioPlayerModel
    @ObservedObject var clock: PlayerClock
    /// The edited quote text, on end-editing and ~1 s after the last keystroke.
    let onCommit: (String) -> Void

    var body: some View {
        QuoteEditTextView(text: text, rambleWordCount: rambleWordCount, timings: timings,
                          playing: player.isPlaying, time: clock.time,
                          onSeek: { player.seek(to: $0) }, onCommit: onCommit)
            .accessibilityIdentifier("quote-karaoke-text")
    }
}

/// UIKit text for the quote: SwiftUI can't say which word was tapped, nor edit with the
/// note's native mechanics. A non-scrolling UITextView sized to its width; editable unless
/// playing, one tap recognizer for the seek.
private struct QuoteEditTextView: UIViewRepresentable {
    let text: String
    let rambleWordCount: Int
    let timings: [WordTiming]
    let playing: Bool
    let time: TimeInterval
    let onSeek: (TimeInterval) -> Void
    let onCommit: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.tintColor = UIColor(Color.skAccent)
        tv.autocorrectionType = .default
        tv.typingAttributes = Self.baseAttributes
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        tv.addGestureRecognizer(tap)
        context.coordinator.textView = tv
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        let c = context.coordinator
        c.onSeek = onSeek
        c.onCommit = onCommit
        c.playing = playing
        c.shownText = text
        // The map is rebuilt only when the words or the sidecar change, never on a clock tick.
        let key = MapKey(words: QuoteKaraokeMap.words(of: text), ramble: rambleWordCount, count: timings.count)
        if c.mapKey != key {
            c.mapKey = key
            c.map = QuoteKaraokeMap(quoteWords: key.words, rambleWordCount: rambleWordCount, timings: timings)
        }
        // Playing → read-only (the tap seeks); paused → edits like the body.
        if tv.isEditable == playing {
            if playing { tv.resignFirstResponder() }
            tv.isEditable = !playing
            tv.isSelectable = !playing
        }
        // Never rewrite the storage under the user's fingers: their text is the truth until
        // end-editing commits it.
        guard !tv.isFirstResponder else { return }
        let active = playing ? c.map.activeWord(at: time) : nil
        guard c.rendered?.text != text || c.rendered?.active != active else { return }
        c.rendered = (text, active)
        tv.attributedText = Self.attributed(text, active: active)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let w = proposal.width ?? UIScreen.main.bounds.width
        let h = uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
        return CGSize(width: w, height: ceil(h))
    }

    struct MapKey: Equatable { let words: [String]; let ramble: Int; let count: Int }

    static var baseAttributes: [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 4
        let base = UIFont.systemFont(ofSize: 15.5)
        let font = base.fontDescriptor.withSymbolicTraits(.traitItalic).map { UIFont(descriptor: $0, size: 15.5) } ?? base
        return [.font: font, .paragraphStyle: para, .foregroundColor: UIColor(Color.skText.opacity(0.78))]
    }

    /// Same look as the old read-only quote: italic 15.5, line spacing 4, 78% text; words
    /// before the active one dim, the active one accent. `active == word count` = all read.
    static func attributed(_ text: String, active: Int?) -> NSAttributedString {
        let out = NSMutableAttributedString(string: text, attributes: baseAttributes)
        guard let active else { return out }
        for (i, r) in KaraokeMap.wordRanges(in: text as NSString).enumerated() {
            if i < active { out.addAttribute(.foregroundColor, value: UIColor(Color.skTextDim), range: r) }
            else if i == active { out.addAttribute(.foregroundColor, value: UIColor(Color.skAccent), range: r) }
            else { break }
        }
        return out
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        weak var textView: UITextView?
        var onSeek: (TimeInterval) -> Void = { _ in }
        var onCommit: (String) -> Void = { _ in }
        var playing = false
        var shownText = ""
        var mapKey: MapKey?
        var map = QuoteKaraokeMap(quoteWords: [], rambleWordCount: 0, timings: [])
        var rendered: (text: String, active: Int?)?
        private var commitTask: Task<Void, Never>?

        func textViewDidChange(_ tv: UITextView) {
            commitTask?.cancel()
            commitTask = Task { @MainActor [weak self, weak tv] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, let tv else { return }
                // A quote cleared to nothing waits for end-editing: committing it would drop
                // the block (and this view) mid-typing.
                guard !tv.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                self.onCommit(tv.text)
            }
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            commitTask?.cancel()
            commitTask = nil
            // Next turn: ending an edit because playback began happens inside a view update.
            let text = tv.text ?? ""
            if text != shownText { DispatchQueue.main.async { [weak self] in self?.onCommit(text) } }
            rendered = nil   // re-render from the stored text on the next update
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc func tapped(_ gr: UITapGestureRecognizer) {
            guard gr.state == .ended, playing, let tv = gr.view as? UITextView else { return }
            let p = gr.location(in: tv)
            let inset = tv.textContainerInset
            let point = CGPoint(x: p.x - inset.left, y: p.y - inset.top)
            let idx = tv.layoutManager.characterIndex(for: point, in: tv.textContainer,
                                                     fractionOfDistanceBetweenInsertionPoints: nil)
            guard let t = QuoteWordSeek.seekTime(atChar: idx, text: tv.text, map: map) else { return }
            onSeek(t)
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
