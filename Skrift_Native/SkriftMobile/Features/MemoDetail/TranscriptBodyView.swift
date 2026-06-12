import SwiftUI

/// The memo-detail transcript body — ONE component with three explicit modes,
/// replacing the stacked special cases that grew around audiobook captures
/// (whole-text karaoke → styled quote block → empty-ramble patch):
///
/// - **editing** — paused (the default). Ordinary memo: the whole transcript in
///   the always-editable `TranscriptEditor`. Capture: the styled quote block
///   (accent bar + attribution) above the quote-protected ramble editor — the
///   stored "> " lines never enter the editor (`CaptureQuote` write-back).
/// - **playing** — the classic full-text karaoke over the WHOLE memo. A capture
///   renders quote + ramble as one continuous text (`Memo.karaokeText`, "> "
///   markers stripped) so the highlight runs straight through both: the timings
///   sidecar holds the quote's words from index 0 and the ramble's after
///   (`appendRecording` shifts them), lining up 1:1 with the displayed words.
/// - **reading** — read-only (transcription in flight): status pill + static
///   text; a capture keeps its styled quote. No editor on purpose — an
///   in-flight append could otherwise be clobbered by a stale draft.
struct TranscriptBodyView: View {
    let memo: Memo
    @ObservedObject var player: AudioPlayerModel
    var onCommit: () -> Void

    enum Mode: Equatable { case editing, playing, reading }

    /// Mode is DERIVED, in one place: playback always wins (full-text karaoke),
    /// then an in-flight transcription is read-only, else the editable default.
    /// Static + pure so tests can pin the precedence.
    static func mode(isPlaying: Bool, status: TranscriptStatus) -> Mode {
        if isPlaying { return .playing }
        if status == .transcribing { return .reading }
        return .editing
    }

    private var mode: Mode { Self.mode(isPlaying: player.isPlaying, status: memo.transcriptStatus) }

    var body: some View {
        switch mode {
        case .playing: playingBody
        case .reading: readingBody
        case .editing: editingBody
        }
    }

    // MARK: - Playing (full-text karaoke)

    @ViewBuilder private var playingBody: some View {
        if let text = memo.karaokeText, !text.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if memo.transcriptStatus == .transcribing {
                    StatusPill(style: .working, label: "Transcribing")
                }
                KaraokeTranscriptView(memo: memo, player: player, text: text)
            }
        } else if memo.transcriptStatus == .failed {
            transcriptionFailedMessage
        }
    }

    // MARK: - Reading (transcription in flight — read-only)

    @ViewBuilder private var readingBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let quote = memo.captureQuote {
                CaptureQuoteBlock(quote: quote.displayText, attribution: memo.quoteAttributionLabel)
                VStack(alignment: .leading, spacing: 12) {
                    StatusPill(style: .working, label: "Transcribing")
                    if !quote.ramble.isEmpty {
                        KaraokeTranscriptView(memo: memo, player: player, text: quote.ramble)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    StatusPill(style: .working, label: "Transcribing")
                    if let text = memo.transcript, !text.isEmpty {
                        KaraokeTranscriptView(memo: memo, player: player, text: text)
                    }
                }
            }
        }
    }

    // MARK: - Editing (paused — always editable in place)

    @ViewBuilder private var editingBody: some View {
        if let quote = memo.captureQuote {
            VStack(alignment: .leading, spacing: 18) {
                CaptureQuoteBlock(quote: quote.displayText, attribution: memo.quoteAttributionLabel)
                TranscriptEditor(memo: memo, onCommit: onCommit)
            }
        } else {
            TranscriptEditor(memo: memo, onCommit: onCommit)
        }
    }

    private var transcriptionFailedMessage: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatusPill(style: .error, label: "Transcription failed", systemImage: "exclamationmark.triangle.fill")
            Text("It'll be transcribed on your Mac when you sync — or pause and type it yourself.")
                .font(.footnote).foregroundStyle(Color.skTextDim)
        }
    }
}

// MARK: - Karaoke transcript (read-only text + inline image markers)

/// Read-only transcript text with the karaoke highlight: the active spoken
/// word accents, played words dim, upcoming stay default. `text` is rendered
/// as-is (with `[[img_NNN]]` markers becoming inline photos); word indices
/// count from 0 across all text segments, matching the memo's timings sidecar.
/// When playback is paused (reading mode) it renders as plain static text.
private struct KaraokeTranscriptView: View {
    let memo: Memo
    @ObservedObject var player: AudioPlayerModel
    let text: String
    @State private var timings: [WordTiming] = []
    @AppStorage("karaokeTapToSeek") private var tapToSeek = false

    /// Active spoken-word index during playback (nil when paused / no timings) —
    /// the transcript highlights that word. Word-accurate via the on-device timings.
    private var activeWord: Int? {
        guard player.isPlaying, !timings.isEmpty else { return nil }
        return Karaoke.activeWordIndex(timings, at: player.currentTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let active = activeWord
            ForEach(Array(segmentsWithOffsets.enumerated()), id: \.offset) { _, item in
                switch item.seg {
                case .text(let s):
                    if tapToSeek && player.isPlaying {
                        karaokeWords(s, wordOffset: item.wordOffset, active: active)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        karaokeText(s, wordOffset: item.wordOffset, active: active)
                            .font(.system(size: 15.5))
                            .lineSpacing(4)
                            .foregroundStyle(Color.skText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .image(let n):
                    ImageEmbed(url: memo.imageURL(markerIndex: n))
                }
            }
        }
        .task(id: memo.id) { timings = WordTimingsStore().load(for: memo.id) ?? [] }
    }

    /// Each segment paired with the count of spoken words before it, so karaoke maps
    /// the global active-word index into the right segment (image markers aren't words).
    private var segmentsWithOffsets: [(seg: Segment, wordOffset: Int)] {
        var offset = 0
        var out: [(seg: Segment, wordOffset: Int)] = []
        for seg in segments {
            out.append((seg: seg, wordOffset: offset))
            if case .text(let s) = seg { offset += s.split(whereSeparator: { $0.isWhitespace }).count }
        }
        return out
    }

    /// Render a text segment, highlighting the active word (accent + colour) via an
    /// AttributedString. The word index advances per whitespace-delimited run so it
    /// aligns with the on-device word timings; whitespace/newlines are preserved.
    private func karaokeText(_ text: String, wordOffset: Int, active: Int?) -> Text {
        guard let active else { return Text(text) }   // not playing → plain text
        var attr = AttributedString()
        var wordIndex = wordOffset
        var buffer = ""
        func flush() {
            guard !buffer.isEmpty else { return }
            var piece = AttributedString(buffer)
            // Played words dim, the current word accents, upcoming stay default — so a
            // glance shows where playback is (matches desktop). NO weight change: bold
            // widened the word and made the next one jump, so colour only.
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
        return Text(attr)
    }

    /// Tap-to-seek mode: each word is its own tappable view (a flowing wrap), so a
    /// tap jumps playback to that word. Same grey-out colouring. Opt-in (Settings)
    /// since per-word views lose exact paragraph spacing vs the AttributedString.
    @ViewBuilder private func karaokeWords(_ text: String, wordOffset: Int, active: Int?) -> some View {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        FlowLayout(spacing: 5, lineSpacing: 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                let gi = wordOffset + i
                Text(word)
                    .font(.system(size: 15.5))
                    .foregroundStyle(active.map { gi < $0 ? Color.skTextDim : (gi == $0 ? Color.skAccent : Color.skText) } ?? Color.skText)
                    .contentShape(Rectangle())
                    .onTapGesture { seekToWord(gi) }
            }
        }
    }

    private func seekToWord(_ i: Int) {
        guard i >= 0, i < timings.count else { return }
        player.seek(to: timings[i].start)
        if !player.isPlaying { player.play() }
    }

    private enum Segment { case text(String); case image(Int) }

    private var segments: [Segment] {
        guard !text.isEmpty else { return [] }
        var result: [Segment] = []
        let ns = text as NSString
        let regex = try? NSRegularExpression(pattern: #"\[\[img_(\d+)\]\]"#)
        var last = 0
        regex?.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            if match.range.location > last {
                let chunk = ns.substring(with: NSRange(location: last, length: match.range.location - last))
                if !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.text(chunk.trimmingCharacters(in: .whitespacesAndNewlines))) }
            }
            let num = Int(ns.substring(with: match.range(at: 1))) ?? 0
            result.append(.image(num))
            last = match.range.location + match.range.length
        }
        if last < ns.length {
            let tail = ns.substring(from: last)
            if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.text(tail.trimmingCharacters(in: .whitespacesAndNewlines))) }
        }
        return result.isEmpty ? [.text(text)] : result
    }
}

// MARK: - Capture quote block

/// The styled C1 blockquote heading a capture memo's body: an accent quote bar
/// on the left, italic + slightly dimmed quote text, and a plain-text
/// attribution caption from the C2 book metadata ("— Author, Book · ch. N" —
/// the `[[Author]]` wikilink stays Mac-export-side). Non-editable by design:
/// the ramble below it is the editable part, so the quote never reads as
/// "recorded twice" plain text. Shown in the editing + reading modes; playback
/// swaps it out for the full-text karaoke.
struct CaptureQuoteBlock: View {
    let quote: String
    let attribution: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(quote)
                .font(.system(size: 15.5))
                .italic()
                .lineSpacing(4)
                .foregroundStyle(Color.skText.opacity(0.78))
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

/// An inline photo from the transcript markers; placeholder if the file is gone
/// (e.g. seeded demo memos).
struct ImageEmbed: View {
    let url: URL?

    var body: some View {
        Group {
            if let url, let image = MemoImageLoader.thumbnail(at: url, maxWidth: UIScreen.main.bounds.width) {
                Image(uiImage: image)
                    .resizable().scaledToFill()
            } else {
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
