import SwiftUI

// MARK: - Bottom chrome (Option A — mocks/notes-bottom-chrome.html)

/// The Notes bottom row: the compact book pill, only while a book session is
/// active; otherwise nothing. Record lives in the header verb row on every width
/// (D136 dropped the red mic corner button). Its own view so only IT re-renders
/// on the session's 2 Hz playback ticks, never the memos list.
struct NotesBottomChrome: View {
    var session = AudiobookSession.shared
    /// Mirror of the continue-card's dismissal day: starting a book VOIDS a
    /// ×-for-today (re-engagement rule, device round 4). It lives HERE because
    /// this view stays mounted while the card's List row comes and goes.
    @AppStorage("continueCardDismissedDay") var cardDismissedDay = ""

    var body: some View {
        HStack(spacing: 16) {
            if session.isActive {
                AudiobookMiniPill()
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .animation(Theme.Motion.spring, value: session.isActive)
        .onChange(of: session.isActive) { _, active in
            if active {
                DevLog.log("bottomChrome void — session active, clearing cardDismissedDay (was '\(cardDismissedDay)')")
                cardDismissedDay = ""
            }
        }
    }
}

// MARK: - iPad shell helpers

/// Record presentation, per BASE's idiom rule: a centered card **sheet** on iPad
/// (m7 — `.presentationSizing(.form)`, the room stays dimmed-but-visible behind
/// it), a full-screen **cover** on the phone. Swapping the modifier type needs a
/// ViewModifier (an `if` in a chain can't).
struct RecordPresentation<Presented: View>: ViewModifier {
    @Binding var isPresented: Bool
    let isPad: Bool
    @ViewBuilder var presented: () -> Presented

    func body(content: Content) -> some View {
        Group {
            if isPad {
                content.sheet(isPresented: $isPresented) {
                    presented().presentationSizing(.form)
                }
            } else {
                content.fullScreenCover(isPresented: $isPresented, content: presented)
            }
        }
    }
}

/// One-shot ⌘F seam: `SkriftApp`'s `.commands` calls `requestFocus()`, and
/// `MemosListView` observes the bump to move keyboard focus into its search
/// field (the shared `SearchField` can't carry a focus binding). Mirrors the
/// `RecordingIntentBridge` singleton pattern.
final class SearchFocusBridge: ObservableObject {
    static let shared = SearchFocusBridge()
    private init() {}
    @Published private(set) var focusRequestID = 0
    func requestFocus() { focusRequestID += 1 }
}

/// The phone/iPad's colors for the shared m2 note card (NoteCardView) — lives here
/// (app target) and NOT in Theme.swift, which the widget/share-extension targets
/// also compile without Shared/UI in their sources.
extension NoteCardStyle {
    static let skrift = NoteCardStyle(
        accent: .skAccent, accentSoft: .skAccentSoft, accentText: .skAccentText,
        text: .skText, textDim: .skTextDim, textFaint: .skTextFaint,
        amber: .skAmber, green: .skGreen, red: .skRed,
        chipFill: .skElev, surface: .skSurface, border: .skBorder)
}
