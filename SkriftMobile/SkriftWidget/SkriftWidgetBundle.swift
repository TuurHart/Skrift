import SwiftUI
import WidgetKit

/// The widget extension's entry point: the recording Live Activity + the Control
/// Center record button.
@main
struct SkriftWidgetBundle: WidgetBundle {
    var body: some Widget {
        SkriftLiveActivity()
        RecordControlWidget()
    }
}
