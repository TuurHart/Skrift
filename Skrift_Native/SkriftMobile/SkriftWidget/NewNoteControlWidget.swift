import AppIntents
import SwiftUI
import WidgetKit

/// Control Center (iOS 18) New Note button. Tapping runs `NewNoteIntent`,
/// which opens Skrift straight into an empty note (D135: its own control,
/// beside the Record one — `RecordControlWidget`).
struct NewNoteControlWidget: ControlWidget {
    static let kind = "com.skrift.mobile.newnote"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: NewNoteIntent()) {
                Label("New Note", systemImage: "square.and.pencil")
            }
        }
        .displayName("Skrift New Note")
        .description("Open an empty Skrift note.")
    }
}
