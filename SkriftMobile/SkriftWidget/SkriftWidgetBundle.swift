import SwiftUI
import WidgetKit

/// The widget extension's entry point. Holds the recording Live Activity for now;
/// 8b adds the Control Center record control + a Home/Lock Screen widget here.
@main
struct SkriftWidgetBundle: WidgetBundle {
    var body: some Widget {
        SkriftLiveActivity()
    }
}
