import SwiftUI
import WidgetKit

/// Lock Screen accessory + Home Screen widget with a one-tap record affordance.
/// Tapping opens `skrift://record`, which AppURLHandler turns into a recording start.
/// Complements the Control Center control (`RecordControlWidget`) and the recording
/// Live Activity. The view + provider are the shared `QuickActionSpec`.
struct RecordWidget: Widget {
    static let kind = "com.skrift.mobile.recordwidget"

    var body: some WidgetConfiguration {
        QuickActionSpec(kind: Self.kind, url: "skrift://record", symbol: "quote.opening",
                        title: "Record", caption: "Tap to record",
                        blurb: "Start a Skrift voice note.").configuration
    }
}
