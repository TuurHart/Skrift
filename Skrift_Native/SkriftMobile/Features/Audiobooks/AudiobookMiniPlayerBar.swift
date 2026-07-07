import SwiftUI

/// The FULL mini-player bar (CROSS-LANE CONTRACT C3): a Bound-style glass
/// capsule that exists ONLY while a book session is active
/// (`AudiobookSession.shared.isActive`). Since the 2026-07-07 bottom-chrome
/// redesign (`mocks/notes-bottom-chrome.html`, Option A) it lives on the
/// **Books tab only**; the Notes tab mounts the compact `AudiobookMiniPill`
/// beside the record button instead, and Journal/Settings carry nothing.
/// Contents: cover (→ player) · ⟲15 · play/pause · 15⟳ · ❝ Add note.
/// The ˄ expand chevron was cut (duplicate of the cover tap).
///
/// Self-contained: mount it gated on `isActive`; it renders nothing when no
/// book is loaded, presents the full player (cover tap) and the capture flow
/// (❝) on its own, and pauses the book before capture.
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
                // The ˄ expand chevron was CUT 2026-07-07 (user call): it duplicated
                // tapping the cover, and the width buys breathing room.
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

/// The COMPACT book pill for the Notes tab (2026-07-07 bottom-chrome redesign;
/// interior = V2a of `mocks/notes-pill-v2-iterations.html`, picked after the
/// build-46 device round + Henry's "crowded" note): cover · time-left ·
/// ❝ Add note · a FILLED accent play — 60pt tall, sharing ONE bottom row with
/// the record button so the two never stack or overlap (the build-40
/// regression). The middle is TIME-ONLY by design: a title can't fit legibly
/// beside a labeled chip + play at 390pt (build-46 truth) — the title is one
/// tap away, because the pill BODY (cover + middle) opens the player, which is
/// what the thumb expects. Skips and the chevron are deliberately absent —
/// they live in the full player, the Books-tab bar, and the lock screen.
/// Renders nothing when no book session is active.
struct AudiobookMiniPill: View {
    @ObservedObject private var session = AudiobookSession.shared

    @State private var showPlayer = false
    @State private var showCapture = false

    var body: some View {
        if let book = session.book {
            HStack(spacing: 8) {
                // Cover + the flexible time-left middle are ONE tap target: the
                // pill body is the book — tap it, the player opens.
                Button {
                    showPlayer = true
                } label: {
                    HStack(spacing: 8) {
                        BookCoverView(book: book, showsPlaceholderTitle: false)
                            .frame(width: 44, height: 44)
                            .clipShape(.rect(cornerRadius: 10, style: .continuous))
                        Text(AudiobookTime.clock(max(0, session.duration - session.currentTime)) + " left")
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.skTextDim)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mini-pill-cover")
                .accessibilityLabel("\(book.title) — open the player")

                Button {
                    session.pause()
                    showCapture = true
                } label: {
                    HStack(spacing: 5) {
                        Text("\u{275D}")
                            .font(.system(size: 14, weight: .heavy))
                        Text("Add note")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(Color.skAccentText)
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(Color.skAccent.opacity(0.2), in: .capsule)
                }
                .accessibilityIdentifier("mini-pill-capture")
                .accessibilityLabel("Add note — pauses the book and builds a quote from what you just heard")

                // V2a: play is the pill's hero — a filled accent circle at the end.
                Button {
                    session.togglePlay()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.skAccent)
                            .frame(width: 42, height: 42)
                            .shadow(color: Color.skAccent.opacity(0.4), radius: 6, y: 2)
                        Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .contentShape(Circle())
                }
                .accessibilityIdentifier("mini-pill-play")
                .accessibilityLabel(session.isPlaying ? "Pause" : "Play")
            }
            .padding(.leading, 8)
            .padding(.trailing, 9)
            .frame(height: 60)
            .background(.ultraThinMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.skBorder, lineWidth: 0.5))
            .overlay(
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.09), .clear],
                                         startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.45), radius: 14, y: 7)
            .fullScreenCover(isPresented: $showPlayer) {
                AudiobookPlayerView()
            }
            .fullScreenCover(isPresented: $showCapture) {
                QuoteCaptureFlowView()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("audiobook-mini-pill")
        }
    }
}
