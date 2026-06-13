import SwiftUI

/// The player's read-along text panel (player redesign — the text-forward hero).
/// Shows the narration around the playhead from the wave-2 `BookTranscript`
/// sidecar, the CURRENT sentence lit (past fades, a little upcoming trails).
/// When the spot isn't transcribed yet it shows the "transcribe to read along"
/// nudge — which routes to the whole-book transcribe (the growth loop).
///
/// Disk I/O is kept OFF the 0.5 s playback tick: the sidecar window is loaded
/// only when the playhead leaves the cached range (or the file changes); the lit
/// line is recomputed in-memory every update.
@MainActor
final class ReadAlongModel: ObservableObject {
    enum LineState { case past, current, upcoming }
    struct Line: Identifiable, Equatable { let id: Int; let text: String; let state: LineState }

    @Published private(set) var covered = false
    @Published private(set) var lines: [Line] = []

    private let store = BookTranscriptStore()
    private var sentences: [BufferSentence] = []      // loaded window, file-local
    private var loadedFileIndex = -1
    private var validRange: ClosedRange<TimeInterval>?

    func update(book: Audiobook, fileIndex: Int, fileLocal: TimeInterval, audioURL: URL?) {
        let stale = fileIndex != loadedFileIndex || !(validRange?.contains(fileLocal) ?? false)
        if stale { reload(book: book, fileIndex: fileIndex, fileLocal: fileLocal, audioURL: audioURL) }
        recompute(fileLocal: fileLocal)
    }

    private func reload(book: Audiobook, fileIndex: Int, fileLocal: TimeInterval, audioURL: URL?) {
        loadedFileIndex = fileIndex
        if let audioURL,
           let ft = store.fileTranscript(bookID: book.id, fileIndex: fileIndex, audioURL: audioURL),
           ft.isCovered(upTo: fileLocal) {
            let words = ft.words(inWindow: max(0, fileLocal - 90), end: fileLocal + 60)
            sentences = QuoteCaptureProcessor.buildSentences(from: words, snappedStart: 0, snappedEnd: 0)
            covered = !sentences.isEmpty
            // Cache valid until the playhead passes 30 s ahead of this load (then
            // reload to pull the next sentences) or scrubs before the window.
            validRange = covered ? (max(0, fileLocal - 90))...(fileLocal + 30) : nil
        } else {
            sentences = []; covered = false
            // Not transcribed here — re-check every ~3 s so a running bg job that
            // catches up flips us to read-along without a manual refresh.
            validRange = (fileLocal - 1)...(fileLocal + 3)
        }
    }

    private func recompute(fileLocal: TimeInterval) {
        guard !sentences.isEmpty else { lines = []; return }
        let cur = sentences.lastIndex(where: { $0.start <= fileLocal }) ?? 0
        let lo = max(0, cur - 1), hi = min(sentences.count - 1, cur + 2)
        lines = (lo...hi).map { i in
            Line(id: i, text: sentences[i].text,
                 state: i < cur ? .past : (i == cur ? .current : .upcoming))
        }
    }
}

struct ReadAlongView: View {
    let book: Audiobook
    let fileIndex: Int
    let fileLocal: TimeInterval
    let audioURL: URL?
    let onTranscribe: () -> Void

    @StateObject private var model = ReadAlongModel()

    var body: some View {
        Group {
            if model.covered {
                readAlong
            } else {
                nudge
            }
        }
        .onAppear { refresh() }
        .onChange(of: fileLocal) { _, _ in refresh() }
        .onChange(of: fileIndex) { _, _ in refresh() }
    }

    private func refresh() {
        model.update(book: book, fileIndex: fileIndex, fileLocal: fileLocal, audioURL: audioURL)
    }

    // MARK: - Read-along (transcribed)

    private var readAlong: some View {
        VStack(alignment: .leading, spacing: 12) {
            flowing
            HStack(spacing: 6) {
                Circle().fill(Color.skAccent).frame(width: 6, height: 6)
                Text("reading now").font(.system(size: 11)).foregroundStyle(Color.skTextFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("player-readalong")
    }

    /// One flowing block (teleprompter feel): past faint, current lit, upcoming dim.
    private var flowing: some View {
        model.lines.reduce(Text("")) { acc, line in
            let color: Color = line.state == .current ? .skText
                : (line.state == .past ? .skTextFaint : .skTextDim)
            return acc + Text(line.text + " ").foregroundColor(color)
        }
        .font(.system(size: 17))
        .lineSpacing(5)
        .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityIdentifier("player-readalong-nudge")
    }
}
