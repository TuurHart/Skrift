import SwiftUI

/// The at-rest "Continue listening" card on Notes (mock
/// `notes-compact-header.html`; the Hendri-debate resolution in
/// `notes-book-presence-debate.html`): **cards for starting, chrome for
/// controlling**. While NO session is live, the most recently played book
/// appears as a CONTENT card above search — ▶ resumes in one tap (the session
/// starts playing and the V2a pill takes over the bottom row), the card body
/// opens the player, × dismisses it for the rest of the day. Renders nothing
/// while a session is live, when no book has ever been played, or after a
/// dismissal today.
///
/// This replaces cold-launch `restoreOnLaunch()`: no phantom paused AVPlayer
/// at launch — the card reads the library, and a session exists only once you
/// actually play.
struct ContinueListeningCard: View {
    /// Body-tap opens the player — presented by the OWNER (a `fullScreenCover`
    /// must not hang off this view: as a List row it unmounts the moment the
    /// session starts, which would tear the cover down mid-present).
    var openPlayer: () -> Void = {}

    @ObservedObject private var session = AudiobookSession.shared
    @ObservedObject private var store = AudiobookLibraryStore.shared
    /// "yyyy-MM-dd" of the last ×-dismissal — the card stays gone for that day.
    /// (The play-again VOIDS-dismissal rule lives in `NotesBottomChrome`, which
    /// stays mounted while this row comes and goes.)
    @AppStorage("continueCardDismissedDay") private var dismissedDay = ""

    var body: some View {
        if !session.isActive,
           dismissedDay != Self.today(),
           let book = store.sortedByRecent.first,
           book.lastPlayedAt != nil {
            card(book)
        }
    }

    private func card(_ book: Audiobook) -> some View {
        HStack(spacing: 12) {
            // Body = the book: tap → open the player (paused, where you left off).
            Button {
                if session.open(book) { openPlayer() }
            } label: {
                HStack(spacing: 12) {
                    BookCoverView(book: book, showsPlaceholderTitle: false)
                        .frame(width: 48, height: 48)
                        .clipShape(.rect(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("CONTINUE LISTENING")
                            .font(.system(size: 10, weight: .bold))
                            .kerning(0.5)
                            .foregroundStyle(Color.skAccentText)
                        Text(book.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.skText)
                            .lineLimit(1)
                        Text(AudiobookTime.clock(book.timeLeft) + " left")
                            .font(.system(size: 11.5))
                            .monospacedDigit()
                            .foregroundStyle(Color.skTextDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("continue-card-body")
            .accessibilityLabel("\(book.title), \(AudiobookTime.clock(book.timeLeft)) left — open the player")

            Button {
                DevLog.log("card x-dismiss TAPPED — writing dismissedDay=\(Self.today())")
                withAnimation(Theme.Motion.spring) { dismissedDay = Self.today() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.skTextFaint)
                    .frame(width: 26, height: 32)
                    .contentShape(Rectangle())
            }
            // .borderless is LOAD-BEARING inside a List row: without it the row
            // hijacks taps and fires sibling buttons (device round 6, build 50:
            // tapping × auto-played the book).
            .buttonStyle(.borderless)
            .accessibilityIdentifier("continue-card-dismiss")
            .accessibilityLabel("Hide for today")

            // ▶ = the one-tap resume the whole card exists for.
            Button {
                session.open(book, autoplay: true)
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.skAccent)
                        .frame(width: 44, height: 44)
                        .shadow(color: Color.skAccent.opacity(0.4), radius: 6, y: 2)
                    Image(systemName: "play.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.borderless)   // see dismiss button — List-row tap hijack
            .accessibilityIdentifier("continue-card-play")
            .accessibilityLabel("Resume \(book.title)")
        }
        .padding(EdgeInsets(top: 12, leading: 13, bottom: 12, trailing: 13))
        .background(Color.skSurface, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle.sk(16)
                .stroke(Color.skAccent.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("continue-listening-card")
    }

    /// Local calendar day string ("2026-07-07") for the dismiss-for-today gate.
    static func today(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
