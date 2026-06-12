import SwiftUI

/// Mock state 4 — the capture sheet over the dimmed player: the snapped quote
/// in italics with SENTENCE-LEVEL TRIM (one grey context sentence on each side;
/// tap grey to include; tap a bright EDGE to drop; middles refuse), a plain
/// attribution PREVIEW, the BIG record-your-thoughts button, "Save & keep
/// listening", and the significance circles.
///
/// Trim is LOCKED once a ramble exists — the audio span and quote text are
/// derived from the included sentences, so allowing further trim after a ramble
/// would make the ramble refer to a different span than the saved audio.
struct CaptureSheetView: View {
    let book: Audiobook
    let output: QuoteCaptureOutput
    let memoID: UUID
    /// Close-and-save. `resume: true` restarts the book ("Save & keep
    /// listening"); `false` keeps it paused (only "Save & keep listening"
    /// restarts the book).
    var onFinish: (_ resume: Bool) -> Void
    /// Before any ramble: delete the capture memo + resume.
    var onDiscard: () -> Void

    @ObservedObject private var session = AudiobookSession.shared
    @State private var significance: Double = 0
    @State private var showRamble = false
    @State private var rambleAdded = false
    /// The capture's memo (a SwiftData `@Model`, so Observation re-renders
    /// this sheet when the appended ramble's transcription lands).
    @State private var memo: Memo?

    // MARK: - Sentence-trim state

    /// Per-sentence inclusion flags — parallel to `output.bufferSentences`.
    @State private var included: [Bool] = []
    /// Brief hint shown when the user tries to drop a middle sentence.
    @State private var trimHint: String = ""
    /// Cancellable task that clears `trimHint` after 2.2 s.
    @State private var hintClearTask: Task<Void, Never>? = nil
    /// True once a ramble has been recorded — trim is locked to prevent the
    /// audio span from diverging from what the user spoke about.
    @State private var trimLocked: Bool = false

    var body: some View {
        ZStack {
            backdrop
            VStack {
                Spacer(minLength: 0)
                sheet
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .onAppear {
            memo = NotesRepository.shared.memo(id: memoID)
            if included.isEmpty {
                included = output.bufferSentences.map(\.isInInitialSpan)
            }
        }
        .fullScreenCover(isPresented: $showRamble) {
            // No auto-resume on dismiss; the book resumes only via
            // "Save & keep listening".
            RecordView(onSaved: { _ in
                rambleAdded = true
                trimLocked = true   // lock trim once a ramble lands
            }, appendTo: memoID)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-sheet")
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack {
            VStack {
                BookCoverView(book: book)
                    .frame(width: 170, height: 170)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    .padding(.top, 30)
                Spacer()
            }
            .opacity(0.45)
            .saturation(0.6)
            Color.black.opacity(0.45).ignoresSafeArea()
        }
    }

    // MARK: - Sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color.skTextFaint.opacity(0.5))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)

            header
                .padding(.bottom, 12)

            quoteBlock
                .padding(.bottom, 8)

            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 10))
                Text(metaLine)
                    .font(.system(size: 10))
            }
            .foregroundStyle(Color.skTextFaint)
            .padding(.horizontal, 2)
            .padding(.bottom, 12)

            if rambleAdded {
                rambleReview
                    .padding(.bottom, 10)
                addMoreButton
                    .padding(.bottom, 9)
            } else {
                recordButton
                    .padding(.bottom, 9)
            }

            Button {
                onFinish(true)
            } label: {
                Text("Save & keep listening")
                    .font(.system(size: 13, weight: rambleAdded ? .bold : .semibold))
                    .foregroundStyle(rambleAdded ? .white : Color.skTextDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        rambleAdded ? Color.skAccent : .clear,
                        in: .rect(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle.sk(12)
                            .stroke(rambleAdded ? .clear : Color.skBorder, lineWidth: 1)
                    )
            }
            .accessibilityIdentifier("capture-save-keep-listening")
            .padding(.bottom, 12)

            SignificanceCircles(value: $significance) {
                commitSignificance()
            }
        }
        .padding(EdgeInsets(top: 11, leading: 16, bottom: 16, trailing: 16))
        .background(Color.skSurface, in: .rect(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle.sk(22).stroke(Color.skBorder, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 24, y: -6)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            // Typographic double-turned-comma (U+275D) via escape so the
            // literal can never be mis-terminated.
            Text("\u{275D}")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    LinearGradient(colors: [Color(hex: 0x8e7dff), Color(hex: 0x6a59ef)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 7, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("Capture")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.skText)
                Text(contextLine)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.skTextFaint)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                // Once a ramble exists, the close button keeps the memo but
                // does not resume the book; "Save & keep listening" is the
                // only path that resumes.
                rambleAdded ? onFinish(false) : onDiscard()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.skTextDim)
                    .frame(width: 24, height: 24)
                    .background(Color.skElev, in: .circle)
            }
            .accessibilityIdentifier("capture-close")
            .accessibilityLabel(rambleAdded
                ? "Save and close \u{2014} the book stays paused"
                : "Discard \u{2014} resume the book")
        }
    }

    private var contextLine: String {
        var parts = [book.title]
        if let chapter = book.shortChapterLabel(at: trimmedSpanStart) { parts.append(chapter) }
        // U+00B7 middle dot, U+2192 right arrow — escape to be safe.
        parts.append(AudiobookTime.clock(trimmedSpanStart) + " \u{2192} " + AudiobookTime.clock(trimmedSpanEnd))
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Quote block with sentence-trim

    private static let quoteMaxHeight: CGFloat = 200

    private var quoteBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .vertical) {
                sentenceTrimContent
                ScrollView(.vertical, showsIndicators: true) {
                    sentenceTrimContent
                }
            }
            .frame(maxHeight: Self.quoteMaxHeight)

            // Plain attribution preview — NO [[..]] on the phone.
            attributionText
                .font(.system(size: 11.5))
                .accessibilityIdentifier("capture-attribution")

            if !trimHint.isEmpty {
                Text(trimHint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.skAmber)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity)
                    .accessibilityIdentifier("capture-trim-hint")
            }

            if trimLocked {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                    Text("trim locked \u{2014} ramble refers to this span")
                        .font(.system(size: 10))
                }
                .foregroundStyle(Color.skTextFaint)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.skAccent.opacity(0.05), in: .rect(cornerRadius: 11, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 11, bottomLeadingRadius: 11)
                .fill(Color.skAccent.opacity(0.6))
                .frame(width: 2.5)
        }
        .overlay(RoundedRectangle.sk(11).stroke(Color.skBorder, lineWidth: 0.5))
    }

    /// Render sentences as tappable inline spans, exactly per the mock:
    /// - Included sentences: bright, italic (the quote)
    /// - Context sentences (one on each side of the included window): grey
    /// - Outside the one-sentence context window: hidden
    private var sentenceTrimContent: some View {
        Group {
            if !output.bufferSentences.isEmpty && included.count == output.bufferSentences.count {
                sentenceRows
            } else {
                // Fallback when the engine returned no word timings.
                Text("\u{201C}\(output.quote)\u{201D}")
                    .font(.system(size: 13.5))
                    .italic()
                    .lineSpacing(4)
                    .foregroundStyle(Color.skText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("capture-quote-text")
            }
        }
    }

    /// The tappable sentence strip — a VStack of `TrimSentenceButton` rows.
    private var sentenceRows: some View {
        let firstIn = included.firstIndex(of: true) ?? 0
        let lastIn = included.lastIndex(of: true) ?? (included.count - 1)
        let windowStart = max(0, firstIn - 1)
        let windowEnd = min(included.count - 1, lastIn + 1)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(output.bufferSentences.indices, id: \.self) { i in
                if i >= windowStart && i <= windowEnd {
                    TrimSentenceButton(
                        text: output.bufferSentences[i].text,
                        isIn: included[i],
                        isLocked: trimLocked,
                        sentenceIndex: i
                    ) {
                        handleSentenceTap(at: i, firstIn: firstIn, lastIn: lastIn)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-quote-text")
    }

    // MARK: - Sentence-tap logic

    private func handleSentenceTap(at i: Int, firstIn: Int, lastIn: Int) {
        guard !trimLocked else { return }
        if included[i] {
            // Bright sentence tapped — only edges are droppable.
            if i == firstIn || i == lastIn {
                // Guard: never drop the last remaining included sentence.
                guard firstIn != lastIn else {
                    flashHint("at least one sentence must remain in the quote")
                    return
                }
                withAnimation(.easeInOut(duration: 0.15)) {
                    included[i] = false
                }
            } else {
                flashHint("drop from the edges \u{2014} middle sentences stay")
            }
        } else {
            // Grey context sentence tapped — include it.
            withAnimation(.easeInOut(duration: 0.15)) {
                included[i] = true
            }
        }
    }

    private func flashHint(_ message: String) {
        hintClearTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) { trimHint = message }
        hintClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { trimHint = "" }
        }
    }

    // MARK: - Derived span & quote text

    private var activeSentences: [BufferSentence] {
        guard included.count == output.bufferSentences.count else {
            return output.bufferSentences.filter(\.isInInitialSpan)
        }
        return zip(output.bufferSentences, included).filter(\.1).map(\.0)
    }

    private var trimmedSpanStart: TimeInterval {
        activeSentences.first.map { output.bufferOffset + $0.start } ?? output.spanStart
    }

    private var trimmedSpanEnd: TimeInterval {
        activeSentences.last.map { output.bufferOffset + $0.end } ?? output.spanEnd
    }

    // MARK: - Attribution

    /// "— David Deutsch, *The Beginning of Infinity*, ch. 4" — plain (the Mac
    /// writes the [[..]] wikilink at export).
    private var attributionText: Text {
        // U+2014 em dash
        let lead = Text("\u{2014} \(book.author), ").foregroundStyle(Color.skTextDim)
        let title = Text(book.title).italic().foregroundStyle(Color.skTextDim)
        let tail = Text(chapterSuffix).foregroundStyle(Color.skTextDim)
        return lead + title + tail
    }

    private var chapterSuffix: String {
        if let n = book.chapterNumberString(at: trimmedSpanStart) { return ", ch. \(n)" }
        return ""
    }

    private var metaLine: String {
        let dur = max(0, trimmedSpanEnd - trimmedSpanStart)
        // U+00B7 middle dot
        return AudiobookTime.clock(dur)
            + " of book audio attached \u{00B7} transcribed on-device, snapped to sentences"
    }

    // MARK: - Record button

    private var recordButton: some View {
        Button {
            showRamble = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mic")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.18), in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Record your thoughts")
                        .font(.system(size: 14.5, weight: .bold))
                    // U+2014 em dash
                    Text("the book stays paused while you talk \u{2014} review, then resume")
                        .font(.system(size: 10.5))
                        .opacity(0.75)
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16))
            .background(
                LinearGradient(colors: [Color(hex: 0x8e7dff), Color(hex: 0x6a59ef)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 14, style: .continuous)
            )
            .shadow(color: Color.skAccent.opacity(0.5), radius: 7, y: 2)
        }
        .accessibilityIdentifier("capture-record-thoughts")
    }

    // MARK: - Post-ramble review

    private var rambleReview: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.skGreen)
                // U+2014 em dash
                Text("YOUR THOUGHTS \u{2014} SAVED")
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(Color.skTextDim)
            }

            switch rambleState {
            case .transcribing:
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    // U+2026 ellipsis
                    Text("Transcribing what you said\u{2026}")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.skTextDim)
                }
            case .failed:
                Text("Transcription failed \u{2014} the audio is saved on the memo and can be retried there.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.skAmber)
            case .noSpeech:
                Text("No speech was recognized \u{2014} try Add more.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.skTextDim)
            case .text(let body):
                ScrollView(.vertical, showsIndicators: true) {
                    Text(body)
                        .font(.system(size: 12.5))
                        .lineSpacing(3)
                        .foregroundStyle(Color.skText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.skGreen.opacity(0.05), in: .rect(cornerRadius: 11, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 11, bottomLeadingRadius: 11)
                .fill(Color.skGreen.opacity(0.55))
                .frame(width: 2.5)
        }
        .overlay(RoundedRectangle.sk(11).stroke(Color.skBorder, lineWidth: 0.5))
        .accessibilityIdentifier("capture-ramble-review")
    }

    private enum RambleState {
        case transcribing, failed, noSpeech
        case text(String)
    }

    private var rambleState: RambleState {
        guard let memo else { return .transcribing }
        if memo.transcriptStatus == .transcribing { return .transcribing }
        if memo.transcriptStatus == .failed { return .failed }
        if let body = QuoteFormatting.rambleBody(transcript: memo.transcript ?? "") {
            return .text(body)
        }
        return .noSpeech
    }

    private var addMoreButton: some View {
        Button {
            showRamble = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "mic").font(.system(size: 11, weight: .medium))
                Text("Add more").font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(Color.skAccentText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .overlay(RoundedRectangle.sk(11).stroke(Color.skAccent.opacity(0.45), lineWidth: 1))
        }
        .accessibilityIdentifier("capture-record-thoughts")
        .accessibilityLabel("Add more thoughts \u{2014} the book stays paused")
    }

    // MARK: - Significance

    private func commitSignificance() {
        let repository = NotesRepository.shared
        guard let memo = repository.memo(id: memoID) else { return }
        memo.significance = significance
        repository.save()
    }
}

// MARK: - TrimSentenceButton

/// One tappable sentence in the capture sheet's trim strip. Extracted to its
/// own view so the parent VStack body can call the action closure without
/// needing a mutating context.
private struct TrimSentenceButton: View {
    let text: String
    let isIn: Bool
    let isLocked: Bool
    let sentenceIndex: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            // Trailing space keeps inline flow natural when sentences wrap.
            Text(text + " ")
                .font(.system(size: 13.5))
                .italic(isIn)
                .foregroundStyle(isIn ? Color.skText : Color.skTextFaint)
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isIn
            ? "capture-sentence-in-\(sentenceIndex)"
            : "capture-sentence-ctx-\(sentenceIndex)")
    }
}
