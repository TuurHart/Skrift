import Foundation

/// Fuses diarization segments with the ASR word-timings into a speaker-attributed
/// transcript. Each word is assigned to the speaker whose segment covers its midpoint
/// (nearest segment if it lands in a gap); consecutive words group into turns; tiny
/// word "islands" shorter than `minTurnWords`, flanked by the same other speaker, are
/// smoothed away. Output is `**Name:** text` turns. Ported verbatim from the phone's
/// `SpeakerFusion` (the Mac emits `**[[Canonical]]:**` for matched speakers since it owns
/// the canonical link form).
enum SpeakerFusion {
    struct Turn: Equatable { let speaker: Int; let text: String }

    static func turns(words: [WordTiming], segments: [DiarizedSegment], minTurnWords: Int = 2) -> [Turn] {
        guard !words.isEmpty, !segments.isEmpty else { return [] }
        let segs = segments.sorted { $0.start < $1.start }
        var labels = words.map { speaker(at: ($0.start + $0.end) / 2, segs: segs) }
        labels = smooth(labels, minRun: minTurnWords)
        labels = foldShortIslands(labels, words: words)

        var turns: [Turn] = []
        var i = 0
        while i < words.count {
            let spk = labels[i]
            var buf: [String] = []
            while i < words.count, labels[i] == spk { buf.append(words[i].word); i += 1 }
            turns.append(Turn(speaker: spk, text: buf.joined(separator: " ")))
        }
        return turns
    }

    /// The `**Name:** text` Markdown (turns joined by blank lines). `name` maps a speaker
    /// slot to a display name (a matched person's `[[Canonical]]`, else "Speaker N").
    static func attributedTranscript(
        words: [WordTiming], segments: [DiarizedSegment], minTurnWords: Int = 2,
        name: (Int) -> String = { "Speaker \($0 + 1)" }
    ) -> String {
        turns(words: words, segments: segments, minTurnWords: minTurnWords)
            .map { "**\(name($0.speaker)):** \($0.text)" }
            .joined(separator: "\n\n")
    }

    private static func speaker(at t: Double, segs: [DiarizedSegment]) -> Int {
        if let s = segs.first(where: { t >= $0.start && t <= $0.end }) { return s.speaker }
        return segs.min(by: { abs(($0.start + $0.end) / 2 - t) < abs(($1.start + $1.end) / 2 - t) })?.speaker ?? 0
    }

    /// Fold a tiny island (≤ `maxIslandWords`) flanked by DIFFERENT speakers into whichever
    /// neighbor is nearer in time — catches Sortformer over-segmenting a short interjection
    /// into its own slot. The same-speaker case is handled by `smooth`. Mirrors the phone.
    private static func foldShortIslands(_ labels: [Int], words: [WordTiming], maxIslandWords: Int = 1) -> [Int] {
        guard labels.count > 2, words.count == labels.count else { return labels }
        var out = labels
        var i = 0
        while i < out.count {
            var j = i
            while j < out.count, out[j] == out[i] { j += 1 }   // run [i, j)
            if j - i <= maxIslandWords {
                let s = out[i]
                let before: Int? = i > 0 ? out[i - 1] : nil
                let after: Int? = j < out.count ? out[j] : nil
                let target: Int?
                switch (before, after) {
                case let (b?, a?) where b != s && a != s:
                    let gapBefore = words[i].start - words[i - 1].end
                    let gapAfter = words[j].start - words[j - 1].end
                    target = gapBefore <= gapAfter ? b : a
                case let (b?, nil) where b != s: target = b
                case let (nil, a?) where a != s: target = a
                default: target = nil
                }
                if let target { for k in i..<j { out[k] = target } }
            }
            i = j
        }
        return out
    }

    /// Relabel runs shorter than `minRun` words that are flanked by the same speaker.
    private static func smooth(_ labels: [Int], minRun: Int) -> [Int] {
        guard minRun > 1, labels.count > 2 else { return labels }
        var out = labels
        var i = 0
        while i < out.count {
            var j = i
            while j < out.count, out[j] == out[i] { j += 1 }   // run [i, j)
            if j - i < minRun {
                let before = i > 0 ? out[i - 1] : nil
                let after = j < out.count ? out[j] : nil
                if let before, before == after, before != out[i] {
                    for k in i..<j { out[k] = before }
                }
            }
            i = j
        }
        return out
    }
}
