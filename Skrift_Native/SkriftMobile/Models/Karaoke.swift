import Foundation

/// Karaoke highlight math (pure → unit-tested). The transcript view maps the active
/// spoken-word index onto the displayed words. (`WordTiming` itself is the shared
/// wire-contract struct — Shared/Model/WordTiming.swift.)
enum Karaoke {
    /// Index of the word being spoken at `time` — the last word whose `start` is at
    /// or before `time`. nil before the first word starts (no highlight yet).
    /// `timings` must be in start order.
    static func activeWordIndex(_ timings: [WordTiming], at time: TimeInterval) -> Int? {
        guard let first = timings.first, time >= first.start else { return nil }
        var idx = 0
        for (i, t) in timings.enumerated() {
            if t.start <= time { idx = i } else { break }
        }
        return idx
    }
}
