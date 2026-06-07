import ActivityKit
import Foundation

/// Live Activity model, shared between the app (which starts/updates the activity)
/// and the widget extension (which renders it). Mirrors Shhhcribble's pattern;
/// Skrift adds a `paused` status + a `pausedAt` anchor because the recorder
/// supports pause/resume and the lock-screen timer must freeze while paused.
///
/// Timer math: the view shows `Text(timerInterval: startedAt...distantFuture,
/// pauseTime: pausedAt)`. The app keeps `startedAt = now − elapsed` (re-anchored
/// on resume so paused time isn't counted); `pausedAt` is the freeze point while
/// paused, nil while recording.
public struct RecordingActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var status: Status
        public var caption: String
        public var startedAt: Date
        public var pausedAt: Date?

        public enum Status: String, Codable, Hashable, Sendable {
            case recording
            case paused
            case stopping
        }

        public init(status: Status, caption: String, startedAt: Date, pausedAt: Date? = nil) {
            self.status = status
            self.caption = caption
            self.startedAt = startedAt
            self.pausedAt = pausedAt
        }
    }

    public var sessionId: String
    public var startedAt: Date

    public init(sessionId: String = UUID().uuidString, startedAt: Date = Date()) {
        self.sessionId = sessionId
        self.startedAt = startedAt
    }
}
