import SwiftUI
import WidgetKit

/// The widget extension's entry point: the recording Live Activity, the Control
/// Center record button, and the Lock/Home-Screen record widget.
@main
struct SkriftWidgetBundle: WidgetBundle {
    var body: some Widget {
        SkriftLiveActivity()
        RecordControlWidget()
        RecordWidget()
    }
}
