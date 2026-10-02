import SwiftUI
import WidgetKit

/// The widget target can't see the app's DesignSystem (Theme.swift), so it compiles the
/// cross-app hex table (`Shared/UI/Palette.swift`, Foundation-only) and builds its dark
/// colours from it with this one helper. The widgets and the Live Activity are always
/// dark (their backgrounds are fixed), so only the `dark` column is read.
extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: alpha)
    }
}

enum WidgetColors {
    static let accent = Color(hex: Palette.accent.dark)       // 7c6bf5
    static let red = Color(hex: Palette.red.dark)             // ef4444
    static let amber = Color(hex: Palette.amber.dark)         // f59e0b
    static let bg = Color(hex: Palette.bg.phone.dark)         // 0f1117
    /// The Live Activity pill — a widget-only value with no twin in the app.
    static let pill = Color(hex: 0x15161d)
}

/// One Lock Screen accessory + Home Screen widget with a one-tap action. Static (no
/// timeline data); tapping opens the `url`, which `AppURLHandler` routes. Record and New
/// Note are two thin `Widget` wrappers over this (D135: separate widgets, not a mode), so
/// their kinds — which installed widgets reference — never change.
struct QuickActionSpec {
    let kind: String
    let url: String
    let symbol: String
    let title: String        // display name, inline label, Home Screen caption
    let caption: String      // the rectangular accessory's second line
    let blurb: String        // the gallery description

    var configuration: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickActionProvider()) { _ in
            QuickActionView(spec: self)
                .widgetURL(URL(string: url))
        }
        .configurationDisplayName(title)
        .description(blurb)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

private struct QuickActionEntry: TimelineEntry { let date: Date }

private struct QuickActionProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickActionEntry { QuickActionEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (QuickActionEntry) -> Void) {
        completion(QuickActionEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickActionEntry>) -> Void) {
        // Static button — one entry, never reload.
        completion(Timeline(entries: [QuickActionEntry(date: Date())], policy: .never))
    }
}

private struct QuickActionView: View {
    let spec: QuickActionSpec
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                family == .systemSmall ? WidgetColors.bg : Color.clear
            }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: spec.symbol).font(.system(size: 20))
            }
        case .accessoryInline:
            Label(spec.title, systemImage: spec.symbol)
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: spec.symbol).font(.system(size: 18))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Skrift").font(.headline)
                    Text(spec.caption).font(.caption)
                }
                Spacer(minLength: 0)
            }
        default:  // .systemSmall (Home Screen)
            VStack(spacing: 8) {
                Image(systemName: spec.symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(WidgetColors.accent))
                    .shadow(color: WidgetColors.accent.opacity(0.4), radius: 8, y: 4)
                Text(spec.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
