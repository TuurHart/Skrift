import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct RecordEntry: TimelineEntry {
    let date: Date
}

// MARK: - Timeline Provider

struct RecordProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecordEntry {
        RecordEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (RecordEntry) -> Void) {
        completion(RecordEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecordEntry>) -> Void) {
        // Static widget — just provide one entry, refresh daily
        let entry = RecordEntry(date: Date())
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 24, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Lock Screen Circular View

struct RecordWidgetCircularView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "mic.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(red: 0.486, green: 0.420, blue: 0.961)) // #7c6bf5
        }
        // Deep-link: opens Skrift app and navigates to the Record tab
        .widgetURL(URL(string: "skrift://record"))
    }
}

// MARK: - Lock Screen Rectangular View

struct RecordWidgetRectangularView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(red: 0.486, green: 0.420, blue: 0.961))
            Text("Record Memo")
                .font(.system(size: 14, weight: .medium))
        }
        .widgetURL(URL(string: "skrift://record"))
    }
}

// MARK: - Lock Screen Inline View

struct RecordWidgetInlineView: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "mic.fill")
            Text("Record Memo")
        }
        .widgetURL(URL(string: "skrift://record"))
    }
}

// MARK: - Widget Entry View

struct RecordWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: RecordProvider.Entry

    var body: some View {
        switch family {
        case .accessoryCircular:
            RecordWidgetCircularView()
        case .accessoryRectangular:
            RecordWidgetRectangularView()
        case .accessoryInline:
            RecordWidgetInlineView()
        default:
            // Home screen small widget fallback
            ZStack {
                Color(red: 0.059, green: 0.067, blue: 0.090) // #0f1117
                VStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(Color(red: 0.486, green: 0.420, blue: 0.961))
                    Text("Record")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .widgetURL(URL(string: "skrift://record"))
        }
    }
}

// MARK: - Widget Configuration

@main
struct RecordWidget: Widget {
    let kind: String = "RecordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecordProvider()) { entry in
            RecordWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Quick Record")
        .description("Tap to start recording a voice memo in Skrift.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .systemSmall,
        ])
    }
}

// MARK: - Preview

#if DEBUG
struct RecordWidget_Previews: PreviewProvider {
    static var previews: some View {
        RecordWidgetEntryView(entry: RecordEntry(date: Date()))
            .previewContext(WidgetPreviewContext(family: .accessoryCircular))
            .previewDisplayName("Circular")

        RecordWidgetEntryView(entry: RecordEntry(date: Date()))
            .previewContext(WidgetPreviewContext(family: .accessoryRectangular))
            .previewDisplayName("Rectangular")

        RecordWidgetEntryView(entry: RecordEntry(date: Date()))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("Small")
    }
}
#endif
