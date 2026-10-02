import SwiftUI
import WidgetKit

/// Lock Screen accessory + Home Screen widget for the quick-note verb (D135: its own
/// control/widget beside Record, not a mode on it). Tapping opens `skrift://newnote`,
/// which `AppURLHandler` turns into an empty-note open via `QuickNoteBridge`. The view +
/// provider are the shared `QuickActionSpec`.
struct NewNoteWidget: Widget {
    static let kind = "com.skrift.mobile.newnotewidget"

    var body: some WidgetConfiguration {
        QuickActionSpec(kind: Self.kind, url: "skrift://newnote", symbol: "square.and.pencil",
                        title: "New Note", caption: "New note",
                        blurb: "Open an empty Skrift note.").configuration
    }
}
