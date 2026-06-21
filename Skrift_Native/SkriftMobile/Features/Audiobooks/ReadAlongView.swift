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
    /// Saved bookmarks (whole book) — the reader hangs a margin glyph + faint tint
    /// beside the line each one lands on (mapped global time → this file's sentence).
    var bookmarks: [AudiobookBookmark] = []
    let onTranscribe: () -> Void
    /// Called when the reader detects an interactive (user) scroll — the parent
    /// uses it to recede the player chrome ("more page" while reading).
    var onUserScroll: () -> Void = {}
    /// Tap the left gutter beside a line to fold/unfold a bookmark there. Called
    /// with that sentence's GLOBAL book time; the parent toggles the store and
    /// passes back an updated `bookmarks` (2026-06-21 — replaces the bottom button).
    var onToggleBookmarkAt: (TimeInterval) -> Void = { _ in }

    @ObservedObject private var session = AudiobookSession.shared
    @ObservedObject private var transcribeJob = BookTranscriptionJob.shared
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
        // Re-anchor the moment playback resumes: otherwise the next 0.1 s tick
        // interpolates from a stale anchor and the word overshoots (up to the 0.6 s
        // clamp × rate) until the next real 0.5 s tick lands.
        .onChange(of: session.isPlaying) { _, playing in
            if playing { anchorLocal = fileLocal; anchorWall = Date() }
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
                let marks = bookmarkedSentences
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: readingLineSpacing) {
                        Color.clear.frame(height: geo.size.height * nowAnchor.y)
                        ForEach(model.sentences.indices, id: \.self) { i in
                            line(i, marked: marks.contains(i)).id(i)
                        }
                        Color.clear.frame(height: geo.size.height * 0.66)
                    }
                    .frame(maxWidth: columnMax)        // reading column cap (~60–68ch)
                    .frame(maxWidth: .infinity)         // centre the column (iPad)
                    // Each line carries its own tappable left gutter (the fold zone);
                    // a hair of leading so it isn't flush to the screen edge.
                    .padding(.leading, 2).padding(.trailing, 4)
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

    /// One sentence-line. Flat 3-step colour ramp (past dim / now bright-white /
    /// ahead). Uniform font + weight throughout — no per-word weight (it re-wrapped
    /// the line as the bold word advanced) and no scale; the now-line pops purely on
    /// brightness, which the user preferred. The bright sentence still advances with
    /// the voice (sentence-level), just without the per-word follow.
    private func line(_ i: Int, marked: Bool) -> some View {
        let isCurrent = i == model.currentIndex
        let isPast = i < model.currentIndex
        return HStack(alignment: .top, spacing: 0) {
            // The fold zone: a full-height tappable left gutter. Tap to bookmark
            // ("fold the corner"), tap again to remove ("unfold"). Shows the mark
            // when set — the marker the user already liked, now toggleable.
            Button { toggleBookmark(at: i) } label: {
                Color.clear
                    .frame(width: 22)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .topLeading) {
                        if marked {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 11)).foregroundStyle(Color.skAccent)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(marked ? "Remove bookmark" : "Add bookmark")

            Text(model.sentences[i].text)
                .foregroundColor(isCurrent ? Self.readNow : (isPast ? Self.readPast : Self.readAhead))
                .font(.system(size: readingFontSize, weight: .regular))
                .lineSpacing(readingLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { seek(to: i) }   // tap the TEXT to seek (gutter = bookmark)
        }
        // Faint "this bit is saved" tint behind a bookmarked line, scrolls with it.
        .background { if marked { Color.skAccent.opacity(0.09) } }
        .animation(.easeInOut(duration: 0.2), value: marked)
        .animation(.easeInOut(duration: 0.25), value: model.currentIndex)
    }

    /// Tap the text → seek there (resumes follow).
    private func seek(to i: Int) {
        guard let local = model.startOf(i) else { return }
        let origin = book.fileStartTimes.indices.contains(fileIndex) ? book.fileStartTimes[fileIndex] : 0
        AudiobookSession.shared.seek(to: local + origin)
        following = true
        Haptics.tap()
    }

    /// Tap the gutter → fold/unfold a bookmark at this sentence's global position.
    private func toggleBookmark(at i: Int) {
        guard let local = model.startOf(i) else { return }
        let origin = book.fileStartTimes.indices.contains(fileIndex) ? book.fileStartTimes[fileIndex] : 0
        onToggleBookmarkAt(local + origin)
    }

    /// Sentence indices (in THIS file) that a bookmark lands on. A bookmark's
    /// GLOBAL position maps to a file + file-local offset; if it's this file, find
    /// the sentence whose span contains it. Computed once per render in `lyrics`.
    private var bookmarkedSentences: Set<Int> {
        guard !bookmarks.isEmpty, !model.sentences.isEmpty else { return [] }
        var set = Set<Int>()
        for bm in bookmarks {
            let loc = book.fileLocation(at: bm.position)
            guard loc.index == fileIndex else { continue }
            if let idx = model.sentences.firstIndex(where: { loc.offset < $0.end }) { set.insert(idx) }
        }
        return set
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

    // MARK: - Read-along states (no text here yet)

    /// Two states when the current spot isn't covered: a live "Transcribing… N%"
    /// while a whole-book transcribe runs, otherwise the "read along later" nudge.
    @ViewBuilder
    private var nudge: some View {
        if transcribeJob.activeBookID == book.id, transcribeJob.isRunningOrPaused {
            transcribingState
        } else {
            notTranscribedState
        }
    }

    /// Mock screen 5 — audio works without text; transcribe on-device to read along.
    private var notTranscribedState: some View {
        VStack(spacing: 8) {
            BookCoverView(book: book)
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                .padding(.bottom, 4)
            Text("Listen now, read along later")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.skText)
            Text("Transcribe this book on-device to follow the words as they're read. Runs while you listen — a few minutes.")
                .font(.system(size: 12.5)).foregroundStyle(Color.skTextDim)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button(action: onTranscribe) {
                HStack(spacing: 7) {
                    Image(systemName: "text.book.closed").font(.system(size: 13, weight: .semibold))
                    Text("Transcribe for read-along").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.skAccent, in: .capsule)
                .shadow(color: Color.skAccent.opacity(0.4), radius: 10, y: 4)
            }
            .padding(.top, 6)
            .accessibilityIdentifier("player-readalong-nudge")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 30)
    }

    /// Live progress while a whole-book transcribe runs (mock: "Transcribing… 38%").
    private var transcribingState: some View {
        VStack(spacing: 12) {
            BookCoverView(book: book)
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 8, style: .continuous))
                .padding(.bottom, 2)
            Text("Transcribing for read-along")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.skText)
            ProgressView(value: max(0, min(1, transcribeJob.progress)))
                .tint(Color.skAccent).frame(maxWidth: 220)
            Text("\(Int((transcribeJob.progress * 100).rounded()))%")
                .font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(Color.skAccent)
            Text("Keep listening — the page catches up as it goes.")
                .font(.system(size: 12)).foregroundStyle(Color.skTextDim).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 30)
        .accessibilityIdentifier("player-readalong-transcribing")
    }
}
