import SwiftUI
import WidgetKit

/// The widget extension's entry point: the recording Live Activity, the Control
/// Center record + new-note buttons, and the Lock/Home-Screen record + new-note
/// widgets (D135: New Note is its own control/widget beside Record).
@main
struct SkriftWidgetBundle: WidgetBundle {
    var body: some Widget {
        SkriftLiveActivity()
        RecordControlWidget()
        RecordWidget()
        NewNoteControlWidget()
        NewNoteWidget()
    }
}
