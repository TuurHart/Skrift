import SwiftUI
import WidgetKit

/// Lock Screen accessory + Home Screen widget for the quick-note verb (D135:
/// its own control/widget beside Record, not a mode on it). Static (no
/// timeline data needed); tapping opens `skrift://newnote`, which
/// `AppURLHandler` turns into an empty-note open via `QuickNoteBridge`.
struct NewNoteWidget: Widget {
    static let kind = "com.skrift.mobile.newnotewidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NewNoteProvider()) { _ in
            NewNoteWidgetView()
                .widgetURL(URL(string: "skrift://newnote"))
        }
        .configurationDisplayName("New Note")
        .description("Open an empty Skrift note.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

private struct NewNoteEntry: TimelineEntry { let date: Date }

private struct NewNoteProvider: TimelineProvider {
    func placeholder(in context: Context) -> NewNoteEntry { NewNoteEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (NewNoteEntry) -> Void) {
        completion(NewNoteEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NewNoteEntry>) -> Void) {
        // Static button — one entry, never reload.
        completion(Timeline(entries: [NewNoteEntry(date: Date())], policy: .never))
    }
}

private struct NewNoteWidgetView: View {
    @Environment(\.widgetFamily) private var family

    private static let skBg = Color(red: 0.059, green: 0.067, blue: 0.090)
    // Matches `Theme.skAccent` 0x7c6bf5 — the widget target doesn't compile
    // Theme.swift, so the value is inlined (same as RecordWidget).
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
                Image(systemName: "square.and.pencil").font(.system(size: 20))
            }
        case .accessoryInline:
            Label("New Note", systemImage: "square.and.pencil")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil").font(.system(size: 18))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Skrift").font(.headline)
                    Text("New note").font(.caption)
                }
                Spacer(minLength: 0)
            }
        default:  // .systemSmall (Home Screen)
            VStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Self.accent))
                    .shadow(color: Self.accent.opacity(0.4), radius: 8, y: 4)
                Text("New Note")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
