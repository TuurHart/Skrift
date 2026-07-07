import SwiftUI

/// The merged audiobook capture screen — ONE note-style screen (signed-off mock
/// `mocks/audiobook-capture-merged.html`, 2026-06-13). It replaces the old
/// two-step flow (select-sentences screen → capture sheet) with the note layout:
///
///   header (❝ + book · chapter)  →  significance (the real SignificanceCircles)
///   →  build-your-quote body (tappable sentence rows)  →  Record your thoughts (pinned)
///
/// Text capture is the only flow now (the audio mark-in/out arm is retired), so
/// this works even on an un-chunked spot: it reads the wave-2 sidecar when the
/// book is transcribed (instant) and otherwise transcribes the window live.
///
/// BUILD-YOUR-QUOTE is bidirectional but BOUNDED (2026-06-14): the line you just
/// heard is the pre-picked anchor, parked in the MIDDLE, with the ~90 s you heard
/// BEFORE it and a few lines AFTER it — scroll up to quote earlier, down to quote
/// a little later (past the tap; the post-pause audio exists, the book is paused).
/// The forward reach is capped (8 lines on a transcribed book, 4 on an un-chunked
/// spot) — no infinite scroll.
///
/// ALWAYS records voice — a quote alone isn't a capture. Tapping "Record your
/// thoughts" carves the quote from the selection, creates the memo, applies the
/// significance, then opens the recorder; afterwards the book auto-resumes and
/// the capture lands as the normal note (no preview/review step — the ramble
/// transcribes in the background via the fire-and-forget `MemoSaver.appendRecording`).
struct MergedCaptureView: View {
    let book: Audiobook
    let audioURL: URL?
    /// Which file of the book `pausedAt` falls in — for the sidecar lookup.
    let fileIndex: Int
    /// GLOBAL playhead (book paused here).
    let pausedAt: TimeInterval
    /// GLOBAL bounds of the file `pausedAt` falls in (origin = `.start`).
    let fileBounds: CaptureSpan.Span
    /// Resume the book + dismiss the flow. Called on cancel and after the ramble.
    let onFinish: () -> Void

    /// Where the shown sentences came from (mirrors the retired `TextCaptureView`):
    /// a pre-transcribed spot is read from the sidecar (instant), else a wave-1
    /// live window transcribe.
    private enum Source {
        case window(QuoteCaptureProcessor.WindowTranscript)
        case sidecar([BufferSentence])
        var sentences: [BufferSentence] {
            switch self {
            case .window(let w): return w.sentences
            case .sidecar(let s): return s
            }
        }
    }

    private enum LoadState { case loading, ready(Source), empty }

    /// How many lines past the tap are selectable — bigger when transcribed (free
    /// from the sidecar), smaller un-chunked (each costs live transcription).
    private static let forwardTranscribed = 8
    private static let forwardLive = 4
    /// Seconds past the tap the live window transcribes — enough to surface
    /// `forwardLive` sentences (clamped to the file end).
    private static let liveForwardSeconds: TimeInterval = 45

    private let transcripts = BookTranscriptStore()
    @ObservedObject private var session = AudiobookSession.shared
    @State private var state: LoadState = .loading
    @State private var sel = TextCaptureSelection(lo: 0, hi: 0)
    @State private var significance: Double = 0
    @State private var touched = false
    @State private var toast = ""
    @State private var toastColor: Color = .skTextDim
    @State private var building = false
    @State private var showRamble = false
    /// Bounds of the DISPLAYED slice into `source.sentences` (the rest, further out,
    /// stay hidden — no infinite scroll). `sel` still indexes the full array.
    @State private var displayLo = 0
    @State private var displayHi = 0
    /// The memo created when "Record your thoughts" fires (so the ramble appends).
    @State private var createdMemoID: UUID?
    /// The buffer temp to clean up when the flow exits (the ±buffer audio).
    @State private var createdBufferURL: URL?
    /// True once a ramble has actually been saved — distinguishes "recorded" from
    /// "opened the recorder then cancelled" so a quote-only memo from a bail is
    /// discarded (always-records).
    @State private var rambleSaved = false
    /// True once the quote has been built + memo created — the flow now owns the
    /// window buffer; stops `onDisappear` deleting it out from under the recorder.
    @State private var handedOff = false

    // Window in FILE-LOCAL time: [playhead − 90 s … playhead], clamped to the file.
    private var windowEndLocal: TimeInterval { min(max(0, pausedAt - fileBounds.start), fileBounds.length) }
    private var windowStartLocal: TimeInterval { max(0, windowEndLocal - 90) }
    private var isReady: Bool { if case .ready = state { return true }; return false }

    var body: some View {
        VStack(spacing: 0) {
            header
            SignificanceCircles(value: $significance) { }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            content
            recordBar
        }
        .background(Color.skBg.ignoresSafeArea())
        .task { await load() }
        .onDisappear {
            // Clean the live window buffer ONLY if we left without building (the
            // sidecar path has no separate buffer; once handed off the recorder /
            // cleanupBuffer owns it).
            if !handedOff, case .ready(.window(let w)) = state {
                try? FileManager.default.removeItem(at: w.bufferURL)
            }
        }
        .fullScreenCover(isPresented: $showRamble, onDismiss: {
            // Recorder closed. The ramble append is fire-and-forget, so resume +
            // dismiss now — the capture lands as the normal note (no preview).
            cleanupBuffer()
            if !rambleSaved, let id = createdMemoID,
               let memo = NotesRepository.shared.memo(id: id) {
                // Bailed before recording — a quote alone isn't a capture; drop it.
                NotesRepository.shared.permanentlyDelete(memo)
            }
            onFinish()
        }) {
            if let id = createdMemoID {
                RecordView(onSaved: { _ in rambleSaved = true }, appendTo: id)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("merged-capture")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            // Typographic double-turned-comma (U+275D) via escape, as in the
            // retired capture sheet's header.
            Text("\u{275D}")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    LinearGradient(colors: [Color(hex: 0x8e7dff), Color(hex: 0x6a59ef)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 7, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 1) {
                // "Add note" — unified verb (user decision 2026-07-07): the capsule
                // pill, the player chip, and this screen all say the same thing.
                Text("Add note")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.skText)
                Text(contextLine)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.skTextFaint)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                // Cancel: nothing created yet → resume the book + dismiss.
                onFinish()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.skTextDim)
                    .frame(width: 24, height: 24)
                    .background(Color.skElev, in: .circle)
            }
            .accessibilityIdentifier("merged-capture-close")
            .accessibilityLabel("Cancel — resume the book")
        }
        .padding(.horizontal, 16).padding(.top, 15).padding(.bottom, 12)
    }

    private var contextLine: String {
        var parts = [book.title]
        if let ch = book.shortChapterLabel(at: pausedAt) { parts.append(ch) }
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Content (loading / empty / build-your-quote)

    @ViewBuilder private var content: some View {
        switch state {
        case .loading: warming
        case .empty:   emptyState
        case .ready(let source): selectBody(source)
        }
    }

    private var warming: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Getting this bit\u{2026}").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.skText)
            Text("A couple of seconds — only the first time this session.")
                .font(.system(size: 12)).foregroundStyle(Color.skTextDim)
                .multilineTextAlignment(.center).padding(.horizontal, 36)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("merged-capture-warming")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "speaker.slash").font(.system(size: 28)).foregroundStyle(Color.skTextFaint)
            Text("Nothing to quote here").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.skText)
            Text("This stretch is music or a pause — no words to grab.")
                .font(.system(size: 12)).foregroundStyle(Color.skTextDim)
                .multilineTextAlignment(.center).padding(.horizontal, 36)
            Button { onFinish() } label: {
                Text("\u{2190} Back to the book").font(.system(size: 13.5, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(Color.skAccent, in: .rect(cornerRadius: 11, style: .continuous))
            }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("merged-capture-empty")
    }

    private func selectBody(_ source: Source) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Build your quote.").font(.system(size: 14.5, weight: .bold)).foregroundStyle(Color.skText)
                Text("The line you just heard is highlighted — tap the lines around it to add them.")
                    .font(.system(size: 11.5)).foregroundStyle(Color.skTextDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 7) {
                        if reachesFileStart(source) {
                            Text("\u{2014} start of chapter \u{2014}")
                                .font(.system(size: 10.5)).foregroundStyle(Color.skTextFaint)
                                .frame(maxWidth: .infinity).padding(.vertical, 2)
                        }
                        // Only the bounded slice is shown (no infinite scroll); `sel`
                        // still indexes the full array, so the build path is unchanged.
                        ForEach(source.sentences.indices, id: \.self) { i in
                            if i >= displayLo && i <= displayHi {
                                sentenceRow(i, source.sentences[i].text)
                            }
                        }
                        // Plain attribution preview — NO [[..]] on the phone.
                        attributionText
                            .font(.system(size: 11.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.top, 4)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                }
                // Park the anchor (the line just heard) in the middle so there's
                // visible context above (earlier) AND below (later).
                .onAppear { withAnimation { proxy.scrollTo(sel.hi, anchor: .center) } }
            }

            Text(toast).font(.system(size: 11.5)).foregroundStyle(toastColor)
                .frame(maxWidth: .infinity).frame(minHeight: 16).padding(.top, 2)
        }
        .frame(maxHeight: .infinity)
    }

    /// True when the displayed slice reaches the file/chapter start (so the "start
    /// of chapter" marker is honest). Sidecar: the slice begins at index 0. Live:
    /// the window itself begins at the file start.
    private func reachesFileStart(_ source: Source) -> Bool {
        switch source {
        case .sidecar: return displayLo == 0
        case .window:  return windowStartLocal < 0.5
        }
    }

    private func sentenceRow(_ i: Int, _ text: String) -> some View {
        let selected = sel.isSelected(i)
        let edge = sel.isEdge(i)
        return HStack(alignment: .top, spacing: 8) {
            Text(text)
                .font(.system(size: 15.5))
                .foregroundStyle(selected ? Color.skText : Color.skTextDim)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: selected ? (edge ? "xmark.circle.fill" : "checkmark.circle.fill") : "plus.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(selected ? (edge ? Color.skTextFaint : Color.skAccent) : Color.skAccent.opacity(0.55))
                .opacity(selected && !edge ? 0.5 : 1)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.skAccent.opacity(0.16) : Color.skAccent.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.skAccent.opacity(0.55) : Color.skBorder, lineWidth: 0.5)
        )
        .id(i)
        .contentShape(Rectangle())
        .onTapGesture { tap(i) }
        .accessibilityIdentifier("merged-capture-sentence-\(i)")
    }

    /// "— David Deutsch, *The Beginning of Infinity*, ch. 4" — plain (the Mac
    /// writes the [[..]] wikilink at export).
    private var attributionText: Text {
        let lead = Text("\u{2014} \(book.author), ").foregroundStyle(Color.skTextDim)
        let title = Text(book.title).italic().foregroundStyle(Color.skTextDim)
        let suffix = book.chapterNumberString(at: pausedAt).map { ", ch. \($0)" } ?? ""
        let tail = Text(suffix).foregroundStyle(Color.skTextDim)
        return lead + title + tail
    }

    // MARK: - Record bar (pinned)

    private var recordBar: some View {
        Button {
            recordThoughts()
        } label: {
            HStack(spacing: 12) {
                if building {
                    ProgressView().controlSize(.small).frame(width: 34, height: 34)
                } else {
                    Image(systemName: "mic")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.18), in: .circle)
                }
                Text(building ? "Preparing\u{2026}" : "Record your thoughts")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16))
            .background(
                LinearGradient(colors: [Color(hex: 0x8e7dff), Color(hex: 0x6a59ef)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 14, style: .continuous)
            )
        }
        .disabled(building || !isReady)
        .opacity(isReady ? 1 : 0.45)
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 18)
        .accessibilityIdentifier("merged-capture-record")
    }

    // MARK: - Actions

    private func load() async {
        guard let audioURL else { state = .empty; return }
        let winStart = windowStartLocal, winEnd = windowEndLocal
        guard winEnd - winStart >= 1 else { state = .empty; return }

        // Transcribed book: load the covered file (file-local times); the tapped
        // line sits in the middle. Show the ~90 s before it + up to 8 lines after
        // (the rest stay hidden — no infinite scroll). Sidecar = instant.
        if let ft = transcripts.fileTranscript(bookID: book.id, fileIndex: fileIndex, audioURL: audioURL),
           ft.isCovered(upTo: winEnd) {
            let all = QuoteCaptureProcessor.buildSentences(from: ft.words, snappedStart: 0, snappedEnd: 0)
            guard !all.isEmpty else { state = .empty; return }
            let capIdx = all.lastIndex(where: { $0.start <= winEnd }) ?? (all.count - 1)
            sel = TextCaptureSelection(lo: capIdx, hi: capIdx)
            displayLo = all.firstIndex(where: { $0.start >= winStart }) ?? 0
            displayHi = min(all.count - 1, capIdx + Self.forwardTranscribed)
            state = .ready(.sidecar(all))
            return
        }

        // Un-chunked spot: transcribe a window spanning both sides of the tap
        // (~90 s back … ~45 s forward, clamped); show the ~90 s before + up to 4
        // lines after. Beyond that, transcribe the book.
        let fwdEnd = min(fileBounds.length, winEnd + Self.liveForwardSeconds)
        do {
            let w = try await QuoteCaptureProcessor().transcribeWindowForDisplay(
                bookAudio: audioURL, windowStart: winStart, windowEnd: fwdEnd)
            guard !w.sentences.isEmpty else { state = .empty; return }
            // The tap sits at (winEnd − winStart) in the window's local time.
            let capLocal = winEnd - winStart
            let capIdx = w.sentences.lastIndex(where: { $0.start <= capLocal }) ?? (w.sentences.count - 1)
            sel = TextCaptureSelection(lo: capIdx, hi: capIdx)
            displayLo = 0
            displayHi = min(w.sentences.count - 1, capIdx + Self.forwardLive)
            state = .ready(.window(w))
        } catch {
            state = .empty
        }
    }

    private func tap(_ i: Int) {
        touched = true
        if let msg = sel.tap(i) {
            toast = msg
            toastColor = msg.hasPrefix("added") ? .green : (msg.hasPrefix("dropped") ? .skTextDim : .skAmber)
        }
        Haptics.tap()
    }

    /// Build the quote from the selection, create the memo, apply the
    /// significance, then open the recorder for the ramble.
    private func recordThoughts() {
        guard !handedOff, case .ready(let source) = state else { return }
        building = true
        Task {
            do {
                let output: QuoteCaptureOutput
                switch source {
                case .window(let w):
                    output = try await QuoteCaptureProcessor().buildOutput(
                        from: w, lo: sel.lo, hi: sel.hi, fileOrigin: fileBounds.start)
                case .sidecar(let sentences):
                    guard let audioURL else { throw QuoteCaptureError.exportFailed }
                    output = try await QuoteCaptureProcessor().buildOutputFromSidecar(
                        bookAudio: audioURL, sentences: sentences, lo: sel.lo, hi: sel.hi,
                        fileOrigin: fileBounds.start)
                }
                guard let memoID = MemoSaver().saveQuoteCapture(
                    audioTempURL: output.audioURL,
                    quote: output.quote,
                    duration: output.duration,
                    wordTimings: output.wordTimings,
                    bookTitle: book.title,
                    bookAuthor: book.author,
                    bookChapter: book.chapterNumberString(at: output.spanStart),
                    // Stable back-link to the source (2026-07-06): the title/author
                    // strings break as a join key when book details are edited —
                    // the id + GLOBAL position are what a "notes for this book" /
                    // jump-back surface needs. Additive metadata; Mac ignores it.
                    bookID: book.id,
                    bookPosition: output.spanStart
                ) else {
                    building = false
                    toast = "Couldn\u{2019}t build that quote — try a different selection"; toastColor = .skAmber
                    return
                }
                handedOff = true
                // Apply the significance set on this screen.
                if let memo = NotesRepository.shared.memo(id: memoID) {
                    memo.significance = significance
                    NotesRepository.shared.save()
                }
                Haptics.success()
                createdMemoID = memoID
                createdBufferURL = output.bufferAudioURL
                building = false
                showRamble = true
            } catch {
                building = false
                toast = "Couldn\u{2019}t build that quote — try a different selection"; toastColor = .skAmber
            }
        }
    }

    private func cleanupBuffer() {
        if let url = createdBufferURL { try? FileManager.default.removeItem(at: url) }
    }
}
