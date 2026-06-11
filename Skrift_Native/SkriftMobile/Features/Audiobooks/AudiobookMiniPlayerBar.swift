import SwiftUI

/// The conditional mini-player (CROSS-LANE CONTRACT C3 — mock state 5): a
/// Bound-style glass capsule that exists ONLY while a book session is active
/// (`AudiobookSession.shared.isActive`). Contents, locked by the mock:
/// cover · ⟲15 · play/pause · 15⟳ · ❝ Capture (the one labeled verb) · ˄ expand.
///
/// Self-contained: the mounting lane just drops `AudiobookMiniPlayerBar()`
/// into the memos list overlay (gated on `isActive`); this view also renders
/// nothing itself when no book is loaded, presents the full player (˄ / cover
/// tap) and the capture flow (❝) on its own, and pauses the book before
/// capture.
struct AudiobookMiniPlayerBar: View {
    @ObservedObject private var session = AudiobookSession.shared

    @State private var showPlayer = false
    @State private var showCapture = false

    var body: some View {
        if let book = session.book {
            HStack(spacing: 2) {
                Button {
                    showPlayer = true
                } label: {
                    BookCoverView(book: book, showsPlaceholderTitle: false)
                        .frame(width: 38, height: 38)
                        .clipShape(.rect(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mini-player-cover")
                .accessibilityLabel("\(book.title) — open the player")
                .padding(.trailing, 4)

                transportButton(systemImage: "gobackward.15", id: "mini-player-back-15", label: "Back 15 seconds") {
                    session.skip(-AudiobookSession.skipInterval)
                }
                transportButton(
                    systemImage: session.isPlaying ? "pause.fill" : "play.fill",
                    id: "mini-player-play",
                    label: session.isPlaying ? "Pause" : "Play"
                ) {
                    session.togglePlay()
                }
                transportButton(systemImage: "goforward.15", id: "mini-player-forward-15", label: "Forward 15 seconds") {
                    session.skip(AudiobookSession.skipInterval)
                }

                Spacer(minLength: 4)

                Button {
                    session.pause()
                    showCapture = true
                } label: {
                    HStack(spacing: 5) {
                        Text("❝").font(.system(size: 13, weight: .heavy))
                        Text("Capture").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Color.skAccentText)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Color.skAccent.opacity(0.2), in: .capsule)
                }
                .accessibilityIdentifier("mini-player-capture")
                .accessibilityLabel("Capture — pauses and proposes the last 30 seconds")

                Button {
                    showPlayer = true
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.skTextDim)
                        .frame(width: 26, height: 32)
                }
                .accessibilityIdentifier("mini-player-expand")
                .accessibilityLabel("Expand to the full player")
            }
            .padding(.leading, 7)
            .padding(.trailing, 9)
            .frame(height: 54)
            .background(.ultraThinMaterial, in: .capsule)
            .overlay(
                Capsule()
                    .strokeBorder(Color.skBorder, lineWidth: 0.5)
            )
            .overlay(
                // The mock's glass sheen.
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.09), .clear],
                                         startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
            .fullScreenCover(isPresented: $showPlayer) {
                AudiobookPlayerView()
            }
            .fullScreenCover(isPresented: $showCapture) {
                QuoteCaptureFlowView()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("audiobook-mini-player")
        }
    }

    private func transportButton(systemImage: String, id: String, label: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.skText)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
    }
}
