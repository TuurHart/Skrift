import SwiftUI

// MARK: - Scale (pure logic, unit-tested)

/// The 10-step importance scale behind the circle control
/// (`mocks/significance-circles.html`). One circle = 0.1; tier boundaries are
/// 0.4 / 0.7 (Passing · Useful · Important) and 0.8+ is past the **refine
/// wall** — those notes get a refine pass on the Mac. Kept separate from the
/// view so the mapping/copy is testable without UIKit. (User-facing label is
/// "Importance"; the internal symbols stay `Significance*` / `significance`.)
enum SignificanceScale {
    static let stepCount = 10
    /// First step past the refine wall: 0.8+ notes get a refine pass.
    static let refineStep = 8

    /// `memo.significance` (0 / 0.1…1.0) → its circle step (0…10), clamped.
    static func step(for value: Double) -> Int {
        min(stepCount, max(0, Int((value * 10).rounded())))
    }

    /// Circle step → the stored significance value (0 / 0.1…1.0).
    static func value(forStep step: Int) -> Double {
        Double(min(stepCount, max(0, step))) / 10
    }

    /// Star-rating toggle: tapping the already-set circle clears to 0 (Not
    /// rated); tapping any other circle sets that rating.
    static func toggling(_ value: Double, tappedStep: Int) -> Double {
        step(for: value) == tappedStep ? 0 : self.value(forStep: tappedStep)
    }

    static func isRefine(step: Int) -> Bool { step >= refineStep }

    /// Tier name for a set step (1…10). Boundaries 0.4 / 0.7 per the mock.
    /// User-facing label is "Importance" (Phase-3 relabel of "significance"); the
    /// top tier reads "Important" to match. Internal symbols stay `Significance*`.
    static func tierName(forStep step: Int) -> String {
        step >= 7 ? "Important" : step >= 4 ? "Useful" : "Passing"
    }

    /// The live value label: "Not rated" / "0.5 · Useful" / "1.0 · Important".
    static func label(forStep step: Int) -> String {
        guard step > 0 else { return "Not rated" }
        return (step == stepCount ? "1.0" : "0.\(step)") + " · " + tierName(forStep: step)
    }

    /// Flag-to-send microcopy: 0 = stays on the phone, >0 = syncs, 0.8+ =
    /// syncs + flagged for a refine pass.
    static func syncCopy(forStep step: Int) -> String {
        if step == 0 { return "Stays on this phone — rate to flag for sync" }
        if isRefine(step: step) { return "Will sync · flagged for a refine pass" }
        return "Will sync to the Mac"
    }
}

// MARK: - The card (signed-off mock: significance-circles.html, iOS panel)

/// The 10-circle significance control — replaces the drag slider. Tap circle N
/// → circles 1…N fill and `memo.significance` = 0.N; re-tap the set circle →
/// back to 0 (Not rated). The faint amber hairline before circle 8 is the
/// refine wall; at 0.8+ all three wall cues show (user-approved): the wall
/// tick, warm-tinted fills on lit circles 8–10, and the flame "refine pass"
/// tag. Below a divider, the flag-to-send line spells out what the rating
/// means for sync.
struct SignificanceCircles: View {
    @Binding var value: Double
    var onCommit: () -> Void

    /// Visual constants (the mock keeps these as "one constant — easy to
    /// flip"): 18pt circles / 6pt gaps instead of the mock's 19/9 so the row +
    /// the inline flame tag fit inside the card on a 390pt phone.
    private static let circleSize: CGFloat = 18
    private static let gap: CGFloat = 6
    private static let wallWidth: CGFloat = 1
    /// Tier-label cluster widths, sized to the circle clusters (1–3 / 4–6 /
    /// 7–10 incl. the wall) like the mock.
    private static let smallCluster = 3 * circleSize + 2 * gap
    private static let largeCluster = 4 * circleSize + 4 * gap + wallWidth

    /// Unlit circle ring — the mock's 20% hairline, adaptive.
    private static let ring = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.22)
                                       : UIColor(white: 0, alpha: 0.18)
    })
    /// Past-the-wall warm tones (mock: oklab color-mix of accent + amber).
    private static let warmFill = Color.skAccent.mix(with: .skAmber, by: 0.58)
    private static let warmText = Color.skAccent.mix(with: .skAmber, by: 0.5)

    private var step: Int { SignificanceScale.step(for: value) }
    private var isRefine: Bool { SignificanceScale.isRefine(step: step) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            circlesRow
                .padding(.top, 9)
            tierLabels
                .padding(.top, 7)
            Rectangle()
                .fill(Color.skBorder)
                .frame(height: 0.5)
                .padding(.top, 11)
                .padding(.bottom, 9)
            syncLine
        }
        .padding(EdgeInsets(top: 13, leading: 13, bottom: 12, trailing: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.skSurface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
        // .contain scopes the card as its own AX container — without it, this
        // identifier propagates DOWN and overwrites every child's identifier
        // (the circle buttons all reported 'significance-circles', breaking
        // XCUITest queries for significance-circle-N).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("significance-circles")
    }

    // MARK: Rows

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Importance")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.skTextFaint)
            Spacer(minLength: 8)
            Text(SignificanceScale.label(forStep: step))
                .font(.system(size: 11.5, weight: step == 0 ? .medium : .semibold))
                .monospacedDigit()
                .foregroundStyle(step == 0 ? Color.skTextFaint
                                 : isRefine ? Self.warmText : Color.skAccent)
                .accessibilityIdentifier("significance-value")
        }
    }

    private var circlesRow: some View {
        HStack(spacing: Self.gap) {
            ForEach(1...SignificanceScale.stepCount, id: \.self) { i in
                if i == SignificanceScale.refineStep { refineWall }
                circle(i)
            }
            Spacer(minLength: Self.gap)
            flameTag
                .opacity(isRefine ? 1 : 0)         // mock keeps its space, fades in
                .accessibilityHidden(!isRefine)
        }
        .animation(Theme.Motion.snappy, value: step)
    }

    private func circle(_ i: Int) -> some View {
        let lit = i <= step
        let warm = lit && isRefine && i >= SignificanceScale.refineStep
        return Button {
            Haptics.tap(.light)
            withAnimation(Theme.Motion.snappy) {
                value = SignificanceScale.toggling(value, tappedStep: i)
            }
            onCommit()
        } label: {
            Circle()
                .fill(warm ? Self.warmFill : lit ? Color.skAccent : Color.clear)
                .overlay(
                    Circle().strokeBorder(
                        warm ? Self.warmFill : lit ? Color.skAccent : Self.ring,
                        lineWidth: 1.5)
                )
                .shadow(color: lit ? (warm ? Color.skAmber : Color.skAccent).opacity(0.3) : .clear,
                        radius: 2.5, y: 1)
                .frame(width: Self.circleSize, height: Self.circleSize)
                // Taller hit area than the 18pt glyph (the row is the touch zone).
                .frame(height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("significance-circle-\(i)")
        .accessibilityLabel("Importance \(SignificanceScale.label(forStep: i))")
        .accessibilityAddTraits(lit ? .isSelected : [])
    }

    /// The always-visible refine wall: a faint amber hairline before circle 8.
    private var refineWall: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Color.skAmber.opacity(0.35))
            .frame(width: Self.wallWidth, height: Self.circleSize + 5)
            .accessibilityHidden(true)
    }

    /// The tiny flame "refine pass" tag, right-aligned on the circles row.
    private var flameTag: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .bold))
            Text("REFINE PASS")
                .font(.system(size: 9, weight: .bold))
                .kerning(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color.skAmber)
        .accessibilityIdentifier("significance-refine-flag")
        .accessibilityLabel("Refine pass — rated 0.8 or higher")
    }

    /// Faint group labels under the circle clusters that light up with the rating.
    private var tierLabels: some View {
        HStack(spacing: Self.gap) {
            tierLabel("PASSING", width: Self.smallCluster, active: step >= 1 && step <= 3, warm: false)
            tierLabel("USEFUL", width: Self.smallCluster, active: step >= 4 && step <= 6, warm: false)
            tierLabel("IMPORTANT", width: Self.largeCluster, active: step >= 7, warm: isRefine)
        }
        .animation(Theme.Motion.snappy, value: step)
        .accessibilityHidden(true)   // decorative — each circle already says its tier
    }

    private func tierLabel(_ text: String, width: CGFloat, active: Bool, warm: Bool) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .kerning(0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(active ? (warm ? Color.skAmber : Color.skAccent) : Color.skTextFaint)
            .frame(width: width)
    }

    /// Flag-to-send: 0 = stays on the phone, >0 = syncs, 0.8+ = syncs + refine flag.
    private var syncLine: some View {
        HStack(spacing: 6) {
            if isRefine {
                Image(systemName: "flame.fill").font(.system(size: 9, weight: .bold))
            } else {
                Circle()
                    .fill(step == 0 ? Color.skTextFaint : Color.skGreen)
                    .frame(width: 6, height: 6)
            }
            Text(SignificanceScale.syncCopy(forStep: step))
                .font(.system(size: 10.5))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(step == 0 ? Color.skTextFaint : isRefine ? Color.skAmber : Color.skTextDim)
        .accessibilityIdentifier("significance-sync-line")
    }
}
