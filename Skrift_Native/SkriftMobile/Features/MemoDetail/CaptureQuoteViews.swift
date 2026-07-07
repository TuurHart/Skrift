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

/// The quote text with the LIVE karaoke highlight during playback — the quote's
/// spoken words run from sidecar index 0 (the ramble's continue after, painted by
/// the editor itself). A small view on purpose: it observes the player clock, so
/// only THIS text re-evaluates per highlight step, not the page.
struct QuoteKaraokeText: View {
    let text: String
    let timings: [WordTiming]
    @ObservedObject var player: AudioPlayerModel
    @ObservedObject var clock: PlayerClock

    var body: some View {
        Text(karaoke(at: clock.time))
            .font(.system(size: 15.5))
            .italic()
            .lineSpacing(4)
            .foregroundStyle(Color.skText.opacity(0.78))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func karaoke(at t: TimeInterval) -> AttributedString {
        guard player.isPlaying, !timings.isEmpty,
              let active = Karaoke.activeWordIndex(timings, at: t) else { return AttributedString(text) }
        var attr = AttributedString()
        var wordIndex = 0
        var buffer = ""
        func flush() {
            guard !buffer.isEmpty else { return }
            var piece = AttributedString(buffer)
            if wordIndex < active { piece.foregroundColor = .skTextDim }
            else if wordIndex == active { piece.foregroundColor = .skAccent }
            attr += piece
            wordIndex += 1
            buffer = ""
        }
        for ch in text {
            if ch.isWhitespace { flush(); attr += AttributedString(String(ch)) }
            else { buffer.append(ch) }
        }
        flush()
        return attr
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
