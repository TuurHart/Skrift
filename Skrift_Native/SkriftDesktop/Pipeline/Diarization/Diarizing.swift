import Foundation

/// A diarization result: a time range assigned to a speaker slot (0-based).
struct DiarizedSegment: Sendable, Equatable, Codable {
    let speaker: Int
    let start: Double
    let end: Double
}

/// Diarization result: speaker time-ranges + the matched name per slot (a slot is named
/// when its voiceprint cosine-matches a known person; nil otherwise → "Speaker N").
struct DiarizationOutput: Sendable {
    let segments: [DiarizedSegment]
    let slotNames: [Int: String]
}

/// Splits a recording into speakers ("who spoke when") + matches each to a known voice
/// ("is this Tiuri?"). Real impl = Sortformer + wespeaker via FluidAudio (`Engines/`,
/// app-only, device ANE); the pipeline injects it so `BatchRunner` host-tests with a stub
/// or no diarizer. Mirrors the phone's `Diarizing`.
protocol Diarizing: Sendable {
    func diarize(audioURL: URL) async throws -> DiarizationOutput
}

/// Detects + parses a speaker-attributed (`**Name:**` turns) transcript, so the Mac
/// doesn't re-diarize a conversation the phone already split, and so name-linking can
/// treat turn headers distinctly from inline speech. Mirrors the phone's
/// `SpeakerTranscript` (SkriftMobile/Features/MemoDetail/SpeakerTurnsView.swift).
enum SpeakerTranscript {
    struct Turn: Equatable { let name: String; let text: String }

    /// A turn header — a bold `**Name:**` anchored to the START of a line/paragraph.
    /// The line anchor (`(?m)^`) is deliberate: a hand-typed/LLM-formatted inline
    /// `**Pros:**` mid-sentence (e.g. an Apple Note) must NOT read as a speaker turn
    /// (the 2026-06-14 false-positive that skipped copy-edit on plain notes).
    private static let headerPattern = #"(?m)^[ \t]*\*\*([^*\n]+?):\*\*[ \t]*"#

    /// The `**Name:**` turns, or nil when fewer than 2 headers — `name` has the `[[ ]]`
    /// stripped (so `[[Tiuri Hartog]]` and a plain `Tiuri Hartog` header read the same).
    static func parse(_ transcript: String?) -> [Turn]? {
        guard let t = transcript,
              let re = try? NSRegularExpression(pattern: headerPattern) else { return nil }
        let ns = t as NSString
        let matches = re.matches(in: t, range: NSRange(location: 0, length: ns.length))
        guard matches.count >= 2 else { return nil }
        var turns: [Turn] = []
        for (i, m) in matches.enumerated() {
            let rawName = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let name = rawName.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
            let textStart = m.range.location + m.range.length
            let textEnd = (i + 1 < matches.count) ? matches[i + 1].range.location : ns.length
            let text = ns.substring(with: NSRange(location: textStart, length: textEnd - textStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            turns.append(Turn(name: name, text: text))
        }
        return turns
    }

    /// The turns PLUS any leading text before the first turn header — e.g. an early
    /// `[[img_NNN]]` photo marker the phone inserted before the first spoken word.
    /// Lets the conversation linker PRESERVE that preamble instead of dropping it (turn
    /// reassembly otherwise keeps only the `**Name:**` blocks). nil when not ≥2 turns.
    static func parseWithPreamble(_ transcript: String?) -> (preamble: String, turns: [Turn])? {
        guard let t = transcript, let turns = parse(t),
              let re = try? NSRegularExpression(pattern: headerPattern) else { return nil }
        let ns = t as NSString
        let firstLoc = re.firstMatch(in: t, range: NSRange(location: 0, length: ns.length))?.range.location ?? 0
        let preamble = ns.substring(to: firstLoc).trimmingCharacters(in: .whitespacesAndNewlines)
        return (preamble, turns)
    }

    /// True when `transcript` is a conversation: ≥2 turn headers AND ≥2 DISTINCT speaker
    /// labels (a list with repeated `**Pros:**`/`**Pros:**` headers, or a single speaker,
    /// is not a conversation → it still gets copy-edit + ordinary name-linking).
    static func isAttributed(_ transcript: String?) -> Bool {
        guard let turns = parse(transcript) else { return false }
        return Set(turns.map(\.name)).count >= 2
    }

    /// Collapse consecutive turns by the SAME speaker label into one (joining bodies with
    /// a space) — repairs diarization fragmentation where one speaker's run was split into
    /// several tiny `**Name:**` turns. Re-emits the `**Name:** text` Markdown verbatim
    /// (no name-linking). Non-attributed text is returned unchanged.
    static func mergeAdjacentTurns(_ transcript: String) -> String {
        guard let turns = parse(transcript) else { return transcript }
        var merged: [(name: String, text: String)] = []
        for t in turns {
            if let last = merged.last, last.name == t.name {
                let sep = (merged[merged.count - 1].text.isEmpty || t.text.isEmpty) ? "" : " "
                merged[merged.count - 1].text += sep + t.text
            } else {
                merged.append((t.name, t.text))
            }
        }
        return merged.map { "**\($0.name):** \($0.text)" }.joined(separator: "\n\n")
    }
}
