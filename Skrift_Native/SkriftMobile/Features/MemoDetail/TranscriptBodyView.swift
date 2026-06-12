import SwiftUI

/// The memo-detail transcript body — ONE component with three explicit modes,
/// replacing the stacked special cases that grew around audiobook captures
/// (whole-text karaoke → styled quote block → empty-ramble patch):
///
/// - **editing** — paused (the default). Ordinary memo: the whole transcript in
///   the always-editable `TranscriptEditor`. Capture: the styled quote block
///   (accent bar + attribution) above the quote-protected ramble editor — the
///   stored "> " lines never enter the editor (`CaptureQuote` write-back).
/// - **playing** — karaoke over the WHOLE memo, one continuous highlight. A
///   capture KEEPS its styled quote frame (accent bar + italics + attribution —
///   so nothing jumps when playback starts, and the book's words never read as
///   the user's): the highlight runs through the quote text inside the frame,
///   then continues into the ramble below. The timings sidecar holds the
///   quote's spoken words from index 0 and the ramble's after
///   (`appendRecording` shifts them), so the quote region karaokes from 0 and
///   the ramble region from `CaptureQuote.spokenWordCount`.
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
        if let quote = memo.captureQuote {
            VStack(alignment: .leading, spacing: 18) {
                if memo.transcriptStatus == .transcribing {
                    StatusPill(style: .working, label: "Transcribing")
                }
                CaptureQuoteFrame(attribution: memo.quoteAttributionLabel) {
                    KaraokeTranscriptView(memo: memo, player: player,
                                          text: quote.displayText, quoteStyle: true)
                }
                if !quote.ramble.isEmpty {
                    KaraokeTranscriptView(memo: memo, player: player,
                                          text: quote.ramble, wordOffset: quote.spokenWordCount)
                }
            }
        } else if let text = memo.transcript, !text.isEmpty {
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
/// count from `wordOffset` across all text segments, matching the memo's
/// timings sidecar (a capture's ramble region starts after the quote's words).
/// When playback is paused (reading mode) it renders as plain static text.
private struct KaraokeTranscriptView: View {
    let memo: Memo
    @ObservedObject var player: AudioPlayerModel
    let text: String
    /// Timings-sidecar index of this region's first word (0 unless this is the
    /// ramble below a capture quote).
    var wordOffset: Int = 0
    /// Render as the styled quote's text — italic, slightly dimmed base colour —
    /// so karaoke can run INSIDE the `CaptureQuoteFrame` without a restyle jump.
    var quoteStyle = false
    @State private var timings: [WordTiming] = []
    // Default ON (2026-06-12, user call): tapping a word during playback should
    // just work. The Settings toggle remains for opting back into the crisp
    // single-Text rendering (per-word views shift paragraph spacing slightly).
    @AppStorage("karaokeTapToSeek") private var tapToSeek = true

    /// Base colour for un-played words (the quote's text is dimmer by design).
    private var baseColor: Color { quoteStyle ? Color.skText.opacity(0.78) : .skText }

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
                            .italic(quoteStyle)
                            .lineSpacing(4)
                            .foregroundStyle(baseColor)
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
        var offset = wordOffset
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
    /// tap jumps playback to that word. Same grey-out colouring. FlowLayout
    /// flattens ALL whitespace, so the text is rebuilt as one stacked block per
    /// LINE (`KaraokeWordLayout.lines`) — otherwise paragraph breaks collapse and
    /// e.g. a multi-append ramble reads as one run (the "no division" bug).
    @ViewBuilder private func karaokeWords(_ text: String, wordOffset: Int, active: Int?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(KaraokeWordLayout.lines(of: text, base: wordOffset).enumerated()), id: \.offset) { _, line in
                // lineSpacing matches the static text's .lineSpacing(4) so the
                // layout doesn't visibly spread when playback starts (P2 nit).
                FlowLayout(spacing: 5, lineSpacing: 4) {
                    ForEach(Array(line.words.enumerated()), id: \.offset) { i, word in
                        let gi = line.offset + i
                        Text(word)
                            .font(.system(size: 15.5))
                            .italic(quoteStyle)
                            .foregroundStyle(active.map { gi < $0 ? Color.skTextDim : (gi == $0 ? Color.skAccent : baseColor) } ?? baseColor)
                            .contentShape(Rectangle())
                            .onTapGesture { seekToWord(gi) }
                    }
                }
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

/// The styled C1 quote FRAMING — accent bar on the left + plain-text
/// attribution caption from the C2 book metadata ("— Author, Book · ch. N" —
/// the `[[Author]]` wikilink stays Mac-export-side) — shared by every mode:
/// editing/reading wrap the static italic quote text, playing wraps the LIVE
/// karaoke text, so the block doesn't jump when playback starts and the
/// book's words always read as the book's.
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

/// The frame with the STATIC quote text (editing + reading modes). Non-editable
/// by design: the ramble below it is the editable part, so the quote never
/// reads as "recorded twice" plain text.
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

/// Pure layout split for the tap-to-seek word grid: `FlowLayout` flattens ALL
/// whitespace, so newline structure must be rebuilt as stacked per-line blocks
/// — otherwise paragraph breaks collapse into one continuous wrap. Each
/// non-empty line carries the timings-sidecar index of its first word so the
/// highlight and tap-to-seek stay globally aligned across lines.
enum KaraokeWordLayout {
    struct Line: Equatable {
        let words: [String]
        /// Sidecar word index of `words[0]`.
        let offset: Int
    }

    static func lines(of text: String, base: Int) -> [Line] {
        var out: [Line] = []
        var offset = base
        for raw in text.components(separatedBy: .newlines) {
            let words = raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard !words.isEmpty else { continue }
            out.append(Line(words: words, offset: offset))
            offset += words.count
        }
        return out
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
