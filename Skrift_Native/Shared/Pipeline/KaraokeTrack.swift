import Foundation

/// WHICH WORD IS PLAYING — the one rule, both apps (Q82 group 6; Tuur 2026-09-30: "unify
/// that between devices, also in karaoke mode"). The phone and the Mac used to answer it
/// with different machinery (an index on the phone, a rounded fraction on the Mac) and
/// tapped-word seeking disagreed on a polished body. Both now build ONE track per body and
/// ask it for the playing word and for a tap's seek time.
///
/// Three bases, picked by one rule and never by the caller:
///  - EXACT: the shown words are as many as the timed words, so word N IS timing N
///    (a raw transcript, or a polish that only re-punctuated).
///  - ALIGNED: the body was edited, so its words are aligned to the timings once
///    (`Karaoke.wordTimes` → `AlignmentCore`). Exact times for matched words.
///  - PROPORTIONAL: no timings, or the aligner rejected the pair — an honest sweep across
///    the duration rather than a confidently wrong highlight.
struct KaraokeTrack: Equatable {
    enum Basis: Equatable { case exact, aligned, proportional }

    let basis: Basis
    /// One start time per shown word, non-decreasing. Empty for `.proportional`.
    let starts: [Double]
    let wordCount: Int
    let duration: Double

    init(displayedWords: [String], timings: [WordTiming], duration: Double) {
        self.wordCount = displayedWords.count
        self.duration = duration
        if !timings.isEmpty, timings.count == displayedWords.count {
            basis = .exact
            starts = timings.map(\.start)
        } else {
            let aligned = timings.isEmpty ? [] : Karaoke.wordTimes(displayedWords: displayedWords, timings: timings)
            if aligned.isEmpty {
                basis = .proportional
                starts = []
            } else {
                basis = .aligned
                starts = aligned
            }
        }
    }

    /// Index of the word being spoken at `time`: the last word that has started. nil before
    /// the first word (nothing highlighted yet) and when there is nothing to go on.
    func activeIndex(at time: Double) -> Int? {
        guard wordCount > 0 else { return nil }
        switch basis {
        case .exact, .aligned:
            let started = Karaoke.activeCount(times: starts, currentTime: time)
            return started > 0 ? started - 1 : nil
        case .proportional:
            guard duration > 0, time >= 0 else { return nil }
            return min(wordCount - 1, Int(time / duration * Double(wordCount)))
        }
    }

    /// The playback time a tap on shown word `index` seeks to. nil when there is no such
    /// word or no way to place it (no timings and no duration).
    func seekTime(forWord index: Int) -> Double? {
        guard index >= 0, index < wordCount else { return nil }
        switch basis {
        case .exact, .aligned:
            return Karaoke.seekTarget(wordIndex: index, times: starts, timings: [],
                                      duration: duration > 0 ? duration : .greatestFiniteMagnitude)
        case .proportional:
            guard duration > 0 else { return nil }
            return max(0, min(Double(index) / Double(wordCount) * duration, duration))
        }
    }
}

/// How one word is drawn while a note plays — the phone's paint, now the Mac's too:
/// what has been read steps back, the playing word takes the accent, what is still to
/// come stays at full strength. The colours are per-app; the assignment is here.
enum KaraokeRole: Equatable {
    case read, playing, upcoming

    static func of(word index: Int, active: Int?) -> KaraokeRole {
        guard let active else { return .upcoming }
        return index < active ? .read : (index == active ? .playing : .upcoming)
    }
}

/// Holds the track for the body being played so a 20 Hz caller does not re-align the note
/// on every tick. Rebuilds only when the words, the timings or the duration change.
final class KaraokeTrackCache {
    private var key: Key?
    private var track: KaraokeTrack?

    private struct Key: Equatable {
        let words: [String]
        let timingCount: Int
        let lastStart: Double
        let duration: Double
    }

    init() {}

    func track(displayedWords: [String], timings: [WordTiming], duration: Double) -> KaraokeTrack {
        let k = Key(words: displayedWords, timingCount: timings.count,
                    lastStart: timings.last?.start ?? 0, duration: duration)
        if let track, key == k { return track }
        let fresh = KaraokeTrack(displayedWords: displayedWords, timings: timings, duration: duration)
        key = k
        track = fresh
        return fresh
    }

    func invalidate() { key = nil; track = nil }
}
