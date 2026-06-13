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
    let onTranscribe: () -> Void

    @ObservedObject private var session = AudiobookSession.shared
    @StateObject private var model = ReadAlongModel()

    /// Interpolation anchor: the playhead value (file-local) at the last real
    /// 0.5 s tick, and the wall-clock when it landed.
    @State private var anchorLocal: TimeInterval = 0
    @State private var anchorWall = Date()
    /// Wall-clock throttle for re-checking coverage while showing the nudge.
    @State private var lastRecheck = Date()

    private let panelHeight: CGFloat = 234
    /// How far before the current line's audio END to flip to the next line. Small
    /// now that the timings are drift-free + interpolated — just covers the render
    /// beat. 0.3 read "a bit too early" on device; 0.1 sits in-sync. Tunable.
    private let lead: TimeInterval = 0.1

    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if model.covered { lyrics } else { nudge }
        }
        .frame(height: panelHeight)
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

    // MARK: - Lyrics (transcribed)

    private var lyrics: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 13) {
                    Color.clear.frame(height: panelHeight * 0.38)
                    ForEach(model.sentences.indices, id: \.self) { i in
                        line(i).id(i)
                    }
                    Color.clear.frame(height: panelHeight * 0.5)
                }
                .padding(.horizontal, 2)
            }
            .onChange(of: model.currentIndex) { _, idx in
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(idx, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(model.currentIndex, anchor: .center) }
        }
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.16),
                .init(color: .black, location: 0.84),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        )
        .accessibilityIdentifier("player-readalong")
    }

    private func line(_ i: Int) -> some View {
        let isCurrent = i == model.currentIndex
        let isPast = i < model.currentIndex
        // UNIFORM font size + weight → the line height never changes, so advancing
        // the highlight doesn't reflow/shove neighbours (the "words hustle" jump).
        // Emphasis is a smooth `scaleEffect` (a transform — no layout reflow) +
        // brightness, both animatable, anchored leading so the text doesn't shift.
        return Text(model.sentences[i].text)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(isCurrent ? Color.skText : (isPast ? Color.skTextFaint : Color.skTextDim))
            .opacity(isCurrent ? 1 : (abs(i - model.currentIndex) == 1 ? 0.6 : 0.32))
            .scaleEffect(isCurrent ? 1.08 : 1.0, anchor: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard let local = model.startOf(i) else { return }
                let origin = book.fileStartTimes.indices.contains(fileIndex) ? book.fileStartTimes[fileIndex] : 0
                AudiobookSession.shared.seek(to: local + origin)
                Haptics.tap()
            }
            .animation(.easeInOut(duration: 0.3), value: model.currentIndex)
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
