import SwiftUI

/// Parses + renders a speaker-attributed (conversation) transcript: `**Name:** text`
/// turns (the Markdown produced by `SpeakerFusion`, synced to the Mac, name-linked to
/// `[[Person]]`). Rendered WYSIWYG — bold name in a per-speaker color, a colored
/// left-edge + faint tint. An un-named "Speaker N" shows a "+ name" tag affordance.
enum SpeakerTranscript {
    struct Turn: Identifiable, Equatable { let id = UUID(); let name: String; let text: String }

    /// Turns if `transcript` is a `**Name:**` conversation (≥2 turns), else nil.
    static func parse(_ transcript: String?) -> [Turn]? {
        guard let t = transcript,
              let re = try? NSRegularExpression(pattern: #"\*\*([^*\n]+?):\*\*[ \t]*"#) else { return nil }
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
        return turns.enumerated()
            .map { i, t in "**\(t.name):** \(i == index ? newText.trimmingCharacters(in: .whitespacesAndNewlines) : t.text)" }
            .joined(separator: "\n\n")
    }

    /// Reassign a SINGLE turn (by position) to another speaker, then re-fuse — the per-line
    /// merge fix. Relabels only `turnAt`, NOT every turn of that speaker (so merging one
    /// mis-split line doesn't collapse the whole conversation). Returns nil if not parseable.
    static func reassign(_ transcript: String?, turnAt index: Int, to newName: String) -> String? {
        guard let turns = parse(transcript), index >= 0, index < turns.count else { return nil }
        let rebuilt = turns.enumerated()
            .map { i, t in "**\(i == index ? newName : t.name):** \(t.text)" }
            .joined(separator: "\n\n")
        return mergeAdjacentTurns(rebuilt)
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
        return merged.map { "**\($0.name):** \($0.text)" }.joined(separator: "\n\n")
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

    /// Cumulative spoken-word count before each turn — maps the global active word index
    /// to a position within a turn (image markers aren't a concern in turn transcripts).
    private var wordOffsets: [Int] {
        var offs: [Int] = []; var acc = 0
        for t in turns { offs.append(acc); acc += t.text.split(whereSeparator: { $0.isWhitespace }).count }
        return offs
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

    /// Editing (paused, tapped) → an inline field; playing → karaoke (active word
    /// highlighted, optional tap-to-seek); otherwise plain text, tap to edit.
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
        } else if let active = activeWord, tapToSeek {
            karaokeWords(turn.text, wordOffset: wordOffset, active: active)
        } else if let active = activeWord {
            Text(karaokeAttr(turn.text, wordOffset: wordOffset, active: active))
                .font(.system(size: 15.5)).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(turn.text)
                .font(.system(size: 15.5)).foregroundStyle(Color.skText).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { startEditing(index, turn.text) }
        }
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
