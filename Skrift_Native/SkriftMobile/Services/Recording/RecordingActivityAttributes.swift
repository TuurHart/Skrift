import ActivityKit
import Foundation

/// Live Activity model, compiled into both the app (which starts/updates the
/// activity) and the widget extension (which renders it) by multi-target source
/// membership (see project.yml). Skrift adds a `paused` status + a `pausedAt`
/// anchor because the recorder supports pause/resume and the lock-screen timer
/// must freeze while paused.
///
/// Timer math: the view shows `Text(timerInterval: startedAt...distantFuture,
/// pauseTime: pausedAt)`. The app keeps `startedAt = now − elapsed` (re-anchored
/// on resume so paused time isn't counted); `pausedAt` is the freeze point while
/// paused, nil while recording. Everything the widget reads lives in `ContentState`.
struct RecordingActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var status: Status
        var caption: String
        var startedAt: Date
        var pausedAt: Date?

        enum Status: String, Codable, Hashable, Sendable {
            case recording
            case paused
            case stopping
        }

        init(status: Status, caption: String, startedAt: Date, pausedAt: Date? = nil) {
            self.status = status
            self.caption = caption
            self.startedAt = startedAt
            self.pausedAt = pausedAt
        }
    }

    init() {}
}
