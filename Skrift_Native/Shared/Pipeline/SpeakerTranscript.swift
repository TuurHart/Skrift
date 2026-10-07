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

        static func == (l: Turn, r: Turn) -> Bool { l.name == r.name && l.text == r.text }

        /// The turn as written in a body: `**name:** text`.
        var markdown: String { "**\(name):** \(text)" }
    }

    /// Turns written back to a body: one `**name:** text` block each, joined by blank lines.
    static func markdown(_ turns: [Turn]) -> String { turns.map(\.markdown).joined(separator: "\n\n") }

    /// A turn header — a bold `**Name:**` anchored to the START of a line/paragraph.
    /// The line anchor (`(?m)^`) is deliberate: a hand-typed/LLM-formatted inline
    /// `**Pros:**` mid-sentence (e.g. an Apple Note) must NOT read as a speaker turn
    /// (the 2026-06-14 false-positive that skipped copy-edit on plain notes).
    /// Compiled ONCE (was a fresh `NSRegularExpression` per call — every one of
    /// `parse`/`parseWithPreamble`/`withPreamble` compiled its own, and `parse`
    /// alone is called from 5+ sites in `MemoDetailView` per commit; C277/C282).
    /// Internal, not private: `SpeakerTurnStyle` matches with the SAME regex to find where each
    /// header sits (this type parses to values and drops the ranges the renderers need).
    static let headerRegex = try! NSRegularExpression(pattern: #"(?m)^[ \t]*\*\*([^*\n]+?):\*\*[ \t]*"#)

    /// A header's label as PARSED: trimmed, `[[ ]]` stripped. `SpeakerTurnStyle` reads the
    /// same headers, so the strip lives here once.
    static func parsedLabel(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
    }

    /// Anything before the first turn header (e.g. an early `[[img_NNN]]` marker), trimmed;
    /// "" when there is no header or the text starts with one.
    static func preamble(of text: String?) -> String {
        guard let text,
              let first = headerRegex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
              first.range.location > 0 else { return "" }
        return (text as NSString).substring(to: first.range.location)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `parse`'s own single-slot cache, keyed on the transcript text: a commit
    /// that fires `parse` from more than one call site (recomputeSpans' onChange
    /// + the direct onCommit call, before that duplicate was removed; still true
    /// of the 5 call sites in the same file) now rescans the text at most once.
    /// DEBUG-only counter for tests; harmless to read/increment in Release.
    private static let parseCache = CommitOnceCache<String, [Turn]?>()
    #if DEBUG
    /// Exposed for `TypingPathCostTests` only — how many times `parseUncached`
    /// actually ran, to prove repeat `parse(_:)` calls on the same text are free.
    static var debugParseComputeCount: Int { parseCache.computeCount }
    #endif

    /// The `**Name:**` turns, or nil when fewer than 2 headers — `name` has the `[[ ]]`
    /// stripped (so `[[Tiuri Hartog]]` and a plain `Tiuri Hartog` header read the same).
    static func parse(_ transcript: String?) -> [Turn]? {
        guard let t = transcript else { return nil }
        return parseCache.value(for: t) { parseUncached(t) }
    }

    private static func parseUncached(_ t: String) -> [Turn]? {
        let ns = t as NSString
        let matches = headerRegex.matches(in: t, range: NSRange(location: 0, length: ns.length))
        guard matches.count >= 2 else { return nil }
        var turns: [Turn] = []
        for (i, m) in matches.enumerated() {
            let name = parsedLabel(ns.substring(with: m.range(at: 1)))
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
        guard let t = transcript, let turns = parse(t) else { return nil }
        return (preamble(of: t), turns)
    }

    /// Prepend the ORIGINAL transcript's preamble (anything before its first `**Name:**`
    /// header) onto a rebuilt turns body, so an edit / merge / rename never silently
    /// drops it. No-op when there's no preamble.
    static func withPreamble(of original: String?, _ body: String) -> String {
        let lead = preamble(of: original)
        return lead.isEmpty ? body : lead + "\n\n" + body
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

    /// THE conversation rule (D175 + D178, Q292), one for both apps: a RECORDING (`source ==
    /// .audio`) whose transcript parses with two or more line-anchored speaker headers, named or
    /// `Speaker N`. Distinct names are NOT required (Tuur 2026-10-03). A typed note or a capture
    /// is never a conversation, so bold labels in typed text (`**Pros:** a` / `**Cons:** b`)
    /// stay ordinary prose. The source is a required argument so no caller can forget the guard.
    static func isConversation(_ transcript: String?, source: NoteSourceType) -> Bool {
        source == .audio && parse(transcript) != nil
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
        let edited = turns.enumerated().map { i, t in
            Turn(name: t.name, text: i == index ? newText.trimmingCharacters(in: .whitespacesAndNewlines) : t.text)
        }
        return withPreamble(of: transcript, markdown(edited))
    }

    /// Reassign a SINGLE turn (by position) to another speaker, then re-merge — the
    /// per-line merge fix. Relabels only `turnAt`, NOT every turn of that speaker.
    static func reassign(_ transcript: String?, turnAt index: Int, to newName: String) -> String? {
        guard let turns = parse(transcript), index >= 0, index < turns.count else { return nil }
        return renamed(transcript) { i, _ in i == index ? newName : nil }
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
        return withPreamble(of: transcript, markdown(merged.map { Turn(name: $0.name, text: $0.text) }))
    }

    /// Rename EVERY turn whose parsed label satisfies `matches` (a speaker's whole voice, however
    /// its header is spelled — `[[Tiuri Hartog]]` first, `Tiuri` after), then merge adjacent
    /// same-speaker turns. nil when not attributed. The Mac's "name from the gutter" (Q87), where
    /// the per-turn slot map of `relabelSlot` does not exist.
    static func relabel(_ transcript: String?, where matches: (String) -> Bool, to newName: String) -> String? {
        renamed(transcript) { _, t in matches(t.name) ? newName : nil }
    }

    /// Rename every turn belonging to diarization SLOT `slot` (NOT every turn that happens
    /// to share the old display name), then merge adjacent same-speaker turns. `turnSlots`
    /// is the per-turn slot map persisted at diarize time. Returns nil when the map doesn't
    /// line up with the current turns (a structural edit since diarize) so the caller can
    /// fall back to name-based relabeling.
    static func relabelSlot(_ transcript: String?, turnSlots: [Int], slot: Int, to newName: String) -> String? {
        guard let turns = parse(transcript), turnSlots.count == turns.count else { return nil }
        return renamed(transcript) { i, _ in turnSlots[i] == slot ? newName : nil }
    }

    /// The ONE rebuild behind `reassign` / `relabel` / `relabelSlot`: each turn keeps its name
    /// unless `pick(index, turn)` returns a replacement; adjacent same-speaker turns then merge
    /// and the preamble is kept. nil when not attributed.
    static func renamed(_ transcript: String?, _ pick: (Int, Turn) -> String?) -> String? {
        guard let turns = parse(transcript) else { return nil }
        let rebuilt = markdown(turns.enumerated().map { i, t in Turn(name: pick(i, t) ?? t.name, text: t.text) })
        return withPreamble(of: transcript, mergeAdjacentTurns(rebuilt))
    }
}
