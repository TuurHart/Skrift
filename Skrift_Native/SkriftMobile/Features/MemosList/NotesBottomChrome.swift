import SwiftUI

// MARK: - Bottom chrome (Option A — mocks/notes-bottom-chrome.html)

/// The Notes bottom row: compact book pill LEFT (only while a book session is
/// active) + the record button RIGHT — one 60pt row, explicitly side by side so
/// the two can never stack or overlap (the build-40 regression). No session →
/// just the record button in the right corner. Its own view so only IT
/// re-renders on the session's 2 Hz playback ticks, never the memos list.
private struct NotesBottomChrome: View {
    /// false at iPad-regular width, where Record moved into the header verb row
    /// (2026-08-18) — the row then carries only the book pill (or nothing).
    var showRecordButton = true
    let onRecord: () -> Void
    private var session = AudiobookSession.shared
    /// Mirror of the continue-card's dismissal day: starting a book VOIDS a
    /// ×-for-today (re-engagement rule, device round 4). It lives HERE because
    /// this view stays mounted while the card's List row comes and goes.
    @AppStorage("continueCardDismissedDay") private var cardDismissedDay = ""

    var body: some View {
        // 16pt pill↔record gap (V2a "real air" — Henry's separation note).
        HStack(spacing: 16) {
            if session.isActive {
                AudiobookMiniPill()
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Spacer(minLength: 0)
            }
            if showRecordButton { recordButton }
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

    private var recordButton: some View {
        Button(action: onRecord) {
            Image(systemName: "mic.fill")
                .font(.system(size: 23))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Color.skRed, in: .circle)
                .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 4))
                .shadow(color: .skRed.opacity(0.45), radius: 12, y: 8)
        }
        .accessibilityIdentifier("new-recording-button")
    }
}

// MARK: - iPad shell helpers

/// A memo card's background. Identical to `.skCard()` when unselected (so the
/// phone — where `selected` is never true — is byte-for-byte unchanged); an
/// accent-soft fill + accent hairline when it backs the split-view detail pane
/// (m1). Kept local (not folded into `.skCard()`) because that shared helper is
/// read-only this wave.
private struct SelectableCard: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        content
            .padding(Theme.Space.cardPadding)
            .background(selected ? Color.skAccentSoft : Color.skSurface,
                        in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle.sk(Theme.Radius.card)
                    .stroke(selected ? Color.skAccent.opacity(0.5) : Color.skBorder, lineWidth: 1)
            )
    }
}

/// Record presentation, per BASE's idiom rule: a centered card **sheet** on iPad
/// (m7 — `.presentationSizing(.form)`, the room stays dimmed-but-visible behind
/// it), a full-screen **cover** on the phone. Swapping the modifier type needs a
/// ViewModifier (an `if` in a chain can't).
private struct RecordPresentation<Presented: View>: ViewModifier {
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
