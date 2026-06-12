import SwiftUI

// MARK: - Observable model for the Hybrid capture adjust screen

/// All mutable state for the Hybrid capture adjust screen, isolated to the
/// main actor so that AVPlayer time-observer callbacks — which fire on the main
/// queue — can write directly to published properties without value-type
/// capture-snapshot pitfalls.
@MainActor
final class CaptureAdjustModel: ObservableObject {
    // MARK: Published state

    @Published var window: CaptureSpan.Span
    @Published var playhead: TimeInterval
    @Published var isPlaying = false
    @Published var inMark: TimeInterval?
    @Published var outMark: TimeInterval?
    @Published var bars: [Float]
    @Published var playbackRate: Double = 1.5
    @Published var statusHint = ""
    @Published var playingSpan = false

    // MARK: Private

    let player = CapturePreviewPlayer()
    private var timeObserverToken: Any?

    static let availableRates: [Double] = [1.0, 1.5, 2.0]
    static let barCount = 88

    // MARK: Init

    init(now: TimeInterval, bounds: CaptureSpan.Span) {
        let w = CaptureSpan.replayWindow(now: now, in: bounds)
        self.window = w
        self.playhead = w.start
        self.bars = SpanWaveform.placeholder(count: Self.barCount)
    }

    // MARK: - Lifecycle

    func prepareAndAutoplay(audioURL: URL, bounds: CaptureSpan.Span) {
        player.prepare(url: audioURL)
        player.rate = playbackRate
        player.play(from: window.start - bounds.start)
        isPlaying = true
        installTimeObserver(bounds: bounds)
    }

    private func installTimeObserver(bounds: CaptureSpan.Span) {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        // Capture `self` weakly to avoid a retain cycle. `self` is @MainActor
        // and the handler is called on the main queue — the explicit MainActor
        // hop in the handler is therefore immediate (no scheduling overhead).
        timeObserverToken = player.addPeriodicTimeObserver(interval: 1.0 / 30.0) { [weak self] t in
            guard let self else { return }
            let globalT = t + bounds.start
            self.playhead = min(globalT, bounds.end)
            let nowPlaying = self.player.isPlaying
            if self.isPlaying != nowPlaying { self.isPlaying = nowPlaying }
            if self.playingSpan, let out = self.outMark, globalT >= out {
                self.player.pause()
                self.isPlaying = false
                self.playingSpan = false
            }
        }
    }

    func tearDown() {
        player.stop()
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    // MARK: - Transport actions

    func togglePlayPause(bounds: CaptureSpan.Span) {
        if isPlaying {
            player.pause()
            isPlaying = false
            playingSpan = false
        } else {
            player.play(from: playhead - bounds.start)
            isPlaying = true
        }
    }

    func skipBack(bounds: CaptureSpan.Span) {
        let (newTime, extend) = CaptureMath.applySkip(
            playheadTime: playhead, delta: -5, window: window, bounds: bounds
        )
        if extend {
            window = CaptureMath.extendWindowLeft(window: window, bounds: bounds)
            playhead = window.start
            player.play(from: window.start - bounds.start)
            isPlaying = true
            statusHint = "Extended to \(AudiobookTime.clock(window.start))"
        } else {
            playhead = newTime
            playingSpan = false
            player.play(from: newTime - bounds.start)
            isPlaying = true
        }
    }

    func skipForward(bounds: CaptureSpan.Span) {
        let (newTime, _) = CaptureMath.applySkip(
            playheadTime: playhead, delta: +5, window: window, bounds: bounds
        )
        playhead = newTime
        playingSpan = false
        player.play(from: newTime - bounds.start)
        isPlaying = true
    }

    func cycleRate() {
        let current = Self.availableRates.firstIndex(of: playbackRate) ?? 0
        let idx = (current + 1) % Self.availableRates.count
        playbackRate = Self.availableRates[idx]
        player.rate = playbackRate
    }

    // MARK: - Mark actions

    func placeInMark(bounds: CaptureSpan.Span) {
        let mark = CaptureMath.placeInMark(
            playheadTime: playhead, isPlaying: isPlaying, bounds: bounds
        )
        inMark = mark
        if let out = outMark, out < mark + CaptureMath.minimumSpan {
            outMark = mark + CaptureMath.minimumSpan
        }
        statusHint = "IN set · snaps outward to a sentence on Continue"
    }

    func placeOutMark(bounds: CaptureSpan.Span) {
        let mark = CaptureMath.placeOutMark(
            playheadTime: playhead, isPlaying: isPlaying, inMark: inMark, bounds: bounds
        )
        outMark = mark
        statusHint = "OUT set · snaps outward to a sentence on Continue"
    }

    func nudgeIn(delta: TimeInterval, current: TimeInterval, bounds: CaptureSpan.Span) {
        let newIn = CaptureMath.nudgeInMark(
            current: current, delta: delta, outMark: outMark, bounds: bounds
        )
        inMark = newIn
        // IN chip: (re)play from the new in-mark — works while already playing.
        let seekTarget = CaptureMath.inChipSeekTarget(newInMark: newIn)
        playingSpan = false
        player.play(from: seekTarget - bounds.start)
        isPlaying = true
    }

    func nudgeOut(delta: TimeInterval, current: TimeInterval, bounds: CaptureSpan.Span) {
        let newOut = CaptureMath.nudgeOutMark(
            current: current, delta: delta, inMark: inMark, bounds: bounds
        )
        outMark = newOut
        // OUT chip: replay the last ~5 s up to the new out-mark.
        let seekTarget = CaptureMath.outChipSeekTarget(newOutMark: newOut, inMark: inMark)
        playingSpan = true
        player.play(from: seekTarget - bounds.start)
        isPlaying = true
    }

    func replayPass(now: TimeInterval, bounds: CaptureSpan.Span) {
        inMark = nil
        outMark = nil
        statusHint = ""
        playingSpan = false
        window = CaptureSpan.replayWindow(now: now, in: bounds)
        playhead = window.start
        player.play(from: window.start - bounds.start)
        isPlaying = true
    }

    func playSpan(bounds: CaptureSpan.Span) {
        guard let inM = inMark else { return }
        playingSpan = true
        playhead = inM
        player.play(from: inM - bounds.start)
        isPlaying = true
    }

    // MARK: - Helpers

    var rateLabel: String {
        let r = playbackRate
        if r == 1.0 { return "1" }
        if r == 1.5 { return "1.5" }
        if r == 2.0 { return "2" }
        return String(format: "%.1f", r)
    }
}

// MARK: - View

/// Hybrid capture adjust screen (signed off 2026-06-12).
///
/// ONE screen, ONE playhead — play/paused is the only state:
///
/// ENTRY — the screen auto-plays the book audio from pausePoint−45 s at 1.5×.
/// The waveform strip shows that window. The amber tick marks the pause point.
/// Real playback IS the audio feedback — no grains, no separate gain graph.
///
/// TRANSPORT — ⟲5 · ▶/⏸ · 5⟳ row centered; rate pill (1×/1.5×/2×) pinned
/// right. Tapping the strip seeks the playhead there.
///
/// MARK — "「 Mark In" and "Mark Out 」" drop flags AT the playhead: −0.7 s
/// reaction bias while playing, exact while paused. Re-tap moves the flag.
/// OUT clamps ≥ IN + 1 s.
///
/// FINE-TUNE — once a flag is set, ±1 s chips appear. An IN chip nudges the
/// mark AND IMMEDIATELY (re)plays from the new in-mark — works while already
/// playing, no pause needed. An OUT chip nudges and replays the last ~5 s up
/// to the new out-mark.
///
/// ⟲5 past the strip's left edge extends the window back by 45 s (clamped to
/// the chapter file start).
///
/// "▶ Play span" plays in → out and stops.
/// "↻ Replay" restarts the −45 s pass (clears marks).
///
/// Continue → existing confirm path (sentence-snap OUTWARD on confirm lives
/// downstream in `QuoteCaptureFlowView`/`QuoteCaptureProcessor`; untouched).
struct CaptureMomentView: View {
    let book: Audiobook
    /// The audio FILE `now` falls in (multi-file books: one file per chapter).
    let audioURL: URL
    /// The pause position when Capture fired (GLOBAL book time).
    let now: TimeInterval
    /// GLOBAL bounds of that file — the strip and every seek are confined to
    /// this one file. Single-file books: the whole book.
    let bounds: CaptureSpan.Span
    @Binding var span: CaptureSpan.Span
    var onCancel: () -> Void
    var onConfirm: () -> Void

    @StateObject private var model: CaptureAdjustModel

    private static let barCount = 88
    private static let stripHeight: CGFloat = 64

    init(
        book: Audiobook,
        audioURL: URL,
        now: TimeInterval,
        bounds: CaptureSpan.Span,
        span: Binding<CaptureSpan.Span>,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.book = book
        self.audioURL = audioURL
        self.now = now
        self.bounds = bounds
        _span = span
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _model = StateObject(wrappedValue: CaptureAdjustModel(now: now, bounds: bounds))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            CapturePausedRow(book: book, pausedAt: now)

            adjustCard
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("capture-moment")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 14)
        .task { model.prepareAndAutoplay(audioURL: audioURL, bounds: bounds) }
        .task(id: barsKey) { await reloadBars() }
        .onDisappear { model.tearDown() }
    }

    // MARK: - Waveform bars

    /// Quantized key — reload only when the window moves by ≥ 0.5 s.
    private var barsKey: String {
        "\(Int((model.window.start * 2).rounded()))-\(Int((model.window.end * 2).rounded()))"
    }

    private func reloadBars() async {
        let w = model.window
        let result = await SpanWaveform.bars(
            url: audioURL,
            start: w.start - bounds.start,
            end: w.end - bounds.start,
            count: Self.barCount
        )
        model.bars = result
    }

    // MARK: - Adjust card

    private var adjustCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.bottom, 10)

            strip
                .padding(.bottom, 4)

            stripLabels
                .padding(.bottom, 12)

            transportRow
                .padding(.bottom, 12)

            markRow
                .padding(.bottom, 10)

            chipRow
                .padding(.bottom, 4)

            hintText
                .padding(.bottom, 10)

            statusLine
                .padding(.bottom, 12)

            ctaRow

            // Cancel / resume — escape hatch below the primary CTA.
            Button {
                model.tearDown()
                onCancel()
            } label: {
                Text("Cancel · resume")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.skTextFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .overlay(RoundedRectangle.sk(11).stroke(Color.skBorder, lineWidth: 1))
            }
            .padding(.top, 6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("capture-cancel")
        }
        .padding(EdgeInsets(top: 14, leading: 13, bottom: 13, trailing: 13))
        .background(Color.skSurface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.isPlaying ? "replaying · \(model.rateLabel)×" : "paused")
                .font(.system(size: 11))
                .foregroundStyle(model.isPlaying ? Color.skAccentText : Color.skTextFaint)
            Spacer()
            if let inMark = model.inMark, let outMark = model.outMark {
                Text(AudiobookTime.clock(inMark) + " → " + AudiobookTime.clock(outMark))
                    .font(.system(size: 11.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.skAccentText)
                    .accessibilityIdentifier("capture-span-times")
            }
        }
    }

    // MARK: - Strip

    private var strip: some View {
        GeometryReader { geo in
            let cgWidth = geo.size.width
            let w = Double(cgWidth)
            ZStack(alignment: .topLeading) {
                waveform(stripWidth: w)

                // Amber tick at the pause point.
                let nowX = CaptureMath.xPosition(of: now, stripWidth: w, window: model.window)
                if nowX >= 0, nowX <= w {
                    Rectangle()
                        .fill(Color.skAmber.opacity(0.7))
                        .frame(width: 1.5, height: Self.stripHeight + 8)
                        .offset(x: nowX, y: -4)
                        .allowsHitTesting(false)
                }

                // Span tint between marks.
                if let inM = model.inMark, let outM = model.outMark, outM > inM {
                    let inX = max(0.0, CaptureMath.xPosition(of: inM, stripWidth: w, window: model.window))
                    let outX = min(w, CaptureMath.xPosition(of: outM, stripWidth: w, window: model.window))
                    if outX > inX {
                        Rectangle()
                            .fill(Color.skAccent.opacity(0.18))
                            .frame(width: outX - inX, height: Self.stripHeight)
                            .offset(x: inX)
                            .allowsHitTesting(false)
                    }
                }

                // IN flag.
                if let inM = model.inMark {
                    flagView(label: "「", time: inM, stripWidth: w)
                }

                // OUT flag.
                if let outM = model.outMark {
                    flagView(label: "」", time: outM, stripWidth: w)
                }

                // White playhead.
                let phX = CaptureMath.xPosition(of: model.playhead, stripWidth: w, window: model.window)
                let clampedPHX = max(0.0, min(w, phX))
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: Self.stripHeight + 4)
                    .shadow(color: .white.opacity(0.5), radius: 4)
                    .offset(x: clampedPHX, y: -2)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let t = CaptureMath.time(atX: Double(location.x), stripWidth: w, window: model.window)
                let clamped = max(bounds.start, min(bounds.end, t))
                model.playhead = clamped
                model.playingSpan = false
                model.player.play(from: clamped - bounds.start)
                model.isPlaying = true
            }
        }
        .frame(height: Self.stripHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-strip")
    }

    private func waveform(stripWidth: Double) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle.sk(10).fill(Color.skElev)
            HStack(alignment: .center, spacing: 1) {
                ForEach(model.bars.indices, id: \.self) { i in
                    let t = model.window.start + (Double(i) + 0.5)
                        / Double(max(1, model.bars.count)) * model.window.length
                    let inSpan = (model.inMark.map { t >= $0 } ?? false)
                        && (model.outMark.map { t <= $0 } ?? false)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(inSpan ? Color.skAccent.opacity(0.7) : Color.skTextFaint.opacity(0.3))
                        .frame(height: max(4, CGFloat(model.bars[i]) * 54))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 2)
            .frame(height: Self.stripHeight)
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
        }
    }

    private func flagView(label: String, time: TimeInterval, stripWidth: Double) -> some View {
        let x = CaptureMath.xPosition(of: time, stripWidth: stripWidth, window: model.window)
        let clampedX = max(0, min(stripWidth, x))
        return VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color.skAccentText)
            Rectangle()
                .fill(Color.skAccent)
                .frame(width: 2, height: Self.stripHeight - 10)
        }
        .offset(x: clampedX - 1, y: 0)
        .allowsHitTesting(false)
    }

    // MARK: - Strip labels

    private var stripLabels: some View {
        HStack {
            Text(AudiobookTime.clock(model.window.start))
            Spacer()
            Text("⏸ " + AudiobookTime.clock(now))
                .fontWeight(.semibold)
                .foregroundStyle(Color.skAmber.opacity(0.8))
            Spacer()
            Text(AudiobookTime.clock(model.window.end))
        }
        .font(.system(size: 9.5))
        .monospacedDigit()
        .foregroundStyle(Color.skTextFaint)
        .accessibilityHidden(true)
    }

    // MARK: - Transport row

    private var transportRow: some View {
        ZStack {
            // Centered transport buttons.
            HStack(spacing: 10) {
                transportButton(label: "⟲5", accessibilityID: "capture-skip-back") {
                    model.skipBack(bounds: bounds)
                }
                playPauseButton
                transportButton(label: "5⟳", accessibilityID: "capture-skip-forward") {
                    model.skipForward(bounds: bounds)
                }
            }

            // Rate pill pinned to the right — absolutely overlaid so the
            // transport buttons stay visually centered.
            HStack {
                Spacer()
                Button {
                    model.cycleRate()
                } label: {
                    Text(model.rateLabel + "×")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.skTextDim)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.skElev, in: .capsule)
                        .overlay(Capsule().stroke(Color.skBorder, lineWidth: 1))
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("capture-rate")
                .accessibilityLabel("Playback rate: \(model.rateLabel)×. Tap to change.")
            }
        }
    }

    private var playPauseButton: some View {
        Button {
            model.togglePlayPause(bounds: bounds)
        } label: {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Color.skAccent, in: Circle())
                .shadow(color: Color.skAccent.opacity(0.4), radius: 6, y: 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-play")
        .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
    }

    private func transportButton(label: String, accessibilityID: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.skText)
                .frame(width: 46, height: 46)
                .background(Color.skElev, in: Circle())
                .overlay(Circle().stroke(Color.skBorder, lineWidth: 1))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityID)
    }

    // MARK: - Mark row

    private var markRow: some View {
        HStack(spacing: 10) {
            markButton(
                label: "「 Mark In",
                isSet: model.inMark != nil,
                accessibilityID: "capture-mark-in"
            ) {
                model.placeInMark(bounds: bounds)
            }

            markButton(
                label: "Mark Out 」",
                isSet: model.outMark != nil,
                accessibilityID: "capture-mark-out"
            ) {
                model.placeOutMark(bounds: bounds)
            }
        }
    }

    private func markButton(
        label: String,
        isSet: Bool,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(isSet ? Color.white : Color.skAccentText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    isSet ? Color.skAccent : Color.skAccentSoft,
                    in: .rect(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle.sk(12).stroke(Color.skAccent, lineWidth: 1)
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel(isSet ? "\(label): set. Tap to move here." : "\(label)")
    }

    // MARK: - ±1s chip row

    private var chipRow: some View {
        HStack(spacing: 6) {
            if let inM = model.inMark {
                chipButton(label: "「 −1s", accessibilityID: "capture-chip-in-minus") {
                    model.nudgeIn(delta: -1, current: inM, bounds: bounds)
                }
                chipButton(label: "「 +1s", accessibilityID: "capture-chip-in-plus") {
                    model.nudgeIn(delta: +1, current: inM, bounds: bounds)
                }
            }
            if let outM = model.outMark {
                chipButton(label: "」 −1s", accessibilityID: "capture-chip-out-minus") {
                    model.nudgeOut(delta: -1, current: outM, bounds: bounds)
                }
                chipButton(label: "」 +1s", accessibilityID: "capture-chip-out-plus") {
                    model.nudgeOut(delta: +1, current: outM, bounds: bounds)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(minHeight: 28)
    }

    private func chipButton(label: String, accessibilityID: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.skTextDim)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.skElev, in: .capsule)
                .overlay(Capsule().stroke(Color.skBorder, lineWidth: 1))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityID)
    }

    // MARK: - Hint + status

    private var hintText: some View {
        Text("Marking while playing lands 0.7 s earlier (reaction bias) · while paused, exactly at the playhead · re-tap to move a flag")
            .font(.system(size: 10))
            .foregroundStyle(Color.skTextFaint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var statusLine: some View {
        Group {
            if model.statusHint.isEmpty {
                Color.clear
            } else {
                Text(model.statusHint)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.skGreen)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-status")
    }

    // MARK: - CTA row

    private var ctaRow: some View {
        HStack(spacing: 8) {
            Button {
                model.replayPass(now: now, bounds: bounds)
            } label: {
                Text("↻ Replay")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.skTextDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .overlay(RoundedRectangle.sk(11).stroke(Color.skBorder, lineWidth: 1))
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("capture-replay")

            Button {
                model.playSpan(bounds: bounds)
            } label: {
                Text("▶ Play span")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(model.inMark != nil ? Color.skText : Color.skTextFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .overlay(RoundedRectangle.sk(11).stroke(Color.skBorder, lineWidth: 1))
            }
            .disabled(model.inMark == nil)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("capture-play-span")

            Button {
                guard let inM = model.inMark, let outM = model.outMark else { return }
                span = CaptureSpan.Span(start: inM, end: outM)
                model.tearDown()
                onConfirm()
            } label: {
                let ready = model.inMark != nil && model.outMark != nil
                Text("Continue →")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(ready ? Color.white : Color.skTextFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        ready ? Color.skAccent : Color.skElev,
                        in: .rect(cornerRadius: 11, style: .continuous)
                    )
            }
            .disabled(model.inMark == nil || model.outMark == nil)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("capture-confirm")
        }
    }
}
