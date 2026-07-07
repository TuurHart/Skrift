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
            // Width budget on the smallest target screen (390pt − 2×14 mount
            // padding = 362pt): lead 12 + cover 48(+4 pad) + 3×40 transport
            // + 3×4 spacing + spacer ≥4 + Capture pill ~92 (10 ❝ + 5 + ~50
            // text + 2×12 padding) + 4 + chevron 30 + trail 14 ≈ 340 ≤ 362 —
            // the pill can NEVER be squeezed into wrapping (and its text is
            // fixedSize + lineLimit(1) besides).
            HStack(spacing: 4) {
                Button {
                    showPlayer = true
                } label: {
                    BookCoverView(book: book, showsPlaceholderTitle: false)
                        .frame(width: 48, height: 48)
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
                        Text("❝")
                            .font(.system(size: 14, weight: .heavy))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        // "Add note" — unified verb (user decision 2026-07-07; was
                        // "Capture" while the player said "Add note" for the SAME flow).
                        Text("Add note")
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(Color.skAccentText)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.skAccent.opacity(0.2), in: .capsule)
                }
                .accessibilityIdentifier("mini-player-capture")
                .accessibilityLabel("Add note — pauses the book and builds a quote from what you just heard")

                Button {
                    showPlayer = true
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.skTextDim)
                        .frame(width: 30, height: 40)
                }
                .accessibilityIdentifier("mini-player-expand")
                .accessibilityLabel("Expand to the full player")
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            // 72pt: roomier than the original 54 (2026-06-11 "buttons too
            // small") but nothing like the grotesque 104 that shipped — and
            // sized by the width arithmetic above, not by feel (2026-06-12).
            .frame(height: 72)
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
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.skText)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
    }
}
