import SwiftUI

// MARK: - Scale (shared)

// The 10-step scale itself is the SHARED `SignificanceScale`
// (Shared/Model/SignificanceScale.swift) — one copy for both apps, since the
// scale gates phone→Mac sync and must never drift. Only the phone-specific
// flag-to-send microcopy lives here, next to the view that shows it.
extension SignificanceScale {
    /// Flag-to-process microcopy. CloudKit mirrors EVERY memo regardless of
    /// rating — what the rating gates is the Mac's pipeline pickup
    /// (`MemoCloudIngest`): 0 = the Mac ignores it, >0 = polish, 0.8+ =
    /// polish + refine pass. The copy must not claim sync behavior.
    static func syncCopy(forStep step: Int) -> String {
        if step == 0 { return "Not flagged — the Mac will leave it alone" }
        if isRefine(step: step) { return "Flagged for a refine pass" }
        return "Flagged — the Mac will polish this"
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
    /// Past-the-wall warm fill — FILLS only; warm text is plain skAmber (one color
    /// with the flame tag, Tuur 2026-07-16). DARK = the mock's accent+amber mix;
    /// LIGHT = plain amber — the mix reads as dirty brown on white (same rule as
    /// the Mac, device-found 2026-07-16).
    private static let warmFill = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: (124 * 0.42 + 245 * 0.58) / 255,
                      green: (107 * 0.42 + 158 * 0.58) / 255,
                      blue: (245 * 0.42 + 11 * 0.58) / 255, alpha: 1)
            : UIColor(red: 217 / 255, green: 119 / 255, blue: 6 / 255, alpha: 1)   // skAmber light
    })

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
                                 : isRefine ? Color.skAmber : Color.skAccent)
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

    /// Flag-to-process: 0 = the Mac ignores it, >0 = polish, 0.8+ = refine flag.
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
