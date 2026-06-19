import SwiftUI

/// The player's read-along panel — Spotify-lyrics style. Discrete sentence
/// LINES; the current line is large + bright, neighbours dim by distance; the
/// view auto-scrolls smoothly to keep the current line centered; edges fade.
/// Tap a line to seek there.
///
/// SYNC (2026-06-13 device feedback "text lags behind voice"): the AVPlayer
/// playhead (`session.currentTime`) only ticks every 0.5 s, so reading the line
/// straight off it quantizes the highlight to half-second steps and always
/// trails. We INTERPOLATE between ticks (anchor + wall-elapsed × rate) and
/// re-evaluate ~10×/s, plus a small `lead` for Parakeet-TDT's slightly-late word
/// timings — so the lit line tracks the narrator instead of lagging.
///
/// Source = the wave-2 `BookTranscript` sidecar; the whole covered prefix of the
/// file is loaded once (reload only on coverage-frontier cross / file change) so
/// scrolling is smooth. Un-chunked spot → the "transcribe to read along" nudge.
@MainActor
final class ReadAlongModel: ObservableObject {
    @Published private(set) var covered = false
    @Published private(set) var sentences: [BufferSentence] = []   // ALL covered, file-local
    @Published private(set) var currentIndex = 0
    /// Index of the word being spoken WITHIN the current sentence (nil = none yet).
    /// Drives the current-word weight+underline. Published only when it changes, so
    /// the read-along doesn't re-render at the 10 Hz interpolation rate.
    @Published private(set) var currentWordIndex: Int?

    private let store = BookTranscriptStore()
    private var loadedFileIndex = -1
    private var loadedUpTo: TimeInterval = -1

    /// Reload the sentence list if needed (file changed / playhead crossed the
    /// coverage frontier). Does NOT touch `currentIndex` — that's driven finely
    /// by `setCurrent`.
    func reloadIfNeeded(book: Audiobook, fileIndex: Int, fileLocal: TimeInterval, audioURL: URL?) {
        // Re-run on a file change, when the playhead crosses the loaded frontier,
        // OR whenever we're NOT covered — so a transcribe that finishes while the
        // player sits paused on the nudge flips to read-along on the next re-check
        // (the view drives that on a wall-clock timer), instead of waiting for
        // playback to advance past a threshold (device bug 2026-06-13).
        guard fileIndex != loadedFileIndex || fileLocal > loadedUpTo || !covered else { return }
        loadedFileIndex = fileIndex
        if let audioURL,
           let ft = store.fileTranscript(bookID: book.id, fileIndex: fileIndex, audioURL: audioURL),
           ft.isCovered(upTo: fileLocal) {
            sentences = QuoteCaptureProcessor.buildSentences(from: ft.words, snappedStart: 0, snappedEnd: 0)
            covered = !sentences.isEmpty
            loadedUpTo = ft.coveredUpTo
        } else {
            sentences = []; covered = false
            loadedUpTo = fileLocal + 2
        }
    }

    /// Set the lit line. Advance at the END of the current sentence rather than
    /// the START of the next: the first sentence that hasn't finished yet. So the
    /// next line lights up the moment the current one's audio ends — riding
    /// through any inter-sentence pause and not waiting on Parakeet's
    /// slightly-late next-start time (the "trails the voice" fix, 2026-06-13).
    func setCurrent(fileLocal: TimeInterval) {
        guard !sentences.isEmpty else { return }
        let idx = sentences.firstIndex(where: { fileLocal < $0.end }) ?? (sentences.count - 1)
        if idx != currentIndex { currentIndex = idx }
        // The active word inside the current sentence (for the weight+underline).
        let wi = Karaoke.activeWordIndex(sentences[idx].words, at: fileLocal)
        if wi != currentWordIndex { currentWordIndex = wi }
    }

    func startOf(_ i: Int) -> TimeInterval? {
        sentences.indices.contains(i) ? sentences[i].start : nil
    }
}

struct ReadAlongView: View {
    let book: Audiobook
    let fileIndex: Int
    let fileLocal: TimeInterval
    let audioURL: URL?
    let onTranscribe: () -> Void
    /// Called when the reader detects an interactive (user) scroll — the parent
    /// uses it to recede the player chrome ("more page" while reading).
    var onUserScroll: () -> Void = {}

    @ObservedObject private var session = AudiobookSession.shared
    @StateObject private var model = ReadAlongModel()

    /// Auto-scroll follows the playhead until the user scrolls away; then a
    /// transient "Back to playing" pill restores it. (Spotify-lyrics / Snipd.)
    @State private var following = true

    // Reading-mode palette (mock's locked 3-step attention ramp): past dim, now
    // brightest, ahead still legible so you can read ahead like a page. The light/
    // sepia reading themes are a chunk-5 fast-follow.
    private static let readPast = Color(hex: 0x6E6E7E)
    private static let readNow = Color(hex: 0xF4F4F8)
    private static let readAhead = Color(hex: 0xA6A6B6)
    /// The current-word cue is a thin accent underline, NOT a filled box (a box
    /// broke reading flow — mock critique).
    private static let wordUnderline = Color.skAccent

    /// Reading type — driven by the "Aa" settings (persisted app-wide).
    @AppStorage(ReadingPrefs.fontSizeKey) private var fontSizePref = ReadingPrefs.defaultFontSize
    @AppStorage(ReadingPrefs.lineHeightKey) private var lineHeightPref = ReadingPrefs.defaultLineHeight
    private var readingFontSize: CGFloat { CGFloat(fontSizePref) }
    private var readingLineSpacing: CGFloat { ReadingPrefs.extraLeading(fontSize: fontSizePref, lineHeight: lineHeightPref) }
    /// Pin the now-line to the upper third (mock): text scrolls UP under it.
    private let nowAnchor = UnitPoint(x: 0.5, y: 0.34)
    /// Reading column cap (~60–68ch) so text never runs full-bleed on iPad.
    private let columnMax: CGFloat = 660

    /// Interpolation anchor: the playhead value (file-local) at the last real
    /// 0.5 s tick, and the wall-clock when it landed.
    @State private var anchorLocal: TimeInterval = 0
    @State private var anchorWall = Date()
    /// Wall-clock throttle for re-checking coverage while showing the nudge.
    @State private var lastRecheck = Date()

    /// How far before the current line's audio END to flip to the next line. Small
    /// now that the timings are drift-free + interpolated — just covers the render
    /// beat. 0.3 read "a bit too early" on device; 0.1 sits in-sync. Tunable.
    private let lead: TimeInterval = 0.1

    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if model.covered { lyrics } else { nudge }
        }
        // Fill the vertical space the player hands us (the read-along is the hero,
        // 2026-06-13) instead of a fixed 234pt panel that left dead space below the
        // controls. minHeight guards tiny layouts.
        .frame(minHeight: 180, maxHeight: .infinity)
        .onAppear {
            anchorLocal = fileLocal; anchorWall = Date()
            model.reloadIfNeeded(book: book, fileIndex: fileIndex, fileLocal: fileLocal, audioURL: audioURL)
            model.setCurrent(fileLocal: fileLocal + lead)
        }
        // Each real 0.5 s tick (or a scrub) re-anchors the interpolation + checks
        // whether to reload the covered window.
        .onChange(of: fileLocal) { _, v in
            anchorLocal = v; anchorWall = Date()
            model.reloadIfNeeded(book: book, fileIndex: fileIndex, fileLocal: v, audioURL: audioURL)
            model.setCurrent(fileLocal: v + lead)   // baseline each real tick; the timer refines between
        }
        .onChange(of: fileIndex) { _, _ in
            model.reloadIfNeeded(book: book, fileIndex: fileIndex, fileLocal: fileLocal, audioURL: audioURL)
        }
        // Fine driver: interpolate between ticks so the line tracks the voice.
        .onReceive(tick) { _ in
            if model.covered {
                let elapsed = session.isPlaying ? min(Date().timeIntervalSince(anchorWall) * session.rate, 0.6) : 0
                model.setCurrent(fileLocal: anchorLocal + elapsed + lead)
            } else if Date().timeIntervalSince(lastRecheck) > 1.5 {
                // Still on the nudge — re-check coverage every ~1.5 s (even paused)
                // so a transcribe finishing in the background flips us to read-along.
                lastRecheck = Date()
                model.reloadIfNeeded(book: book, fileIndex: fileIndex, fileLocal: fileLocal, audioURL: audioURL)
            }
        }
    }

    // MARK: - Lyrics (transcribed) — e-reader "page", now-line pinned upper-third

    private var lyrics: some View {
        // GeometryReader so the head/tail clear-space scales with the height the
        // player hands us; the now-line parks ~⅓ down (the focus band) and text
        // scrolls up under it like a page.
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: readingLineSpacing) {
                        Color.clear.frame(height: geo.size.height * nowAnchor.y)
                        ForEach(model.sentences.indices, id: \.self) { i in
                            line(i).id(i)
                        }
                        Color.clear.frame(height: geo.size.height * 0.66)
                    }
                    .frame(maxWidth: columnMax)        // reading column cap (~60–68ch)
                    .frame(maxWidth: .infinity)         // centre the column (iPad)
                    .padding(.horizontal, 4)
                }
                // Follow the playhead — but only while the user hasn't scrolled away.
                .onChange(of: model.currentIndex) { _, idx in
                    guard following else { return }
                    withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(idx, anchor: nowAnchor) }
                }
                // An interactive (user) scroll breaks follow → show "Back to playing"
                // + tell the parent to recede chrome. Programmatic auto-scroll reports
                // .animating, not .interacting, so it never trips this.
                .onScrollPhaseChange { _, newPhase in
                    if newPhase == .interacting, following {
                        following = false
                        onUserScroll()
                    }
                }
                .onAppear { proxy.scrollTo(model.currentIndex, anchor: nowAnchor) }
                .overlay(alignment: .bottom) {
                    if !following {
                        backToPlaying {
                            withAnimation(.easeInOut(duration: 0.3)) { following = true }
                            withAnimation(.easeInOut(duration: 0.4)) {
                                proxy.scrollTo(model.currentIndex, anchor: nowAnchor)
                            }
                        }
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: following)
            }
        }
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.12),
                .init(color: .black, location: 0.88),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        )
        .accessibilityIdentifier("player-readalong")
    }

    /// One sentence-line. Flat 3-step colour ramp (past/now/ahead) — no per-line
    /// scale (that read teleprompter-y); the now-line pops via brightness + the
    /// current-word weight+underline. Uniform font/weight keeps the line height
    /// stable so advancing never reflows neighbours.
    private func line(_ i: Int) -> some View {
        let isCurrent = i == model.currentIndex
        let isPast = i < model.currentIndex
        let text: Text = isCurrent
            ? currentLineText(model.sentences[i])
            : Text(model.sentences[i].text).foregroundColor(isPast ? Self.readPast : Self.readAhead)
        return text
            .font(.system(size: readingFontSize, weight: .regular))
            .lineSpacing(readingLineSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard let local = model.startOf(i) else { return }
                let origin = book.fileStartTimes.indices.contains(fileIndex) ? book.fileStartTimes[fileIndex] : 0
                AudiobookSession.shared.seek(to: local + origin)
                following = true            // a deliberate jump → resume follow
                Haptics.tap()
            }
            .animation(.easeInOut(duration: 0.25), value: model.currentIndex)
    }

    /// The now-line, rendered word-by-word so the active word gets weight + a thin
    /// accent underline (mock: NOT a filled box). Words rejoin with single spaces —
    /// the same join `buildSentences` uses, so the text is byte-identical.
    private func currentLineText(_ s: BufferSentence) -> Text {
        var result = Text("")
        for (i, w) in s.words.enumerated() {
            var piece = Text(w.word)
            if i == model.currentWordIndex {
                piece = piece.fontWeight(.semibold).underline(true, color: Self.wordUnderline)
            }
            result = result + piece
            if i < s.words.count - 1 { result = result + Text(" ") }
        }
        return result.foregroundColor(Self.readNow)
    }

    /// The transient pill that floats up when you scroll away from the now-line.
    private func backToPlaying(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down").font(.system(size: 11, weight: .semibold))
                Text("Back to playing").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color.skAccent, in: .capsule)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        }
        .accessibilityIdentifier("player-back-to-playing")
    }

    // MARK: - Nudge (not transcribed here)

    private var nudge: some View {
        Button(action: onTranscribe) {
            VStack(spacing: 10) {
                Text("Transcribe this book to read along\nand capture from anywhere.")
                    .font(.system(size: 13.5)).foregroundStyle(Color.skTextDim)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text("Transcribe book →")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.skAccent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20).padding(.horizontal, 16)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.skBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier("player-readalong-nudge")
    }
}
