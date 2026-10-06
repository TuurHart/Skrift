import Foundation
import Observation

/// What the discard question needs from a take (Q328, D182). `LiveRecordingSession` is the
/// real one; the unit test uses a fake, so the rule is provable without a microphone.
@MainActor
protocol DiscardableTake: AnyObject {
    var isPaused: Bool { get }
    func pauseTake()
    func resumeTake()
    /// Throw the take away: stop the mic, delete the main file, segments and marker.
    func discardTake()
}

/// The "Discard this recording?" question (D182): the take PAUSES while it is asked, Keep
/// puts it back as it was (resumed if it was recording, still paused if it was already
/// paused), Discard deletes it. The view only shows `isAsking` as a popover on the x; every
/// rule lives here.
@MainActor
@Observable
final class RecorderDiscardAsk {
    private(set) var isAsking = false
    /// We paused the take for the question, so Keep must resume it. False when the take was
    /// already paused when x was pressed.
    private var pausedByAsk = false
    @ObservationIgnored weak var take: (any DiscardableTake)?

    init(take: (any DiscardableTake)? = nil) { self.take = take }

    /// The x was pressed. A second press while the question is up closes it (= Keep).
    func ask() {
        guard let take else { return }
        if isAsking { keep(); return }
        isAsking = true
        pausedByAsk = !take.isPaused
        if pausedByAsk { take.pauseTake() }
    }

    /// Keep (also Return, Esc, and a click outside the popover): nothing is lost.
    func keep() {
        guard isAsking else { return }
        isAsking = false
        if pausedByAsk { take?.resumeTake() }
        pausedByAsk = false
    }

    func discard() {
        guard isAsking else { return }
        isAsking = false
        pausedByAsk = false
        take?.discardTake()
    }

    /// The take ended by another road (Stop, a write failure): close the question without
    /// resuming anything.
    func reset() {
        isAsking = false
        pausedByAsk = false
    }
}
