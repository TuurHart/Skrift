import SwiftUI

/// Hosts the audiobook quote-capture flow, presented full-screen over the player
/// or the mini-player the moment Capture fires. The presenter pauses the book
/// FIRST; this view then owns the rest: it shows the merged note-style capture
/// screen (`MergedCaptureView`) and resumes the book + dismisses when the capture
/// finishes or is cancelled. Text capture is the only flow now — the audio
/// mark-in/out arm is retired.
struct QuoteCaptureFlowView: View {
    @ObservedObject private var session = AudiobookSession.shared
    @Environment(\.dismiss) private var dismiss

    private let book: Audiobook?
    private let pausedAt: TimeInterval
    /// GLOBAL bounds of the audio file `pausedAt` falls in — the quote audio is
    /// extracted from that file alone. Single-file books: the whole book.
    private let fileBounds: CaptureSpan.Span
    private let fileIndex: Int

    init() {
        let session = AudiobookSession.shared
        book = session.book
        pausedAt = session.currentTime
        let bounds = session.book?.fileBounds(at: session.currentTime)
            ?? CaptureSpan.Span(start: 0, end: 0)
        fileBounds = bounds
        fileIndex = session.book?.fileIndex(at: session.currentTime) ?? 0
    }

    var body: some View {
        ZStack {
            Color.skBg.ignoresSafeArea()
            if let book {
                MergedCaptureView(
                    book: book,
                    audioURL: session.store.audioURL(of: book, fileIndex: fileIndex),
                    fileIndex: fileIndex,
                    pausedAt: pausedAt,
                    fileBounds: fileBounds,
                    onFinish: { session.play(); dismiss() }
                )
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .task {
            // Yield the engine to this capture: pause any background whole-book
            // transcribe so an un-chunked (wave-1 fallback) window isn't stuck
            // behind a chunk. Harmless when idle or already chunked. Resumed on dismiss.
            BookTranscriptionJob.shared.suspendForCapture()
            // Warm the ASR model the moment the capture flow opens — the span
            // build after "Record your thoughts" is then seconds, not a cold-start
            // wait. Skipped on the seeded sim/UI-test path.
            if LaunchFlags.seedTranscript == nil {
                Task { try? await TranscriptionService.shared.ensureLoaded() }
            }
        }
        .onDisappear { BookTranscriptionJob.shared.resumeAfterCapture() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quote-capture-flow")
    }
}

// MARK: - CapturePausedRow

/// The "book paused" header row shared by the capture stages (mock state 3).
struct CapturePausedRow: View {
    let book: Audiobook
    let pausedAt: TimeInterval

    var body: some View {
        HStack(spacing: 11) {
            BookCoverView(book: book)
                .frame(width: 40, height: 40)
                .clipShape(.rect(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(book.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.skText)
                    .lineLimit(1)
                Text(pausedLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.skTextFaint)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("PAUSED")
                .font(.system(size: 9.5, weight: .bold))
                .kerning(0.5)
                .foregroundStyle(Color.skAmber)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Color.skAmber.opacity(0.12), in: .capsule)
        }
        .padding(EdgeInsets(top: 9, leading: 11, bottom: 9, trailing: 11))
        .background(Color.skSurface, in: .rect(cornerRadius: 13, style: .continuous))
    }

    private var pausedLine: String {
        let at = "paused at " + AudiobookTime.clock(pausedAt)
        if let chapter = book.shortChapterLabel(at: pausedAt) {
            return chapter + " \u{00B7} " + at
        }
        return at
    }
}
