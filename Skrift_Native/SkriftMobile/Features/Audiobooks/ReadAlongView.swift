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
        guard fileIndex != loadedFileIndex || fileLocal > loadedUpTo else { return }
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

    /// Set the lit line to the last sentence that has started at `fileLocal`.
    func setCurrent(fileLocal: TimeInterval) {
        guard !sentences.isEmpty else { return }
        let idx = sentences.lastIndex(where: { $0.start <= fileLocal }) ?? 0
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

    private let panelHeight: CGFloat = 234
    /// Nudge the highlight slightly ahead to cancel TDT's late word timings + the
    /// render/animation beat, so it reads as in-sync. Tunable.
    private let lead: TimeInterval = 0.2

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
        }
        .onChange(of: fileIndex) { _, _ in
            model.reloadIfNeeded(book: book, fileIndex: fileIndex, fileLocal: fileLocal, audioURL: audioURL)
        }
        // Fine driver: interpolate between ticks so the line tracks the voice.
        .onReceive(tick) { _ in
            guard model.covered else { return }
            let elapsed = session.isPlaying ? min(Date().timeIntervalSince(anchorWall) * session.rate, 0.6) : 0
            model.setCurrent(fileLocal: anchorLocal + elapsed + lead)
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
        return Text(model.sentences[i].text)
            .font(.system(size: isCurrent ? 21 : 17, weight: isCurrent ? .semibold : .regular))
            .foregroundStyle(isCurrent ? Color.skText : (isPast ? Color.skTextFaint : Color.skTextDim))
            .opacity(isCurrent ? 1 : (abs(i - model.currentIndex) == 1 ? 0.75 : 0.45))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard let local = model.startOf(i) else { return }
                let origin = book.fileStartTimes.indices.contains(fileIndex) ? book.fileStartTimes[fileIndex] : 0
                AudiobookSession.shared.seek(to: local + origin)
                Haptics.tap()
            }
            .animation(.easeInOut(duration: 0.18), value: model.currentIndex)
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
