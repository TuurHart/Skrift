import SwiftUI

/// DESIGN MOCK of conversation mode (no real diarization — static data). Shows the
/// speaker-split note: bold-name turns (the `**Name:** text` Markdown that syncs to
/// Obsidian) rendered WYSIWYG with a subtle per-speaker color + colored left edge,
/// plus the tag-as-you-go affordance (an un-named speaker shows "+ name"). Gated by
/// `-conversationMock` so it can be screenshotted for design review.
struct ConversationMockView: View {
    private struct Turn: Identifiable {
        let id = UUID(); let speaker: String; let named: Bool; let colorIndex: Int; let text: String
    }

    private let turns: [Turn] = [
        .init(speaker: "Tiuri Hartog", named: true, colorIndex: 0,
              text: "If conversation mode works, if I talk, then what if you talk? And now if I talk, it'll only split it afterwards, I'm assuming."),
        .init(speaker: "Speaker 2", named: false, colorIndex: 1,
              text: "Yeah, but can we split the conversation during this pre-recording as well? Because now you'll see if it saves."),
        .init(speaker: "Tiuri Hartog", named: true, colorIndex: 0,
              text: "Yeah. But it would be cool if it noticed while you were talking — like it made a little ding or something."),
    ]

    private func speakerColor(_ i: Int) -> Color { [Color.skAccent, Color(hex: 0x2bb6a8)][i % 2] }

    var body: some View {
        ZStack {
            Color.skBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Harbour chat at dawn")
                        .font(.system(size: 24, weight: .bold)).foregroundStyle(Color.skText)

                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        chip("Today · 08:54", nil)
                        chip("Alfama, Lisbon", "mappin.circle.fill")
                        chip("Conversation", "person.2.wave.2.fill")
                    }
                    .padding(.top, 10)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(turns) { turnView($0) }
                    }
                    .padding(.top, 18)
                }
                .padding(.horizontal, Theme.Space.margin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private func turnView(_ t: Turn) -> some View {
        let c = speakerColor(t.colorIndex)
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 3)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle().fill(c).frame(width: 7, height: 7)
                    Text(t.speaker)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(t.named ? c : Color.skTextDim)
                    if !t.named {
                        Text("+ name")
                            .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(c)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(c.opacity(0.16), in: Capsule())
                    }
                }
                Text(t.text)
                    .font(.system(size: 15.5)).foregroundStyle(Color.skText).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 9).padding(.leading, 5).padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(c.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func chip(_ text: String, _ symbol: String?) -> some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9)) }
            Text(text).font(.system(size: 11))
        }
        .foregroundStyle(Color.skTextDim)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.skElev, in: Capsule())
    }
}
