import SwiftUI

/// The retroactive capture flow (mock states 3 → 4), presented full-screen
/// over the player or the mini-player the moment Capture fires. The presenter
/// pauses the book FIRST; this flow then owns the rest:
/// adjust span (full-screen) → transcribe + sentence-snap (processing) →
/// the capture sheet over the created memo → resume the book.
struct QuoteCaptureFlowView: View {
    @ObservedObject private var session = AudiobookSession.shared
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case adjust
        case processing
        case sheet(memoID: UUID, output: QuoteCaptureOutput)
    }

    private let book: Audiobook?
    private let pausedAt: TimeInterval
    /// GLOBAL bounds of the audio file `pausedAt` falls in — the span (and the
    /// waveform strip) are confined to ONE file; the quote audio is extracted
    /// from that file alone. Single-file books: the whole book.
    private let fileBounds: CaptureSpan.Span
    private let fileIndex: Int

    @State private var stage: Stage = .adjust
    @State private var span: CaptureSpan.Span
    @State private var errorMessage: String?

    // MARK: - Swipe-down-to-dismiss (item 4)

    /// Vertical offset while the user is dragging down to dismiss the adjust
    /// screen. Zero at rest; the content tracks the finger. Matches the same
    /// design as `AudiobookPlayerView.dismissDrag`.
    @State private var dragOffset: CGFloat = 0

    init() {
        let session = AudiobookSession.shared
        book = session.book
        pausedAt = session.currentTime
        let bounds = session.book?.fileBounds(at: session.currentTime)
            ?? CaptureSpan.Span(start: 0, end: 0)
        fileBounds = bounds
        fileIndex = session.book?.fileIndex(at: session.currentTime) ?? 0
        _span = State(initialValue: CaptureSpan.proposal(
            now: session.currentTime,
            in: bounds
        ))
    }

    var body: some View {
        ZStack {
            Color.skBg.ignoresSafeArea()
            if let book {
                switch stage {
                case .adjust:
                    adjustStage(book)
                case .processing:
                    processingStage(book)
                case .sheet(let memoID, let output):
                    CaptureSheetView(
                        book: book,
                        output: output,
                        memoID: memoID,
                        onFinish: { resume in finish(resume: resume, output: output) },
                        onDiscard: { discard(memoID: memoID, output: output) }
                    )
                }
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .task {
            // Warm the ASR model the moment the capture flow opens — the span
            // transcription after Confirm then takes seconds instead of a
            // cold-start wait. Skipped on the seeded sim/UI-test path.
            if LaunchFlags.seedTranscript == nil {
                Task { try? await TranscriptionService.shared.ensureLoaded() }
            }
        }
        .alert("Capture failed", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quote-capture-flow")
    }

    // MARK: - Adjust stage (items 3 + 4: fullscreen, swipe-down)

    /// The adjust screen is fullscreen (item 3) — no floating card with dead
    /// space below. Swipe-down dismisses it (item 4) using the same gesture
    /// design as `AudiobookPlayerView.dismissDrag`.
    private func adjustStage(_ book: Audiobook) -> some View {
        CaptureMomentView(
            book: book,
            audioURL: session.store.audioURL(of: book, fileIndex: fileIndex),
            now: pausedAt,
            bounds: fileBounds,
            span: $span,
            onCancel: {
                session.play()
                dismiss()
            },
            onConfirm: { confirmCapture(book) }
        )
        .contentShape(Rectangle())
        .offset(y: dragOffset)
        .gesture(adjustDismissDrag)
    }

    /// Swipe-down-to-dismiss on the adjust screen: vertically-dominant downward
    /// drag tracks the finger; dismiss past 130 pt or a fast fling; spring back
    /// otherwise. Matches `AudiobookPlayerView.dismissDrag` exactly so both
    /// screens feel consistent. The strip's own `DragGesture` wins inside its
    /// frame (child beats ancestor), so seek and dismiss never fight.
    private var adjustDismissDrag: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                if value.translation.height > 0,
                   value.translation.height > abs(value.translation.width) {
                    dragOffset = value.translation.height
                } else if value.translation.height <= 0 {
                    dragOffset = 0
                }
            }
            .onEnded { value in
                if dragOffset > 130 || (dragOffset > 0 && value.predictedEndTranslation.height > 280) {
                    // Cancel the capture and resume the book, same as "Cancel · resume".
                    session.play()
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: - Processing stage

    private func processingStage(_ book: Audiobook) -> some View {
        VStack(spacing: 0) {
            CapturePausedRow(book: book, pausedAt: pausedAt)
                .padding(.horizontal, Theme.Space.margin)
                .padding(.top, 14)

            Spacer()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Transcribing the span\u{2026}")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.skText)
                Text("The marked range \u{00B1} 20 s runs through the on-device model \u{2014} never the whole book. Both edges snap outward to whole sentences.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.skTextDim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            .accessibilityIdentifier("capture-processing")

            Spacer()
        }
    }

    // MARK: - Actions

    private func confirmCapture(_ book: Audiobook) {
        stage = .processing
        let fileAudio = session.store.audioURL(of: book, fileIndex: fileIndex)
        // The processor works in FILE-LOCAL time.
        let origin = fileBounds.start
        let localSpan = CaptureSpan.Span(start: span.start - origin, end: span.end - origin)
        Task {
            do {
                var output = try await QuoteCaptureProcessor().process(
                    bookAudio: fileAudio,
                    span: localSpan,
                    bookDuration: fileBounds.length
                )
                output.spanStart += origin
                output.spanEnd += origin
                guard let memoID = MemoSaver().saveQuoteCapture(
                    audioTempURL: output.audioURL,
                    quote: output.quote,
                    duration: output.duration,
                    wordTimings: output.wordTimings,
                    bookTitle: book.title,
                    bookAuthor: book.author,
                    bookChapter: book.chapterNumberString(at: output.spanStart)
                ) else {
                    cleanupBuffer(output: output)
                    throw QuoteCaptureError.noSpeech
                }
                Haptics.success()
                stage = .sheet(memoID: memoID, output: output)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                stage = .adjust
            }
        }
    }

    /// Clean up the buffer audio file that the processor left alive for the
    /// trim sheet. Called on every exit path (save, discard, error).
    private func cleanupBuffer(output: QuoteCaptureOutput) {
        try? FileManager.default.removeItem(at: output.bufferAudioURL)
    }

    /// Close the flow. The book resumes ONLY when asked ("Save & keep
    /// listening" / cancel-resume paths) — never behind the user's back.
    private func finish(resume: Bool, output: QuoteCaptureOutput) {
        cleanupBuffer(output: output)
        if resume { session.play() }
        dismiss()
    }

    /// Before any ramble: drop the capture memo (audio + sidecars included)
    /// and resume the book.
    private func discard(memoID: UUID, output: QuoteCaptureOutput) {
        cleanupBuffer(output: output)
        let repository = NotesRepository.shared
        if let memo = repository.memo(id: memoID) {
            repository.permanentlyDelete(memo)
        }
        session.play()
        dismiss()
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
