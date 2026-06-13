import AppIntents
import SwiftUI
import WidgetKit

/// Control Center (iOS 18) record button. Tapping runs StartRecordingIntent,
/// which opens Skrift and starts recording.
struct RecordControlWidget: ControlWidget {
    static let kind = "com.skrift.mobile.record"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartRecordingIntent()) {
                // Skrift-forward glyph (quote.opening ❝) instead of a generic mic —
                // echoes the app's quote-capture identity. CC renders it monochrome.
                Label("Record", systemImage: "quote.opening")
            }
        }
        .displayName("Skrift")
        .description("Start a Skrift voice memo.")
    }
}
