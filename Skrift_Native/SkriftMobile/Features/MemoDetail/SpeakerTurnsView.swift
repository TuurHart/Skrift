import SwiftUI

// `SpeakerTranscript` (turn parsing + the per-line edit/reassign/relabel helpers)
// is the shared type: Shared/Pipeline/SpeakerTranscript.swift.

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
