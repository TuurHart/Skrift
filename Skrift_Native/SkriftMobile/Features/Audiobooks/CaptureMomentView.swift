import SwiftUI

/// Mock state 3 — the capture moment: the book is paused and the proposed span
/// [now − 30 s → now] sits on a ~75 s micro-scrubber window. Drag IN/OUT to
/// adjust; audio grains play under your finger (snippet scrubbing, v1 of the
/// locked design). The window is PANNABLE: drag the strip background to scroll
/// it earlier/later through the file, or drag a handle past the strip's edge
/// and the window follows (edge-bump) — so IN can land well before the
/// proposed 30 s. The sentence-snap itself happens after Confirm, on the span
/// transcription's word timings — both edges move OUTWARD so sloppy markers
/// always yield whole sentences.
///
/// Gesture design (the device-test fix): each handle owns its OWN generous
/// ≥44 pt hit target with a single `DragGesture` bound to THAT handle, placed
/// with `.position` so the hit area always sits exactly under the visible
/// handle (the old `.contentShape` AFTER `.offset` left both hit rectangles
/// stacked at the strip's corner — grabbing "near IN" actually started OUT's
/// gesture). A `CaptureScrub.Latch` claims the handle on the drag's FIRST
/// change and never re-evaluates mid-drag; clamping (`CaptureScrub.dragged`)
/// keeps the handles from crossing. All pure math is unit-tested.
struct CaptureMomentView: View {
    let book: Audiobook
    /// The audio FILE `now` falls in (multi-file books play file-per-chapter).
    let audioURL: URL
    /// The pause position when Capture fired (GLOBAL book time).
    let now: TimeInterval
    /// GLOBAL bounds of that file — the span and the pannable window are
    /// confined to ONE file (single-file books: the whole book).
    let bounds: CaptureSpan.Span
    @Binding var span: CaptureSpan.Span
    var onCancel: () -> Void
    var onConfirm: () -> Void

    @State private var bars: [Float]
    @State private var grain = GrainPlayer()
    @State private var latch = CaptureScrub.Latch()
    @State private var lastActive: CaptureScrub.Handle = .outMarker
    @State private var lastGrainAt = Date.distantPast
    /// The visible slice of the file — pannable state, seeded around `now`.
    @State private var window: CaptureSpan.Span
    /// Window at the start of a background pan (deltas apply to this anchor,
    /// not the live window — re-anchoring per move would compound).
    @State private var panAnchor: CaptureSpan.Span?

    private static let barCount = 88
    /// The per-handle hit target — comfortably past the 44 pt minimum.
    private static let handleHitWidth: CGFloat = 56
    private static let stripSpace = "capture-strip"

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
        _window = State(initialValue: CaptureSpan.window(now: now, in: bounds))
        _bars = State(initialValue: SpanWaveform.placeholder(count: Self.barCount))
    }

    var body: some View {
        VStack(spacing: 12) {
            CapturePausedRow(book: book, pausedAt: now)

            spanCard

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 14)
        .task { grain.prepare(url: audioURL) }
        .task(id: barsKey) {
            // Re-read the waveform whenever the window settles somewhere new
            // (pan / edge-bump). Reads only the visible slice, off the main
            // actor; a superseded read is simply replaced by the next.
            let w = window
            bars = await SpanWaveform.bars(
                url: audioURL,
                start: w.start - bounds.start,
                end: w.end - bounds.start,
                count: Self.barCount
            )
        }
        .onDisappear { grain.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-moment")
    }

    /// Quantized window key so the bars reload once per settled position, not
    /// on every sub-pixel pan tick.
    private var barsKey: String {
        "\(Int((window.start * 2).rounded()))-\(Int((window.end * 2).rounded()))"
    }

    // MARK: - Span card

    private var spanCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Proposed span")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.skTextFaint)
                Spacer()
                Text(relativeLabel)
                    .font(.system(size: 11.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.skAccentText)
                    .accessibilityIdentifier("capture-span-relative")
            }
            .padding(.bottom, 10)

            zoomContext
                .frame(height: 30)
                .padding(.horizontal, 2)

            strip
                .padding(.top, 16)
                .padding(.horizontal, 2)

            stripLabels
                .padding(.top, 5)
                .padding(.horizontal, 2)

            HStack(alignment: .center) {
                grainChip
                Spacer()
                Text("handles **snap outward**\nto whole sentences")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.skTextFaint)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.top, 9)
            .padding(.horizontal, 2)

            HStack(alignment: .firstTextBaseline) {
                readoutText
                Spacer()
                Text("\(Int(span.length.rounded())) s · whole sentences")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.skTextDim)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Color.skElev, in: .capsule)
                    .accessibilityIdentifier("capture-span-length")
            }
            .padding(.top, 12)
            .padding(.horizontal, 2)

            HStack(spacing: 8) {
                Button {
                    onCancel()
                } label: {
                    Text("Cancel · resume")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.skTextDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(RoundedRectangle.sk(11).stroke(Color.skBorder, lineWidth: 1))
                }
                .accessibilityIdentifier("capture-cancel")

                Button {
                    onConfirm()
                } label: {
                    Text("Confirm capture ❝")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.skAccent, in: .rect(cornerRadius: 11, style: .continuous))
                        .shadow(color: Color.skAccent.opacity(0.4), radius: 5, y: 1)
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("capture-confirm")
            }
            .padding(.top, 13)
        }
        .padding(EdgeInsets(top: 14, leading: 13, bottom: 13, trailing: 13))
        .background(Color.skSurface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// "12:05 → 12:38" with the arrow dimmed.
    private var readoutText: Text {
        let time = { (t: TimeInterval) -> Text in
            Text(AudiobookTime.clock(t))
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.skText)
        }
        let arrow = Text(" → ")
            .font(.system(size: 14))
            .foregroundStyle(Color.skTextFaint)
        return time(span.start) + arrow + time(span.end)
    }

    /// "now −30 s → now" / "now −41 s → now +4 s" (signed both ways — IN can
    /// be panned to either side of the pause point).
    private var relativeLabel: String {
        nowOffsetLabel(span.start) + " → " + nowOffsetLabel(span.end)
    }

    private func nowOffsetLabel(_ t: TimeInterval) -> String {
        let delta = Int((t - now).rounded())
        if delta == 0 { return "now" }
        return delta < 0 ? "now −\(-delta) s" : "now +\(delta) s"
    }

    // MARK: - Zoom context (where the window sits in the pannable range)

    private var zoomContext: some View {
        GeometryReader { geo in
            let scopeLength = max(0.1, bounds.length)
            let clamp = { (x: CGFloat) in min(max(0, x), geo.size.width) }
            let posX = clamp(geo.size.width * CGFloat((now - bounds.start) / scopeLength))
            let winL = clamp(geo.size.width * CGFloat((window.start - bounds.start) / scopeLength))
            let winR = clamp(geo.size.width * CGFloat((window.end - bounds.start) / scopeLength))

            ZStack(alignment: .topLeading) {
                // The file bar + played fill + the zoom window box.
                Capsule().fill(Color.skBorder)
                    .frame(height: 4)
                    .offset(y: 2)
                Capsule().fill(Color.skAccent.opacity(0.35))
                    .frame(width: max(2, posX), height: 4)
                    .offset(y: 2)
                RoundedRectangle.sk(3)
                    .fill(Color.skAccent.opacity(0.25))
                    .overlay(RoundedRectangle.sk(3).stroke(Color.skAccent, lineWidth: 1))
                    .frame(width: max(6, winR - winL), height: 10)
                    .offset(x: winL, y: -1)

                // The zoom cone down to the strip.
                Path { p in
                    p.move(to: CGPoint(x: winL, y: 9))
                    p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    p.move(to: CGPoint(x: winR, y: 9))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                }
                .stroke(Color.skAccent.opacity(0.35), lineWidth: 1)

                Text("ZOOMED · DRAG STRIP TO PAN")
                    .font(.system(size: 8, weight: .medium))
                    .kerning(0.4)
                    .foregroundStyle(Color.skTextFaint)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: 12)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - The strip (waveform + region + handles)

    private var strip: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let inX = xPosition(of: span.start, width: width)
            let outX = xPosition(of: span.end, width: width)
            let nowVisible = now >= window.start && now <= window.end

            ZStack(alignment: .topLeading) {
                // Waveform background — also the PAN surface.
                waveform
                    .contentShape(Rectangle())
                    .gesture(panGesture(width: width))

                // Selected region tint.
                Rectangle()
                    .fill(Color.skAccent.opacity(0.13))
                    .frame(width: max(0, outX - inX), height: 64)
                    .offset(x: inX)
                    .allowsHitTesting(false)

                // Where Capture fired (hidden once panned out of view).
                if nowVisible {
                    Rectangle()
                        .fill(.white.opacity(0.55))
                        .frame(width: 1.5, height: 72)
                        .offset(x: xPosition(of: now, width: width), y: -4)
                        .allowsHitTesting(false)
                }

                handle(.inMarker, x: inX, width: width)
                handle(.outMarker, x: outX, width: width)
            }
            .coordinateSpace(name: Self.stripSpace)
        }
        .frame(height: 64)
    }

    private var waveform: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle.sk(10).fill(Color.skElev)
            HStack(alignment: .center, spacing: 1) {
                ForEach(bars.indices, id: \.self) { i in
                    let t = window.start + (Double(i) + 0.5) / Double(bars.count) * max(0.1, window.length)
                    let inRegion = t >= span.start && t <= span.end
                    RoundedRectangle(cornerRadius: 1)
                        .fill(inRegion ? Color.skAccent.opacity(0.75) : Color.skTextFaint.opacity(0.35))
                        .frame(height: max(4, CGFloat(bars[i]) * 54))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 2)
            .frame(height: 64)
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
        }
    }

    /// A handle's x on the strip, pinned to the edges when its time has been
    /// panned out of the window (still grabbable there — dragging edge-bumps
    /// the window back toward it).
    private func xPosition(of t: TimeInterval, width: CGFloat) -> CGFloat {
        let raw = width * CGFloat((t - window.start) / max(0.1, window.length))
        return min(max(0, raw), width)
    }

    private func handle(_ side: CaptureScrub.Handle, x: CGFloat, width: CGFloat) -> some View {
        let isOffWindow = side == .inMarker
            ? span.start < window.start - 0.01 || span.start > window.end + 0.01
            : span.end < window.start - 0.01 || span.end > window.end + 0.01
        return VStack(spacing: 1) {
            Text(side == .inMarker ? "IN" : "OUT")
                .font(.system(size: 8, weight: .heavy))
                .kerning(0.6)
                .foregroundStyle(Color.skAccentText)
            RoundedRectangle.sk(6)
                .fill(Color.skAccent)
                .frame(width: 16, height: 70)
                .overlay(
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white.opacity(0.75))
                        .frame(width: 2, height: 18)
                )
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        }
        .opacity(isOffWindow ? 0.45 : 1)
        // The generous hit target sits exactly under the visible handle:
        // `.position` (not `.offset`) so layout, rendering AND hit-testing
        // agree — `.contentShape` after `.offset` left the hit rectangle at
        // the strip's corner, which is what made OUT grab IN-side touches.
        .frame(width: Self.handleHitWidth, height: 96)
        .contentShape(Rectangle())
        .position(x: x, y: 26)
        .zIndex(zIndex(for: side))
        .gesture(handleDrag(side, width: width))
        .accessibilityIdentifier(side == .inMarker ? "capture-handle-in" : "capture-handle-out")
        .accessibilityLabel(side == .inMarker
            ? "In marker — drag; snaps earlier to the sentence start"
            : "Out marker — drag; snaps later to the sentence end")
    }

    /// The dragging handle always wins hit-testing; otherwise the last-touched
    /// one stays on top (matters only when the two hit areas overlap on a
    /// short span).
    private func zIndex(for side: CaptureScrub.Handle) -> Double {
        if latch.active == side { return 3 }
        return lastActive == side ? 2 : 1
    }

    private func handleDrag(_ side: CaptureScrub.Handle, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.stripSpace))
            .onChanged { value in
                // Latch on the first change — which handle this drag moves is
                // decided ONCE, never re-evaluated mid-drag.
                guard latch.claim(side) else { return }
                lastActive = side
                // The drag location in the STRIP's space (not the moving
                // handle's own space — translation against a moving anchor
                // would double-count). Unclamped: past the edge it drives the
                // edge-bump pan below.
                let raw = CaptureScrub.time(
                    atX: value.location.x, stripWidth: width, window: window
                )
                window = CaptureScrub.panned(toInclude: raw, window: window, bounds: bounds)
                span = CaptureScrub.dragged(span, handle: side, to: raw, bounds: bounds)
                let t = side == .inMarker ? span.start : span.end
                if Date().timeIntervalSince(lastGrainAt) > 0.35 {
                    lastGrainAt = Date()
                    grain.playGrain(at: t - bounds.start)
                }
            }
            .onEnded { _ in
                let owned = latch.active == side
                latch.release(side)
                guard owned else { return }
                // The settle grain — hear exactly where the marker landed
                // (grain times are file-local).
                grain.playGrain(
                    at: (side == .inMarker ? span.start : span.end) - bounds.start,
                    length: 0.6
                )
            }
    }

    /// Drag the strip background to pan the window through the file — IN can
    /// then be placed well before the proposed 30 s (and OUT past it).
    private func panGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.stripSpace))
            .onChanged { value in
                guard latch.active == nil else { return }   // a handle owns the touch
                let anchor = panAnchor ?? window
                if panAnchor == nil { panAnchor = anchor }
                // Content follows the finger: dragging right shows EARLIER audio.
                let delta = -Double(value.translation.width / max(1, width)) * anchor.length
                window = CaptureScrub.pan(anchor, by: delta, bounds: bounds)
            }
            .onEnded { _ in panAnchor = nil }
    }

    private var stripLabels: some View {
        let nowVisible = now > window.start + 0.5 && now < window.end - 0.5
        return HStack {
            Text(edgeLabel(window.start))
            Spacer()
            if nowVisible {
                Text("now").fontWeight(.semibold).foregroundStyle(Color.skTextDim)
                Spacer()
            }
            Text(edgeLabel(window.end))
        }
        .font(.system(size: 9.5))
        .monospacedDigit()
        .foregroundStyle(Color.skTextFaint)
        .accessibilityHidden(true)
    }

    /// A window edge relative to the pause point: "−60 s" / "+15 s".
    private func edgeLabel(_ t: TimeInterval) -> String {
        let delta = Int((t - now).rounded())
        return delta <= 0 ? "−\(-delta) s" : "+\(delta) s"
    }

    private var grainChip: some View {
        let scrubbing = latch.active != nil
        return HStack(spacing: 5) {
            Image(systemName: "music.note")
                .font(.system(size: 9))
            Text(scrubbing ? "♪ playing grain…" : "grains play as you scrub · drag strip to pan")
                .font(.system(size: 10))
        }
        .foregroundStyle(scrubbing ? Color.skAccentText : Color.skTextFaint)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(
            scrubbing ? Color.skAccentSoft : Color.skElev.opacity(0.6),
            in: .capsule
        )
        .accessibilityIdentifier("capture-grain-chip")
    }
}
