import SwiftUI

/// Mock state 3 — the capture moment: the book is paused and the proposed span
/// [now − 30 s → now] sits on a ~75 s micro-scrubber window (now − 60 → now + 15).
/// Drag IN/OUT to adjust; audio grains play under your finger (snippet
/// scrubbing, v1 of the locked design). The sentence-snap itself happens after
/// Confirm, on the span transcription's word timings — both edges move OUTWARD
/// so sloppy markers always yield whole sentences.
struct CaptureMomentView: View {
    let book: Audiobook
    let audioURL: URL
    /// The pause position when Capture fired.
    let now: TimeInterval
    @Binding var span: CaptureSpan.Span
    var onCancel: () -> Void
    var onConfirm: () -> Void

    private enum HandleSide { case inMarker, outMarker }

    @State private var bars: [Float] = SpanWaveform.placeholder(count: Self.barCount)
    @State private var grain = GrainPlayer()
    @State private var scrubbing: HandleSide?
    @State private var lastGrainAt = Date.distantPast

    private static let barCount = 88

    private var window: CaptureSpan.Span {
        CaptureSpan.window(now: now, duration: book.duration)
    }

    var body: some View {
        VStack(spacing: 12) {
            CapturePausedRow(book: book, pausedAt: now)

            spanCard

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 14)
        .task {
            grain.prepare(url: audioURL)
            let w = window
            bars = await SpanWaveform.bars(url: audioURL, start: w.start, end: w.end, count: Self.barCount)
        }
        .onDisappear { grain.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-moment")
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

    /// "now −30 s → now" / "now −41 s → now +4 s".
    private var relativeLabel: String {
        let back = Int((now - span.start).rounded())
        let ahead = Int((span.end - now).rounded())
        let lead = "now −\(max(0, back)) s → "
        return lead + (ahead > 0 ? "now +\(ahead) s" : "now")
    }

    // MARK: - Zoom context (where the window sits in the chapter)

    private var zoomContext: some View {
        GeometryReader { geo in
            let scope = scopeBounds
            let scopeLength = max(0.1, scope.end - scope.start)
            let posX = geo.size.width * CGFloat((now - scope.start) / scopeLength)
            let winL = geo.size.width * CGFloat((window.start - scope.start) / scopeLength)
            let winR = geo.size.width * CGFloat((window.end - scope.start) / scopeLength)

            ZStack(alignment: .topLeading) {
                // The chapter bar + played fill + the zoom window box.
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

                Text("ZOOMED · ~15 S GRAIN")
                    .font(.system(size: 8, weight: .medium))
                    .kerning(0.4)
                    .foregroundStyle(Color.skTextFaint)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: 12)
            }
        }
        .accessibilityHidden(true)
    }

    /// The zoom bar's range: the current chapter, or the whole book.
    private var scopeBounds: (start: TimeInterval, end: TimeInterval) {
        guard let chapter = book.chapter(at: now) else { return (0, max(0.1, book.duration)) }
        return (chapter.start, min(book.duration, chapter.start + max(0.1, chapter.duration)))
    }

    // MARK: - The strip (waveform + region + handles)

    private var strip: some View {
        GeometryReader { geo in
            let w = window
            let length = max(0.1, w.end - w.start)
            let inX = geo.size.width * CGFloat((span.start - w.start) / length)
            let outX = geo.size.width * CGFloat((span.end - w.start) / length)
            let nowX = geo.size.width * CGFloat((now - w.start) / length)

            ZStack(alignment: .topLeading) {
                // Waveform background.
                RoundedRectangle.sk(10).fill(Color.skElev)
                HStack(alignment: .center, spacing: 1) {
                    ForEach(bars.indices, id: \.self) { i in
                        let t = w.start + (Double(i) + 0.5) / Double(bars.count) * length
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

                // Selected region tint.
                Rectangle()
                    .fill(Color.skAccent.opacity(0.13))
                    .frame(width: max(0, outX - inX), height: 64)
                    .offset(x: inX)
                    .allowsHitTesting(false)

                // Where Capture fired.
                Rectangle()
                    .fill(.white.opacity(0.55))
                    .frame(width: 1.5, height: 72)
                    .offset(x: nowX, y: -4)
                    .allowsHitTesting(false)

                handle(side: .inMarker, x: inX, in: geo)
                handle(side: .outMarker, x: outX, in: geo)
            }
            .coordinateSpace(name: Self.stripSpace)
        }
        .frame(height: 64)
    }

    private static let stripSpace = "capture-strip"

    private func handle(side: HandleSide, x: CGFloat, in geo: GeometryProxy) -> some View {
        let w = window
        let length = max(0.1, w.end - w.start)
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
        .offset(x: x - 8, y: -14)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.stripSpace))
                .onChanged { value in
                    scrubbing = side
                    // The drag location in the STRIP's space (not the moving
                    // handle's own space — translation against a moving anchor
                    // would double-count).
                    let fraction = value.location.x / max(1, geo.size.width)
                    let raw = w.start + Double(fraction) * length
                    let t: TimeInterval
                    if side == .inMarker {
                        // Keep ≥1 s of span; the outer max guards tiny files
                        // where span.end − 1 would fall before the window.
                        t = min(max(w.start, raw), max(w.start, span.end - 1))
                        span.start = t
                    } else {
                        t = max(min(w.end, raw), min(w.end, span.start + 1))
                        span.end = t
                    }
                    if Date().timeIntervalSince(lastGrainAt) > 0.35 {
                        lastGrainAt = Date()
                        grain.playGrain(at: t)
                    }
                }
                .onEnded { _ in
                    scrubbing = nil
                    // The settle grain — hear exactly where the marker landed.
                    grain.playGrain(at: side == .inMarker ? span.start : span.end, length: 0.6)
                }
        )
        .accessibilityIdentifier(side == .inMarker ? "capture-handle-in" : "capture-handle-out")
        .accessibilityLabel(side == .inMarker
            ? "In marker — drag; snaps earlier to the sentence start"
            : "Out marker — drag; snaps later to the sentence end")
    }

    private var stripLabels: some View {
        let w = window
        let back = Int((now - w.start).rounded())
        let ahead = Int((w.end - now).rounded())
        return HStack {
            Text("−\(back) s")
            Spacer()
            Text("now").fontWeight(.semibold).foregroundStyle(Color.skTextDim)
            if ahead > 0 {
                Spacer()
                Text("+\(ahead) s")
            }
        }
        .font(.system(size: 9.5))
        .monospacedDigit()
        .foregroundStyle(Color.skTextFaint)
        .accessibilityHidden(true)
    }

    private var grainChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "music.note")
                .font(.system(size: 9))
            Text(scrubbing != nil ? "♪ playing grain…" : "audio grains play as you scrub")
                .font(.system(size: 10))
        }
        .foregroundStyle(scrubbing != nil ? Color.skAccentText : Color.skTextFaint)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(
            scrubbing != nil ? Color.skAccentSoft : Color.skElev.opacity(0.6),
            in: .capsule
        )
        .accessibilityIdentifier("capture-grain-chip")
    }
}
