import SwiftUI

/// The "Aa" reading-text settings popover (mock screen 4). v1 = font **size** +
/// **line spacing** (Tight/Cozy/Loose), persisted app-wide via `@AppStorage` so
/// every book opens the way you last left it. The read-along reads the same keys.
/// Light/sepia/dark reading themes are a fast-follow — shown dimmed so the slot
/// reads, but not yet wired.
struct TextSettingsSheet: View {
    @AppStorage(ReadingPrefs.fontSizeKey) private var fontSize = ReadingPrefs.defaultFontSize
    @AppStorage(ReadingPrefs.lineHeightKey) private var lineHeight = ReadingPrefs.defaultLineHeight

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Color.skBorder).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 10).padding(.bottom, 18)

            Text("TEXT").font(.system(size: 11, weight: .semibold)).kerning(0.4)
                .foregroundStyle(Color.skTextFaint).padding(.bottom, 14)

            // Size — A− / A+ steppers (mock: small A / large A tap targets)
            HStack {
                Text("Size").font(.system(size: 13)).foregroundStyle(Color.skTextDim)
                Spacer()
                HStack(spacing: 12) {
                    sizeButton(glyph: 14, enabled: fontSize > ReadingPrefs.minFontSize) {
                        setSize(fontSize - 1)
                    }
                    .accessibilityIdentifier("reading-size-smaller")
                    .accessibilityLabel("Smaller text")
                    sizeButton(glyph: 21, enabled: fontSize < ReadingPrefs.maxFontSize) {
                        setSize(fontSize + 1)
                    }
                    .accessibilityIdentifier("reading-size-larger")
                    .accessibilityLabel("Larger text")
                }
            }
            .padding(.bottom, 16)

            // Line spacing — Tight / Cozy / Loose (= 1.5 / 1.7 / 1.9 line-height)
            Picker("", selection: $lineHeight) {
                Text("Tight").tag(ReadingPrefs.tight)
                Text("Cozy").tag(ReadingPrefs.cozy)
                Text("Loose").tag(ReadingPrefs.loose)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("reading-line-spacing")
            .padding(.bottom, 18)

            // Reading themes — fast-follow (shown dimmed)
            HStack(spacing: 10) {
                themeSwatch("Light", bg: Color(hex: 0xECE8DF), fg: Color(hex: 0x2A2A2A))
                themeSwatch("Sepia", bg: Color(hex: 0xEFE2C6), fg: Color(hex: 0x3A2F1A))
                themeSwatch("Dark", bg: Color(hex: 0x16161E), fg: Color(hex: 0xDDDDDD), selected: true)
            }
            .opacity(0.5)
            .allowsHitTesting(false)
            Text("Light & sepia reading themes coming soon")
                .font(.system(size: 10.5)).foregroundStyle(Color.skTextFaint)
                .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .background(Color.skElev.ignoresSafeArea())
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.hidden)
        .accessibilityIdentifier("reading-text-settings")
    }

    private func setSize(_ v: Double) {
        fontSize = min(ReadingPrefs.maxFontSize, max(ReadingPrefs.minFontSize, v))
        Haptics.tap(.light)
    }

    private func sizeButton(glyph: CGFloat, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("A").font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(enabled ? Color.skText : Color.skTextFaint)
                .frame(width: 44, height: 42)
                .background(Color.skSurface, in: .rect(cornerRadius: 11, style: .continuous))
        }
        .disabled(!enabled)
    }

    private func themeSwatch(_ name: String, bg: Color, fg: Color, selected: Bool = false) -> some View {
        Text(name).font(.system(size: 11.5, weight: .medium)).foregroundStyle(fg)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(bg, in: .rect(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(selected ? Color.skAccent : Color.clear, lineWidth: 1)
            )
    }
}

/// Shared reading-text preference keys + bounds. One source of truth for the "Aa"
/// sheet (writer) and the read-along (reader); `@AppStorage` persists app-wide.
enum ReadingPrefs {
    static let fontSizeKey = "readingFontSize"
    static let lineHeightKey = "readingLineHeight"

    static let defaultFontSize: Double = 17
    static let minFontSize: Double = 14
    static let maxFontSize: Double = 22

    // Line-height multipliers behind Tight/Cozy/Loose.
    static let tight: Double = 1.5
    static let cozy: Double = 1.7
    static let loose: Double = 1.9
    static let defaultLineHeight = cozy

    /// SwiftUI `.lineSpacing` is EXTRA leading on top of the font's ~1.2 natural
    /// line height — convert a CSS-style line-height multiplier to that extra.
    static func extraLeading(fontSize: Double, lineHeight: Double) -> CGFloat {
        max(2, CGFloat(fontSize) * (CGFloat(lineHeight) - 1.2))
    }
}
