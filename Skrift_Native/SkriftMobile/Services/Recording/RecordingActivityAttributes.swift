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
        /// Island/Lock Screen waveform bar heights, 0...1, `barCount` entries (empty = idle).
        /// The widget CANNOT animate on its own (ActivityKit renders snapshots; a
        /// `TimelineView(.animation)` never ticks), so the bars are DATA the app pushes.
        var levels: [Float]

        static let barCount = 5

        enum Status: String, Codable, Hashable, Sendable {
            case recording
            case paused
            case stopping
        }

        init(status: Status, caption: String, startedAt: Date, pausedAt: Date? = nil, levels: [Float] = []) {
            self.status = status
            self.caption = caption
            self.startedAt = startedAt
            self.pausedAt = pausedAt
            self.levels = levels
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            status = try c.decode(Status.self, forKey: .status)
            caption = try c.decode(String.self, forKey: .caption)
            startedAt = try c.decode(Date.self, forKey: .startedAt)
            pausedAt = try c.decodeIfPresent(Date.self, forKey: .pausedAt)
            levels = try c.decodeIfPresent([Float].self, forKey: .levels) ?? []
        }
    }

    init() {}
}
