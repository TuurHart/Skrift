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
                Label("Record", systemImage: "mic.fill")
            }
        }
        .displayName("Skrift")
        .description("Start a Skrift voice memo.")
    }
}
