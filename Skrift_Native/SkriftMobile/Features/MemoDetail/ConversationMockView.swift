import SwiftUI

/// DESIGN MOCK of a conversation note (gated by `-conversationMock`). Feeds a sample
/// `**Name:**` transcript through the SAME `SpeakerTurnsView` the real detail uses, so
/// the mock and production rendering can't drift.
struct ConversationMockView: View {
    private static let sample = """
    **Tiuri Hartog:** If conversation mode works, if I talk, then what if you talk? And now if I talk, it'll only split it afterwards, I'm assuming.

    **Speaker 2:** Yeah, but can we split the conversation during this pre-recording as well? Because now you'll see if it saves.

    **Tiuri Hartog:** Yeah. But it would be cool if it noticed while you were talking — like it made a little ding or something.
    """

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
                    SpeakerTurnsView(turns: SpeakerTranscript.parse(Self.sample) ?? [])
                        .padding(.top, 18)
                }
                .padding(.horizontal, Theme.Space.margin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
