import SwiftUI

// `SpeakerTranscript` (turn parsing + the per-line edit/reassign/relabel helpers)
// is the shared type: Shared/Pipeline/SpeakerTranscript.swift.

struct SpeakerTurnsView: View {
    let turns: [SpeakerTranscript.Turn]
    /// Hue slot per turn, from the SHARED rule (`SpeakerTurnStyle.slots`) — computed by the
    /// host, which holds the names roster, so this view never touches disk mid-playback.
    /// Empty (a preview / a caller that has no roster) → fall back to first-appearance order
    /// of the header text, which is what this view used to do on its own.
    var speakerSlots: [Int] = []
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
    /// A re-split is running: a tap on a turn does not open its editor (the Mac's read-only body, Q183).
    var readOnly: Bool = false

    @State private var editingIndex: Int?
    @State private var draft = ""
    @FocusState private var editingFocused: Bool

    /// The colour of each turn's speaker — the SHARED hue table keyed by the SHARED slot rule
    /// (`Palette.speakerHues` · `SpeakerTurnStyle`), so a speaker wears the same colour here
    /// and in the Mac's turn gutter. This used to be a private 4-colour table keyed on
    /// `turn.name`, which coloured one voice twice: conversation naming writes a speaker's
    /// first header as the full `[[Tiuri Hartog]]` and every later one as the short `Tiuri`.
    private var slotForTurn: [Int] {
        guard speakerSlots.count != turns.count else { return speakerSlots }
        var map: [String: Int] = [:]
        return turns.map { t in
            if let s = map[t.name] { return s }
            let s = map.count; map[t.name] = s; return s
        }
    }

    /// Cumulative SPOKEN-word count before each turn — maps the global active word index to
    /// a position within a turn. Excludes `[[img_NNN]]` markers (not spoken words) so the
    /// karaoke highlight doesn't drift past an inline photo.
    private var wordOffsets: [Int] {
        var offs: [Int] = []; var acc = 0
        for t in turns { offs.append(acc); acc += Self.spokenWordCount(t.text) }
        return offs
    }

    static func spokenWordCount(_ text: String) -> Int { ConversationKaraoke.spokenWords(text).count }

    var body: some View {
        let slots = slotForTurn
        let offsets = wordOffsets
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(turns.enumerated()), id: \.offset) { index, turn in
                turnRow(turn, index: index,
                        color: .skSpeakerHue(slot: slots[index]), wordOffset: offsets[index])
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
                .onTapGesture { if !readOnly { startEditing(turnIndex, fullText) } }
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

/// Which word is playing in a CONVERSATION: the same `KaraokeTrack` the monologue and the Mac
/// ask, over ALL turns' spoken words in order (Q183 / C239; the phone used to read
/// `Karaoke.activeWordIndex`, word N = timing N with no alignment). A word's index is global
/// across turns, `[[img_NNN]]` markers excluded (they are not spoken).
enum ConversationKaraoke {
    static func spokenWords(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.hasPrefix("[[img_") }
    }

    static func displayedWords(turns: [SpeakerTranscript.Turn]) -> [String] {
        turns.flatMap { spokenWords($0.text) }
    }

    static func track(turns: [SpeakerTranscript.Turn], timings: [WordTiming], duration: Double) -> KaraokeTrack {
        KaraokeTrack(displayedWords: displayedWords(turns: turns), timings: timings, duration: duration)
    }
}

/// Holds the conversation's track between 20 Hz ticks: the turns' words are split once, and the
/// track is rebuilt only when the turns, the timings or the duration change.
final class ConversationKaraokeCache {
    private var turns: [SpeakerTranscript.Turn] = []
    private var words: [String] = []
    private let tracks = KaraokeTrackCache()

    func track(turns newTurns: [SpeakerTranscript.Turn], timings: [WordTiming], duration: Double) -> KaraokeTrack {
        if newTurns != turns {
            turns = newTurns
            words = ConversationKaraoke.displayedWords(turns: newTurns)
        }
        return tracks.track(displayedWords: words, timings: timings, duration: duration)
    }
}
