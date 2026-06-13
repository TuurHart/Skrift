import SwiftUI
import AVFoundation

// MARK: - Pure selection + span logic (host-testable, no SwiftUI)

/// Contiguous sentence selection for text-capture (mock `text-capture.html`).
/// Every grey line shows "+"; tapping any extends the quote to cover it; tapping
/// a selected END line drops it. Pure so the rules are unit-tested without a view.
struct TextCaptureSelection: Equatable {
    var lo: Int
    var hi: Int

    /// Apply a tap on sentence `i`; returns a short status (or nil). Mutates lo/hi.
    mutating func tap(_ i: Int) -> String? {
        if i < lo { lo = i; return "added — \(count) lines" }
        if i > hi { hi = i; return "added — \(count) lines" }
        if lo == hi { return "this is your quote — tap a + line to add more" }
        if i == lo { lo += 1; return "dropped the top line" }
        if i == hi { hi -= 1; return "dropped the bottom line" }
        return "tap an end line (✕) to shorten"
    }

    var count: Int { hi - lo + 1 }
    func isSelected(_ i: Int) -> Bool { i >= lo && i <= hi }
    func isEdge(_ i: Int) -> Bool { hi > lo && (i == lo || i == hi) }
}

enum TextCaptureMath {
    /// GLOBAL book span for the selected sentence range. `sentences[*].start/end`
    /// are window-local; add `windowStart` (file-local) then `fileOrigin`
    /// (global) — the inverse of what `QuoteCaptureFlowView.confirmCapture` undoes.
    static func globalSpan(sentences: [BufferSentence], lo: Int, hi: Int,
                           windowStart: TimeInterval, fileOrigin: TimeInterval) -> CaptureSpan.Span? {
        guard sentences.indices.contains(lo), sentences.indices.contains(hi), lo <= hi else { return nil }
        return CaptureSpan.Span(
            start: sentences[lo].start + windowStart + fileOrigin,
            end:   sentences[hi].end   + windowStart + fileOrigin
        )
    }
}

// MARK: - View

/// Text-first quote capture (the A/B alternative to `CaptureMomentView`). Shows
/// the last ~90 s of narration as tappable sentences; the user builds a quote by
/// tapping. On confirm it emits a GLOBAL span that the flow runs through the SAME
/// `QuoteCaptureProcessor`/sheet path as the audio mode — downstream untouched.
struct TextCaptureView: View {
    let book: Audiobook
    let audioURL: URL?
    /// GLOBAL playhead (book paused here).
    let pausedAt: TimeInterval
    /// GLOBAL bounds of the file `pausedAt` falls in (origin = `.start`).
    let fileBounds: CaptureSpan.Span
    /// Called with a GLOBAL span when the user confirms a quote.
    let onConfirm: (CaptureSpan.Span) -> Void
    let onCancel: () -> Void

    private enum LoadState {
        case loading
        case ready(QuoteCaptureProcessor.WindowTranscript)
        case empty
    }

    @State private var state: LoadState = .loading
    @State private var sel = TextCaptureSelection(lo: 0, hi: 0)
    @State private var touched = false
    @State private var toast = ""
    @State private var toastColor: Color = .skTextDim
    @State private var previewPlayer: AVAudioPlayer?

    // Window in FILE-LOCAL time: [playhead − 90 s … playhead], clamped to the file.
    private var windowEndLocal: TimeInterval { min(max(0, pausedAt - fileBounds.start), fileBounds.length) }
    private var windowStartLocal: TimeInterval { max(0, windowEndLocal - 90) }

    var body: some View {
        VStack(spacing: 0) {
            nav
            switch state {
            case .loading:  warming
            case .empty:    emptyState
            case .ready(let w): selectBody(w)
            }
        }
        .background(Color.skBg.ignoresSafeArea())
        .task { await load() }
        .onDisappear {
            previewPlayer?.stop()
            if case .ready(let w) = state { try? FileManager.default.removeItem(at: w.bufferURL) }
        }
        .accessibilityIdentifier("text-capture")
    }

    // MARK: Nav

    private var nav: some View {
        HStack(spacing: 10) {
            Button { previewPlayer?.stop(); onCancel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.skTextDim)
                    .frame(width: 30, height: 30)
                    .background(Color.skElev, in: .circle)
            }
            .accessibilityIdentifier("text-capture-cancel")
            VStack(alignment: .leading, spacing: 1) {
                Text(book.title).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.skText).lineLimit(1)
                if let ch = book.shortChapterLabel(at: pausedAt) {
                    Text(ch).font(.system(size: 11)).foregroundStyle(Color.skTextDim).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 15).padding(.bottom, 8)
    }

    // MARK: States

    private var warming: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Getting this bit…").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.skText)
            Text("A couple of seconds — only the first time this session.")
                .font(.system(size: 12)).foregroundStyle(Color.skTextDim)
                .multilineTextAlignment(.center).padding(.horizontal, 36)
            Spacer()
        }
        .accessibilityIdentifier("text-capture-warming")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "speaker.slash").font(.system(size: 28)).foregroundStyle(Color.skTextFaint)
            Text("Nothing to quote here").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.skText)
            Text("This stretch is music or a pause — no words to grab.")
                .font(.system(size: 12)).foregroundStyle(Color.skTextDim)
                .multilineTextAlignment(.center).padding(.horizontal, 36)
            Button { onCancel() } label: {
                Text("← Back to the book").font(.system(size: 13.5, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(Color.skAccent, in: .rect(cornerRadius: 11, style: .continuous))
            }
            .padding(.top, 4)
            .accessibilityIdentifier("text-capture-empty-back")
            Spacer()
        }
        .accessibilityIdentifier("text-capture-empty")
    }

    private func selectBody(_ w: QuoteCaptureProcessor.WindowTranscript) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Build your quote.").font(.system(size: 14.5, weight: .bold)).foregroundStyle(Color.skText)
                Text("We grabbed the line you just heard — scroll, tap + to add the ones around it.")
                    .font(.system(size: 11.5)).foregroundStyle(Color.skTextDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 7) {
                        Text("— start of chapter —")
                            .font(.system(size: 10.5)).foregroundStyle(Color.skTextFaint)
                            .frame(maxWidth: .infinity).padding(.vertical, 2)
                            .opacity(windowStartLocal <= 0.5 ? 1 : 0)
                        ForEach(Array(w.sentences.enumerated()), id: \.offset) { i, s in
                            sentenceRow(i, s.text)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                }
                .onAppear { withAnimation { proxy.scrollTo(sel.hi, anchor: .center) } }
            }

            Text(toast).font(.system(size: 11.5)).foregroundStyle(toastColor)
                .frame(maxWidth: .infinity).frame(minHeight: 16).padding(.top, 4)

            footer(w)
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
        .accessibilityIdentifier("text-capture-sentence-\(i)")
    }

    private func footer(_ w: QuoteCaptureProcessor.WindowTranscript) -> some View {
        VStack(spacing: 8) {
            Button { preview(w) } label: {
                Text("▶ Hear selection · 1.5×").font(.system(size: 12)).foregroundStyle(Color.skAccent)
            }
            .accessibilityIdentifier("text-capture-preview")
            Button { confirm(w) } label: {
                Text("Use as quote (\(sel.count) line\(sel.count > 1 ? "s" : "")) →")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(touched ? .white : Color.skAccent)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(touched ? Color.skAccent : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.skAccent.opacity(touched ? 0 : 0.55), lineWidth: 1)
                    )
            }
            .accessibilityIdentifier("text-capture-use")
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 18)
        .background(Color.skSurface.ignoresSafeArea(edges: .bottom).overlay(alignment: .top) {
            Rectangle().fill(Color.skBorder).frame(height: 0.5)
        })
    }

    // MARK: Actions

    private func load() async {
        guard let audioURL else { state = .empty; return }
        guard windowEndLocal - windowStartLocal >= 1 else { state = .empty; return }
        do {
            let w = try await QuoteCaptureProcessor().transcribeWindowForDisplay(
                bookAudio: audioURL, windowStart: windowStartLocal, windowEnd: windowEndLocal)
            guard !w.sentences.isEmpty else { state = .empty; return }
            let last = w.sentences.count - 1
            sel = TextCaptureSelection(lo: last, hi: last)   // pre-pick the line you just heard
            state = .ready(w)
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

    private func confirm(_ w: QuoteCaptureProcessor.WindowTranscript) {
        guard let span = TextCaptureMath.globalSpan(
            sentences: w.sentences, lo: sel.lo, hi: sel.hi,
            windowStart: w.windowStart, fileOrigin: fileBounds.start) else { return }
        previewPlayer?.stop()
        onConfirm(span)
    }

    /// Play the selected span from `bufferURL` at 1.5× (window-local times = buffer-local).
    private func preview(_ w: QuoteCaptureProcessor.WindowTranscript) {
        guard sel.lo < w.sentences.count, sel.hi < w.sentences.count else { return }
        let start = w.sentences[sel.lo].start
        let end = w.sentences[sel.hi].end
        do {
            let p = try AVAudioPlayer(contentsOf: w.bufferURL)
            p.enableRate = true
            p.rate = 1.5
            p.currentTime = start
            p.prepareToPlay()
            p.play()
            previewPlayer = p
            toast = "▶ playing your \(sel.count)-line selection at 1.5×…"; toastColor = .skAccent
            let dur = max(0.1, (end - start) / 1.5)
            DispatchQueue.main.asyncAfter(deadline: .now() + dur) { [weak p] in p?.stop() }
        } catch {
            // Preview is non-essential; silently ignore (the quote audio is exact regardless).
        }
    }
}
