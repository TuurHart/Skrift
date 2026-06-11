import SwiftUI
import AppKit

/// Pure value↔circle mapping for the 10-circle significance control (kept free of
/// SwiftUI so it stays unit-testable). Circle N ↔ 0.N — the same 0.1 snaps the old
/// slider persisted to `PipelineFile.significance`. Tier boundaries stay 0.4 / 0.7
/// (passing · useful · significant); 0.8+ crosses the "refine wall" (those notes
/// get a refine pass before export).
enum SignificanceScale {
    /// First circle past the refine wall (0.8).
    static let refineWall = 8

    /// Stored value → how many circles are lit (0 = unrated). Tolerates float noise
    /// (0.7000000001 from old slider data) and off-grid phone values by rounding;
    /// clamps BEFORE the Int conversion so an off-contract value can't trap.
    static func litCount(_ value: Double?) -> Int {
        guard let value, value.isFinite else { return 0 }
        return Int(min(10, max(0, (value * 10).rounded())))
    }

    /// Circle N → the persisted value (1 → 0.1 … 10 → 1.0).
    static func value(forCircle n: Int) -> Double { Double(n) / 10 }

    static func tierName(_ n: Int) -> String {
        n >= 7 ? "Significant" : n >= 4 ? "Useful" : "Passing"
    }

    /// "0.5 · Useful" / "1.0 · Significant" — the top-right value text.
    static func valueText(_ n: Int) -> String {
        (n == 10 ? "1.0" : "0.\(n)") + " · " + tierName(n)
    }
}

/// The 10-circle significance control — replaces the slider row per the signed-off
/// `mocks/significance-circles.html` (desktop card spec). Star-rating interaction:
/// hover previews the would-be rating, click the Nth circle sets 0.N, re-clicking
/// the set circle clears back to "Not rated" (nil — no separate × affordance).
/// The 0.8 refine wall is cued three ways at once: an always-visible amber hairline
/// before circle 8, warm-tinted fills on lit circles 8–10, and a flame
/// "refine pass" tag after the row.
struct SignificanceCircles: View {
    /// nil = the user hasn't rated this note yet (shows "Not rated", not a
    /// misleading "0.0 · Passing"). Set values are exact 0.1 snaps, byte-compatible
    /// with what the slider wrote.
    @Binding var value: Double?
    /// Disabled until the note is processed (#18 — can't rate an unprocessed note).
    var enabled: Bool = true

    /// Dot under the cursor (drives the scale-up).
    @State private var hovered: Int?
    /// Pending-value preview (drives ghost fills + the top-right label). Cleared on
    /// click so the freshly set rating paints in its real color immediately, exactly
    /// like the mock's set()→paintVal().
    @State private var preview: Int?

    private static let dotSize: CGFloat = 13
    private static let gap: CGFloat = 7

    private var lit: Int { SignificanceScale.litCount(value) }
    private var warm: Bool { lit >= SignificanceScale.refineWall }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            dotsRow.padding(.top, 9)
            tierLabels.padding(.top, 7)
        }
        .opacity(enabled ? 1 : 0.5)
    }

    // ── Label + live value (same spot as the old slider value) ──
    private var topRow: some View {
        HStack {
            Text("significance").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            Spacer()
            if !enabled {
                Text("rate after processing").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            } else if let preview {
                Text(SignificanceScale.valueText(preview))
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            } else if lit > 0 {
                Text(SignificanceScale.valueText(lit))
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(warm ? Self.warmText : Theme.accent)
            } else {
                Text("Not rated").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textMuted)
            }
        }
    }

    // ── The circles (≈200pt wide — can't be mistaken for the audio scrubber) ──
    private var dotsRow: some View {
        HStack(spacing: Self.gap) {
            ForEach(1...10, id: \.self) { i in
                if i == SignificanceScale.refineWall { wallTick }
                dot(i)
            }
            flameTag.padding(.leading, 6)
        }
        .animation(.easeOut(duration: 0.12), value: preview)
        .animation(.easeOut(duration: 0.12), value: lit)
    }

    private func dot(_ i: Int) -> some View {
        let isLit = i <= lit
        let isWarmDot = isLit && warm && i >= SignificanceScale.refineWall
        let isPreview = !isLit && preview.map { i <= $0 } == true

        let fill: Color = isWarmDot ? Self.warmFill
            : isLit ? Theme.accent
            : isPreview ? Theme.accent.opacity(0.3)
            : .clear
        let border: Color = isWarmDot ? Self.warmFill
            : isLit ? Theme.accent
            : isPreview ? Theme.accent.opacity(0.55)
            : Theme.hairline.opacity(0.2)

        return Button {
            value = lit == i ? nil : SignificanceScale.value(forCircle: i)
            preview = nil
        } label: {
            Circle()
                .fill(fill)
                .overlay(Circle().strokeBorder(border, lineWidth: 1.5))
                .frame(width: Self.dotSize, height: Self.dotSize)
                .shadow(color: isWarmDot ? Theme.amber.opacity(0.3) : isLit ? Theme.accent.opacity(0.35) : .clear,
                        radius: isWarmDot ? 4 : isLit ? 2.5 : 0,
                        y: isWarmDot ? 0 : isLit ? 1 : 0)
        }
        .buttonStyle(.plain)
        .scaleEffect(hovered == i ? 1.22 : 1)
        .animation(.easeOut(duration: 0.1), value: hovered)
        .onHover { inside in
            guard enabled else { return }
            if inside {
                hovered = i; preview = i
            } else {
                // Only clear our own marks — enter on the next dot may land first.
                if hovered == i { hovered = nil }
                if preview == i { preview = nil }
            }
        }
        .disabled(!enabled)
        .help(SignificanceScale.valueText(i))
        .accessibilityLabel("Significance \(SignificanceScale.valueText(i))")
    }

    /// Always-visible amber hairline before circle 8 — the refine wall.
    private var wallTick: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Theme.amber.opacity(0.35))
            .frame(width: 1, height: Self.dotSize + 5)
            .help("refine wall — 0.8+ notes get a refine pass")
    }

    /// Flame + "refine pass" tag after the row; fades in at 0.8+. Always laid out
    /// (opacity 0 when off) so the row width never jumps — mirrors the mock.
    private var flameTag: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill").font(.system(size: 9, weight: .bold))
            Text("REFINE PASS").font(.system(size: 9, weight: .bold)).tracking(0.54)
        }
        .foregroundStyle(Theme.amber)
        .fixedSize()
        .opacity(warm ? 0.9 : 0)
        .animation(.easeOut(duration: 0.18), value: warm)
        .allowsHitTesting(warm)
        .help("Rated 0.8+ — this note gets a refine pass before export")
    }

    // ── Tier group labels under the circle clusters (1–3 / 4–6 / 7–10) ──
    private var tierLabels: some View {
        HStack(spacing: Self.gap) {
            tierLabel("passing", width: 3 * Self.dotSize + 2 * Self.gap, active: lit >= 1 && lit <= 3, warmTint: false)
            tierLabel("useful", width: 3 * Self.dotSize + 2 * Self.gap, active: lit >= 4 && lit <= 6, warmTint: false)
            // The significant cluster is 4 dots + the 1pt wall + its gaps wide.
            tierLabel("significant", width: 4 * Self.dotSize + 4 * Self.gap + 1, active: lit >= 7, warmTint: warm)
        }
    }

    private func tierLabel(_ name: String, width: CGFloat, active: Bool, warmTint: Bool) -> some View {
        Text(name.uppercased())
            .font(.system(size: 9))
            .tracking(0.63)
            .foregroundStyle(active ? (warmTint ? Theme.amber : Theme.accent) : Theme.textMuted)
            .frame(width: width)
            .animation(.easeOut(duration: 0.15), value: active)
    }

    // ── Warm blend colors (mock: color-mix of accent + amber) ──
    /// `color-mix(in oklab, accent 42%, amber)` — fill for lit circles 8–10.
    private static let warmFill = blend(accentWeight: 0.42)
    /// `color-mix(in oklab, accent 50%, amber)` — the warm value text.
    private static let warmText = blend(accentWeight: 0.50)

    /// sRGB approximation of the mock's oklab color-mix, adaptive light/dark using
    /// the same palette literals as `Theme.accent` / `Theme.amber`.
    private static func blend(accentWeight w: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { ap in
            let dark = ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let accent: (r: CGFloat, g: CGFloat, b: CGFloat) = dark ? (124, 107, 245) : (108, 92, 224)
            let amber: (r: CGFloat, g: CGFloat, b: CGFloat) = dark ? (245, 158, 11) : (217, 119, 6)
            return NSColor(srgbRed: (accent.r * w + amber.r * (1 - w)) / 255,
                           green: (accent.g * w + amber.g * (1 - w)) / 255,
                           blue: (accent.b * w + amber.b * (1 - w)) / 255,
                           alpha: 1)
        })
    }
}
