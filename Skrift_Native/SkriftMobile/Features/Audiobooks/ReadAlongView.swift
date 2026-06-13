import SwiftUI

/// The player's read-along panel — Spotify-lyrics style (player redesign +
/// 2026-06-13 device feedback: "text smaller and jumps fast → make it more like
/// Spotify lyrics"). Discrete sentence LINES; the current line is large + bright,
/// neighbours dim by distance; the view auto-scrolls smoothly to keep the
/// current line centered; edges fade. Tap a line to seek there.
///
/// Source = the wave-2 `BookTranscript` sidecar. The WHOLE covered prefix of the
/// current file is loaded once (so scrolling is smooth — no per-tick reload); we
/// only reload when the playhead crosses the coverage frontier (it may have
/// grown) or the file changes. Un-chunked spot → the "transcribe to read along"
/// nudge.
@MainActor
final class ReadAlongModel: ObservableObject {
    @Published private(set) var covered = false
    @Published private(set) var sentences: [BufferSentence] = []   // ALL covered, file-local
    @Published private(set) var currentIndex = 0

    private let store = BookTranscriptStore()
    private var loadedFileIndex = -1
    private var loadedUpTo: TimeInterval = -1

    func update(book: Audiobook, fileIndex: Int, fileLocal: TimeInterval, audioURL: URL?) {
        if fileIndex != loadedFileIndex || fileLocal > loadedUpTo {
            reload(book: book, fileIndex: fileIndex, fileLocal: fileLocal, audioURL: audioURL)
        }
        if !sentences.isEmpty {
            let idx = sentences.lastIndex(where: { $0.start <= fileLocal }) ?? 0
            if idx != currentIndex { currentIndex = idx }
        }
    }

    private func reload(book: Audiobook, fileIndex: Int, fileLocal: TimeInterval, audioURL: URL?) {
        loadedFileIndex = fileIndex
        if let audioURL,
           let ft = store.fileTranscript(bookID: book.id, fileIndex: fileIndex, audioURL: audioURL),
           ft.isCovered(upTo: fileLocal) {
            sentences = QuoteCaptureProcessor.buildSentences(from: ft.words, snappedStart: 0, snappedEnd: 0)
            covered = !sentences.isEmpty
            loadedUpTo = ft.coveredUpTo            // reload when playhead passes the frontier
        } else {
            sentences = []; covered = false
            loadedUpTo = fileLocal + 2             // re-check ~2 s later (bg job may catch up)
        }
    }

    /// File-local start of sentence `i` (for tap-to-seek). nil if out of range.
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

    @StateObject private var model = ReadAlongModel()

    /// Fixed so the player layout is stable across states; the lyrics scroll
    /// internally within it.
    private let panelHeight: CGFloat = 234

    var body: some View {
        Group {
            if model.covered { lyrics } else { nudge }
        }
        .frame(height: panelHeight)
        .onAppear { refresh() }
        .onChange(of: fileLocal) { _, _ in refresh() }
        .onChange(of: fileIndex) { _, _ in refresh() }
    }

    private func refresh() {
        model.update(book: book, fileIndex: fileIndex, fileLocal: fileLocal, audioURL: audioURL)
    }

    // MARK: - Lyrics (transcribed)

    private var lyrics: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 13) {
                    Color.clear.frame(height: panelHeight * 0.38)   // lets line 0 center
                    ForEach(model.sentences.indices, id: \.self) { i in
                        line(i).id(i)
                    }
                    Color.clear.frame(height: panelHeight * 0.5)
                }
                .padding(.horizontal, 2)
            }
            .onChange(of: model.currentIndex) { _, idx in
                withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(idx, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(model.currentIndex, anchor: .center) }
        }
        // Spotify-style soft fade at the top/bottom edges.
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
