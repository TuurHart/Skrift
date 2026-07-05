import SwiftUI

/// Parses + renders a speaker-attributed (conversation) transcript: `**Name:** text`
/// turns (the Markdown produced by `SpeakerFusion`, synced to the Mac, name-linked to
/// `[[Person]]`). Rendered WYSIWYG — bold name in a per-speaker color, a colored
/// left-edge + faint tint. An un-named "Speaker N" shows a "+ name" tag affordance.
enum SpeakerTranscript {
    struct Turn: Identifiable, Equatable { let id = UUID(); let name: String; let text: String }

    /// A turn header — a bold `**Name:**` anchored to the START of a line. The `(?m)^`
    /// anchor is deliberate: a mid-sentence `**Pros:**` (e.g. a hand-typed list) must NOT
    /// read as a speaker turn (the 2026-06-14 false-positive). Shared VERBATIM with the
    /// desktop `SpeakerTranscript.headerPattern` so the shared `Sanitiser`'s conversation
    /// parsing is identical on phone and Mac (no drift).
    private static let headerPattern = #"(?m)^[ \t]*\*\*([^*\n]+?):\*\*[ \t]*"#

    /// Turns if `transcript` is a `**Name:**` conversation (≥2 turns), else nil.
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

    /// The turns PLUS any leading text before the first turn header (e.g. an early
    /// `[[img_NNN]]` photo marker the phone inserted before the first spoken word). Lets
    /// the shared conversation linker PRESERVE that preamble instead of dropping it. nil
    /// when not ≥2 turns. Mirrors the desktop `SpeakerTranscript.parseWithPreamble` — the
    /// method the shared `Sanitiser.processConversation` calls.
    static func parseWithPreamble(_ transcript: String?) -> (preamble: String, turns: [Turn])? {
        guard let t = transcript, let turns = parse(t),
              let re = try? NSRegularExpression(pattern: headerPattern) else { return nil }
        let ns = t as NSString
        let firstLoc = re.firstMatch(in: t, range: NSRange(location: 0, length: ns.length))?.range.location ?? 0
        let preamble = ns.substring(to: firstLoc).trimmingCharacters(in: .whitespacesAndNewlines)
        return (preamble, turns)
    }

    /// Prepend the transcript's PREAMBLE (anything before the first `**Name:**`
    /// header — e.g. a leading `[[img_NNN]]` photo marker) onto a rebuilt turns
    /// body, so a turn edit / merge / rename never silently drops it. No-op when
    /// there's no preamble (the common case, incl. a rebuilt body that starts at a
    /// header — used to re-attach the ORIGINAL preamble after a rebuild).
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

    /// Replace a single turn's TEXT (by position), keeping its speaker — for inline editing
    /// (fix a transcription error, or move a boundary word between turns). Returns nil if
    /// not parseable. Does NOT re-fuse (names unchanged).
    static func setText(_ transcript: String?, turnAt index: Int, to newText: String) -> String? {
        guard let turns = parse(transcript), index >= 0, index < turns.count else { return nil }
        let body = turns.enumerated()
            .map { i, t in "**\(t.name):** \(i == index ? newText.trimmingCharacters(in: .whitespacesAndNewlines) : t.text)" }
            .joined(separator: "\n\n")
        return withPreamble(of: transcript, body)
    }

    /// Reassign a SINGLE turn (by position) to another speaker, then re-fuse — the per-line
    /// merge fix. Relabels only `turnAt`, NOT every turn of that speaker (so merging one
    /// mis-split line doesn't collapse the whole conversation). Returns nil if not parseable.
    static func reassign(_ transcript: String?, turnAt index: Int, to newName: String) -> String? {
        guard let turns = parse(transcript), index >= 0, index < turns.count else { return nil }
        let rebuilt = turns.enumerated()
            .map { i, t in "**\(i == index ? newName : t.name):** \(t.text)" }
            .joined(separator: "\n\n")
        return withPreamble(of: transcript, mergeAdjacentTurns(rebuilt))
    }

    /// Collapse consecutive turns by the SAME speaker into one (after a reassign/merge), so
    /// a turn folded into its neighbour reads as a single turn rather than two adjacent
    /// boxes. Re-emits the `**Name:** text` Markdown.
    static func mergeAdjacentTurns(_ transcript: String) -> String {
        guard let turns = parse(transcript) else { return transcript }
        var merged: [(name: String, text: String)] = []
        for t in turns {
            if let last = merged.last, last.name == t.name {
                merged[merged.count - 1].text += " " + t.text
            } else {
                merged.append((t.name, t.text))
            }
        }
        let body = merged.map { "**\($0.name):** \($0.text)" }.joined(separator: "\n\n")
        return withPreamble(of: transcript, body)
    }

    /// Rename every turn belonging to diarization SLOT `slot` (NOT every turn that happens
    /// to share the old display name), then merge adjacent same-speaker turns. `turnSlots`
    /// is the per-turn slot map (turn i → slot) persisted at diarize time. Returns nil when
    /// the map doesn't line up with the current turns (a structural edit since diarize) so
    /// the caller can fall back to name-based relabeling. This is what lets two speakers
    /// that share a name (e.g. one voice split into two slots, both "Tiuri") be renamed /
    /// enrolled independently.
    static func relabelSlot(_ transcript: String?, turnSlots: [Int], slot: Int, to newName: String) -> String? {
        guard let turns = parse(transcript), turnSlots.count == turns.count else { return nil }
        let rebuilt = turns.enumerated()
            .map { i, t in "**\(turnSlots[i] == slot ? newName : t.name):** \(t.text)" }
            .joined(separator: "\n\n")
        return withPreamble(of: transcript, mergeAdjacentTurns(rebuilt))
    }
}

struct SpeakerTurnsView: View {
    let turns: [SpeakerTranscript.Turn]
    /// Tap a turn's NAME → (turn index, speaker label). The index lets the parent merge
    /// just THIS line (per-line) while naming relabels the whole speaker.
    var onTag: (Int, String) -> Void = { _, _ in }
    /// Global active spoken-word index during playback (nil = paused → turns are editable).
    var activeWord: Int? = nil
    var tapToSeek: Bool = false
    var onSeek: (Int) -> Void = { _ in }
    /// Commit an edit to a turn's TEXT (fix a word, move a boundary word between turns).
    var onEditText: (Int, String) -> Void = { _, _ in }
    /// Resolve a `[[img_NNN]]` marker (1-based) to its photo file URL — inline photos coexist
    /// with speaker turns (the photo shows in the turn being spoken when it was taken).
    var imageURL: (Int) -> URL? = { _ in nil }

    @State private var editingIndex: Int?
    @State private var draft = ""
    @FocusState private var editingFocused: Bool

    /// Stable per-speaker color by first-appearance order.
    private var palette: [String: Color] {
        let colors: [Color] = [.skAccent, Color(hex: 0x2bb6a8), Color(hex: 0xe0823a), Color(hex: 0xc066d6)]
        var map: [String: Color] = [:]
        for t in turns where map[t.name] == nil { map[t.name] = colors[map.count % colors.count] }
        return map
    }

    /// Cumulative SPOKEN-word count before each turn — maps the global active word index to
    /// a position within a turn. Excludes `[[img_NNN]]` markers (not spoken words) so the
    /// karaoke highlight doesn't drift past an inline photo.
    private var wordOffsets: [Int] {
        var offs: [Int] = []; var acc = 0
        for t in turns { offs.append(acc); acc += Self.spokenWordCount(t.text) }
        return offs
    }

    static func spokenWordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).filter { !$0.hasPrefix("[[img_") }.count
    }

    var body: some View {
        let colorFor = palette
        let offsets = wordOffsets
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(turns.enumerated()), id: \.offset) { index, turn in
                turnRow(turn, index: index, color: colorFor[turn.name] ?? .skAccent, wordOffset: offsets[index])
            }
        }
    }

    @ViewBuilder private func turnRow(_ turn: SpeakerTranscript.Turn, index: Int, color c: Color, wordOffset: Int) -> some View {
        let unnamed = SpeakerTranscript.isUnnamed(turn.name)
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 3)
            VStack(alignment: .leading, spacing: 5) {
                Button { onTag(index, turn.name) } label: {
                    HStack(spacing: 6) {
                        Circle().fill(c).frame(width: 7, height: 7)
                        Text(turn.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(unnamed ? Color.skTextDim : c)
                        Text(unnamed ? "+ name" : "edit")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(c)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(c.opacity(0.16), in: Capsule())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tag-speaker-\(turn.name)")
                turnBody(turn, index: index, wordOffset: wordOffset)
            }
        }
        .padding(.vertical, 9).padding(.leading, 5).padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(c.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    /// Editing (paused, tapped) → an inline field; otherwise the turn renders as text +
    /// inline `[[img_NNN]]` photos (split into segments), each text segment plain (paused)
    /// or karaoke-highlighted (playing). Tap a text segment (paused) to edit the turn.
    @ViewBuilder private func turnBody(_ turn: SpeakerTranscript.Turn, index: Int, wordOffset: Int) -> some View {
        if editingIndex == index {
            VStack(alignment: .trailing, spacing: 4) {
                TextField("", text: $draft, axis: .vertical)
                    .font(.system(size: 15.5)).foregroundStyle(Color.skText).tint(.skAccent)
                    .lineSpacing(3)
                    .focused($editingFocused)
                    .accessibilityIdentifier("turn-editor-\(index)")
                    .onChange(of: editingFocused) { _, focused in if !focused { commit() } }
                Button("Done") { editingFocused = false }
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.skAccent)
                    .accessibilityIdentifier("turn-editor-done")
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(segmentItems(turn.text, base: wordOffset)) { item in
                    switch item.seg {
                    case .text(let s): textSegment(s, wordOffset: item.offset, turnIndex: index, fullText: turn.text)
                    case .image(let n): ImageEmbed(url: imageURL(n))
                    }
                }
            }
        }
    }

    @ViewBuilder private func textSegment(_ s: String, wordOffset: Int, turnIndex: Int, fullText: String) -> some View {
        if let active = activeWord, tapToSeek {
            karaokeWords(s, wordOffset: wordOffset, active: active)
        } else if let active = activeWord {
            Text(karaokeAttr(s, wordOffset: wordOffset, active: active))
                .font(.system(size: 15.5)).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(s)
                .font(.system(size: 15.5)).foregroundStyle(Color.skText).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { startEditing(turnIndex, fullText) }
        }
    }

    private enum Seg { case text(String); case image(Int) }
    private struct SegItem: Identifiable { let id: Int; let seg: Seg; let offset: Int }

    /// Split a turn's text into text/photo segments, tracking the spoken-word offset before
    /// each (photos don't advance the word index — so karaoke stays aligned across images).
    private func segmentItems(_ text: String, base: Int) -> [SegItem] {
        let ns = text as NSString
        let regex = try? NSRegularExpression(pattern: #"\[\[img_(\d+)\]\]"#)
        var out: [SegItem] = []
        var last = 0, wordIdx = base, sid = 0
        func addText(_ chunk: String) {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            out.append(SegItem(id: sid, seg: .text(trimmed), offset: wordIdx)); sid += 1
            wordIdx += Self.spokenWordCount(trimmed)
        }
        regex?.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            if m.range.location > last {
                addText(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            }
            let n = Int(ns.substring(with: m.range(at: 1))) ?? 0
            out.append(SegItem(id: sid, seg: .image(n), offset: wordIdx)); sid += 1
            last = m.range.location + m.range.length
        }
        if last < ns.length { addText(ns.substring(from: last)) }
        if out.isEmpty { out.append(SegItem(id: 0, seg: .text(text), offset: base)) }
        return out
    }

    private func startEditing(_ index: Int, _ text: String) {
        guard editingIndex != index else { return }
        if editingIndex != nil { commit() }       // commit the turn already being edited first
        editingIndex = index; draft = text
        DispatchQueue.main.async { editingFocused = true }
    }

    private func commit() {
        guard let i = editingIndex else { return }
        editingIndex = nil
        onEditText(i, draft)
    }

    /// AttributedString with played words dimmed + the active word accented (matches the
    /// non-conversation karaoke view).
    private func karaokeAttr(_ text: String, wordOffset: Int, active: Int) -> AttributedString {
        var attr = AttributedString()
        var wordIndex = wordOffset
        var buffer = ""
        func flush() {
            guard !buffer.isEmpty else { return }
            var piece = AttributedString(buffer)
            if wordIndex < active { piece.foregroundColor = .skTextDim }
            else if wordIndex == active { piece.foregroundColor = .skAccent }
            else { piece.foregroundColor = .skText }
            attr += piece; wordIndex += 1; buffer = ""
        }
        for ch in text {
            if ch.isWhitespace { flush(); attr += AttributedString(String(ch)) } else { buffer.append(ch) }
        }
        flush()
        return attr
    }

    @ViewBuilder private func karaokeWords(_ text: String, wordOffset: Int, active: Int) -> some View {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        FlowLayout(spacing: 5, lineSpacing: 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                let gi = wordOffset + i
                Text(word).font(.system(size: 15.5))
                    .foregroundStyle(gi < active ? Color.skTextDim : (gi == active ? Color.skAccent : Color.skText))
                    .contentShape(Rectangle())
                    .onTapGesture { onSeek(gi) }
            }
        }
    }
}
