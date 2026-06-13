import SwiftUI
import WidgetKit

/// Lock Screen accessory + Home Screen widget with a one-tap record affordance.
/// Static (no timeline data needed); tapping opens `skrift://record`, which
/// AppURLHandler turns into a recording start. Complements the Control Center
/// control (`RecordControlWidget`) and the recording Live Activity.
struct RecordWidget: Widget {
    static let kind = "com.skrift.mobile.recordwidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: RecordProvider()) { _ in
            RecordWidgetView()
                .widgetURL(URL(string: "skrift://record"))
        }
        .configurationDisplayName("Record")
        .description("Start a Skrift voice memo.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

private struct RecordEntry: TimelineEntry { let date: Date }

private struct RecordProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecordEntry { RecordEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (RecordEntry) -> Void) {
        completion(RecordEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RecordEntry>) -> Void) {
        // Static button — one entry, never reload.
        completion(Timeline(entries: [RecordEntry(date: Date())], policy: .never))
    }
}

private struct RecordWidgetView: View {
    @Environment(\.widgetFamily) private var family

    private static let skBg = Color(red: 0.059, green: 0.067, blue: 0.090)
    // Skrift's accent (matches `Theme.skAccent` 0x7c6bf5 / the in-app record
    // button) so the widget reads as Skrift, not a generic red record dot. The
    // widget target doesn't compile Theme.swift, so the value is inlined.
    private static let accent = Color(red: 0.486, green: 0.420, blue: 0.961)

    var body: some View {
        content
            .containerBackground(for: .widget) {
                family == .systemSmall ? Self.skBg : Color.clear
            }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill").font(.system(size: 20))
            }
        case .accessoryInline:
            Label("Record", systemImage: "mic.fill")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "mic.fill").font(.system(size: 18))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Skrift").font(.headline)
                    Text("Tap to record").font(.caption)
                }
                Spacer(minLength: 0)
            }
        default:  // .systemSmall (Home Screen)
            VStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Self.accent))
                    .shadow(color: Self.accent.opacity(0.4), radius: 8, y: 4)
                Text("Record")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
