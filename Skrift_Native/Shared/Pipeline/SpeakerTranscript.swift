import Foundation

/// Detects + parses a speaker-attributed (`**Name:**` turns) conversation transcript —
/// SHARED, and load-bearing: the shared `Sanitiser.processConversation` parses through
/// THIS type, so until 2026-07-13 each app compiled its own twin and one shared file
/// silently had two behaviors (they had already drifted: the Mac's merge dropped the
/// preamble; the phone's merge wasn't empty-safe — this union keeps the best of both).
///
/// Used by: the shared Sanitiser (conversation name-linking), the Mac's "don't
/// re-diarize / flatten to monologue" logic, the phone's turn rendering + per-line
/// edit/reassign/rename surface.
enum SpeakerTranscript {
    /// A parsed turn. `Identifiable` for SwiftUI lists; equality is CONTENT-only
    /// (name + text — the id is per-parse and must never affect comparison).
    struct Turn: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let text: String

        init(name: String, text: String) {
            self.name = name
            self.text = text
        }

        static func == (l: Turn, r: Turn) -> Bool { l.name == r.name && l.text == r.text }
    }

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
    /// `[[img_NNN]]` photo marker inserted before the first spoken word. Lets callers
    /// PRESERVE that preamble instead of dropping it. nil when not ≥2 turns.
    static func parseWithPreamble(_ transcript: String?) -> (preamble: String, turns: [Turn])? {
        guard let t = transcript, let turns = parse(t),
              let re = try? NSRegularExpression(pattern: headerPattern) else { return nil }
        let ns = t as NSString
        let firstLoc = re.firstMatch(in: t, range: NSRange(location: 0, length: ns.length))?.range.location ?? 0
        let preamble = ns.substring(to: firstLoc).trimmingCharacters(in: .whitespacesAndNewlines)
        return (preamble, turns)
    }

    /// Prepend the ORIGINAL transcript's preamble (anything before its first `**Name:**`
    /// header) onto a rebuilt turns body, so an edit / merge / rename never silently
    /// drops it. No-op when there's no preamble.
    static func withPreamble(of original: String?, _ body: String) -> String {
        guard let original, let re = try? NSRegularExpression(pattern: headerPattern),
              let first = re.firstMatch(in: original, range: NSRange(location: 0, length: (original as NSString).length)),
              first.range.location > 0 else { return body }
        let preamble = (original as NSString).substring(to: first.range.location)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return preamble.isEmpty ? body : preamble + "\n\n" + body
    }

    /// "Speaker N" is the un-named placeholder (offer to tag it); a real name isn't.
    static func isUnnamed(_ name: String) -> Bool {
        name.range(of: #"^Speaker \d+$"#, options: .regularExpression) != nil
    }

    /// The distinct speaker labels in a transcript, in first-appearance order.
    static func speakers(in transcript: String?) -> [String] {
        guard let turns = parse(transcript) else { return [] }
        var seen = Set<String>(), out: [String] = []
        for t in turns where !seen.contains(t.name) { seen.insert(t.name); out.append(t.name) }
        return out
    }

    /// True when `transcript` is a conversation: ≥2 turn headers AND ≥2 DISTINCT speaker
    /// labels (a list with repeated `**Pros:**`/`**Pros:**` headers, or a single speaker,
    /// is not a conversation → it still gets copy-edit + ordinary name-linking).
    static func isAttributed(_ transcript: String?) -> Bool {
        guard let turns = parse(transcript) else { return false }
        return Set(turns.map(\.name)).count >= 2
    }

    /// FLATTEN a speaker-attributed transcript back to plain monologue prose: drop every
    /// `**Name:**` header and join the turn bodies with blank lines, preserving any leading
    /// preamble. Returns the input unchanged when it isn't attributed (callers no-op safely).
    static func flattened(_ transcript: String?) -> String? {
        guard let transcript else { return nil }
        guard let parsed = parseWithPreamble(transcript) else { return transcript }   // not a conversation
        var parts: [String] = []
        if !parsed.preamble.isEmpty { parts.append(parsed.preamble) }
        parts.append(contentsOf: parsed.turns.map(\.text).filter { !$0.isEmpty })
        return parts.joined(separator: "\n\n")
    }

    /// Replace a single turn's TEXT (by position), keeping its speaker — for inline editing.
    /// Returns nil if not parseable. Does NOT re-fuse (names unchanged).
    static func setText(_ transcript: String?, turnAt index: Int, to newText: String) -> String? {
        guard let turns = parse(transcript), index >= 0, index < turns.count else { return nil }
        let body = turns.enumerated()
            .map { i, t in "**\(t.name):** \(i == index ? newText.trimmingCharacters(in: .whitespacesAndNewlines) : t.text)" }
            .joined(separator: "\n\n")
        return withPreamble(of: transcript, body)
    }

    /// Reassign a SINGLE turn (by position) to another speaker, then re-merge — the
    /// per-line merge fix. Relabels only `turnAt`, NOT every turn of that speaker.
    static func reassign(_ transcript: String?, turnAt index: Int, to newName: String) -> String? {
        guard let turns = parse(transcript), index >= 0, index < turns.count else { return nil }
        let rebuilt = turns.enumerated()
            .map { i, t in "**\(i == index ? newName : t.name):** \(t.text)" }
            .joined(separator: "\n\n")
        return withPreamble(of: transcript, mergeAdjacentTurns(rebuilt))
    }

    /// Collapse consecutive turns by the SAME speaker label into one — repairs
    /// diarization fragmentation and post-reassign adjacency. Empty-safe join (no
    /// doubled spaces when a body is empty — the Mac's old rule) AND preamble-
    /// preserving (the phone's old rule; the Mac's twin used to DROP it).
    /// Non-attributed text is returned unchanged.
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
        let body = merged.map { "**\($0.name):** \($0.text)" }.joined(separator: "\n\n")
        return withPreamble(of: transcript, body)
    }

    /// Rename every turn belonging to diarization SLOT `slot` (NOT every turn that happens
    /// to share the old display name), then merge adjacent same-speaker turns. `turnSlots`
    /// is the per-turn slot map persisted at diarize time. Returns nil when the map doesn't
    /// line up with the current turns (a structural edit since diarize) so the caller can
    /// fall back to name-based relabeling.
    static func relabelSlot(_ transcript: String?, turnSlots: [Int], slot: Int, to newName: String) -> String? {
        guard let turns = parse(transcript), turnSlots.count == turns.count else { return nil }
        let rebuilt = turns.enumerated()
            .map { i, t in "**\(turnSlots[i] == slot ? newName : t.name):** \(t.text)" }
            .joined(separator: "\n\n")
        return withPreamble(of: transcript, mergeAdjacentTurns(rebuilt))
    }
}
