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
    /// Tag-as-you-go: tap an un-named speaker to assign a name (wired by the parent).
    var onTag: (String) -> Void = { _ in }

    /// Stable per-speaker color by first-appearance order.
    private var palette: [String: Color] {
        let colors: [Color] = [.skAccent, Color(hex: 0x2bb6a8), Color(hex: 0xe0823a), Color(hex: 0xc066d6)]
        var map: [String: Color] = [:]
        for t in turns where map[t.name] == nil { map[t.name] = colors[map.count % colors.count] }
        return map
    }

    var body: some View {
        let colorFor = palette
        VStack(alignment: .leading, spacing: 12) {
            ForEach(turns) { turn in
                turnRow(turn, color: colorFor[turn.name] ?? .skAccent)
            }
        }
    }

    @ViewBuilder private func turnRow(_ turn: SpeakerTranscript.Turn, color c: Color) -> some View {
        let unnamed = SpeakerTranscript.isUnnamed(turn.name)
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 3)
            VStack(alignment: .leading, spacing: 5) {
                // The whole label is tappable — assign an un-named speaker OR correct a
                // wrong one (diarization sometimes swaps two people).
                Button { onTag(turn.name) } label: {
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
                Text(turn.text)
                    .font(.system(size: 15.5)).foregroundStyle(Color.skText).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 9).padding(.leading, 5).padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(c.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
