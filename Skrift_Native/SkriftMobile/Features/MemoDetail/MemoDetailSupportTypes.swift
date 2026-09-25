import SwiftUI
import SwiftData
import UIKit
import QuickLook
import PhotosUI
import FluidAudio

// MARK: - Capture annotation editor

/// Simple editable body for C3 capture annotations — no karaoke, no markers.
/// Matches the transcript-editor style (dark surface, tint accent, dismiss on drag).
/// BORDERLESS (locked rule 2026-07-12: shared inputs never get bubble/box
/// chrome) — the annotation reads and edits like the note body itself, exactly
/// as the normal transcript editor does. Placeholder only when empty.
struct CaptureAnnotationEditor: View {
    @Binding var text: String
    @FocusState var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Add a note about this…")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.skTextFaint)
                    .padding(.top, 9)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $text)
                .font(.system(size: 15))
                .foregroundStyle(Color.skText)
                .tint(.skAccent)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .focused($focused)
        }
        .accessibilityIdentifier("capture-annotation-editor")
    }
}

// MARK: - Conversation turns (per-tick isolation)

/// Hosts `SpeakerTurnsView` and owns the karaoke tick: it observes the player
/// CLOCK, so during playback only this subtree re-evaluates per position change —
/// the page above it re-renders only on rare player state (play/pause).
struct ConversationTurnsSection: View {
    @ObservedObject var player: AudioPlayerModel
    @ObservedObject var clock: PlayerClock
    let timings: [WordTiming]
    let turns: [SpeakerTranscript.Turn]
    let speakerSlots: [Int]
    let tapToSeek: Bool
    let onTag: (Int, String) -> Void
    let onSeek: (Int) -> Void
    let onEditText: (Int, String) -> Void
    let imageURL: (Int) -> URL?

    var body: some View {
        SpeakerTurnsView(
            turns: turns,
            speakerSlots: speakerSlots,
            onTag: onTag,
            activeWord: (player.isPlaying && !timings.isEmpty)
                ? Karaoke.activeWordIndex(timings, at: clock.time) : nil,
            tapToSeek: tapToSeek,
            onSeek: onSeek,
            onEditText: onEditText,
            imageURL: imageURL
        )
    }
}

// MARK: - Player bar

struct PlayerBar: View {
    @ObservedObject var player: AudioPlayerModel
    // Position ticks are observed HERE only — the page tree above stays out of
    // the 20 Hz re-render loop (note-editing study 2026-07-06).
    @ObservedObject var clock: PlayerClock
    /// iPad note bar (signed mock A): the Mac's transport order — ⟲10 · play ·
    /// ⟳10, play in the middle. The phone keeps its own order (play first),
    /// which is why this is a flag and not a rewrite.
    var macTransportOrder = false
    /// How much room the transport actually has. The signed spec's promise is
    /// that the SCRUBBER gets the slack ("fills the whole available space…
    /// dynamically"), so when the column can't hold everything, controls stand
    /// down in order of what the scrubber can replace: first the ±10 skips
    /// (drag instead), then the time labels (the knob's position says it).
    enum Density { case full, tight, minimal }
    var density: Density = .full

    var body: some View {
        // The COMPACT pill (signed-off spec, −60% height): play · ±10 s ·
        // scrubber with times · speed — one ~44 pt row. The whole scrubber
        // zone is the drag target (no more fishing for a 3-pt slider).
        HStack(spacing: macTransportOrder ? 8 : 10) {
            if macTransportOrder && density == .full { skipBack }
            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.skAccent, in: .circle)
                    .shadow(color: .skAccent.opacity(0.38), radius: 5, y: 3)
            }
            .accessibilityIdentifier("play-button")
            .disabled(!player.hasAudio)

            if !macTransportOrder { skipBack }
            if density == .full { skipForward }

            // fixedSize: inside the iPad note bar these were wrapping to two
            // lines and squeezing the scrubber (2026-07-23 shot). The times take
            // their natural width; the scrubber keeps the rest.
            if density != .minimal {
                Text(timeString(clock.time))
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.skTextDim)
                    .fixedSize()
            }

            scrubber

            if density != .minimal {
                Text(timeString(player.duration))
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.skTextDim)
                    .fixedSize()
            }

            // fixedSize: without it the HStack compressed this button below its
            // text at portrait width and it rendered as an EMPTY capsule — a
            // control with nothing in it (2026-07-23 shot).
            Button { player.cycleRate() } label: {
                Text(rateLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.skText)
                    .lineLimit(1)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Color.skSurface, in: .rect(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle.sk(8).stroke(Color.skBorder, lineWidth: 1))
            }
            .fixedSize()
            .accessibilityIdentifier("speed-button")
        }
        .frame(height: 40)
    }

    var skipBack: some View {
        Button { player.skip(-10) } label: {
            Image(systemName: "gobackward.10")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.skText)
                .frame(width: 26, height: 32)
        }
        .accessibilityIdentifier("skip-back-button")
    }

    var skipForward: some View {
        Button { player.skip(10) } label: {
            Image(systemName: "goforward.10")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.skText)
                .frame(width: 26, height: 32)
        }
        .accessibilityIdentifier("skip-fwd-button")
    }

    /// Thin progress line with a knob; the FULL-HEIGHT zone around it accepts
    /// the scrub drag.
    var scrubber: some View {
        GeometryReader { geo in
            let progress = player.duration > 0 ? min(max(clock.time / player.duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14)).frame(height: 3.5)
                Capsule().fill(Color.skAccent)
                    .frame(width: max(3.5, geo.size.width * progress), height: 3.5)
                Circle().fill(.white)
                    .frame(width: 11, height: 11)
                    .offset(x: geo.size.width * progress - 5.5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard player.duration > 0 else { return }
                        player.seek(to: (v.location.x / geo.size.width) * player.duration)
                    }
            )
        }
        // THE flexible element of the bar (signed spec: the scrubber "fills the
        // whole available space… dynamically"). A GeometryReader has no ideal
        // width, so without an explicit max the HStack handed the slack to the
        // fixed controls and left the scrubber ~12pt wide. NO layoutPriority
        // here: with `maxWidth: .infinity` it would claim the entire proposal
        // and shove the fixed controls past the column edge — that overflow
        // clipped the note's own title and the Connections panel (shot fix-v1).
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .disabled(!player.hasAudio)
        .accessibilityIdentifier("player-scrubber")
    }

    var rateLabel: String {
        player.rate == 1 ? "1×" : (player.rate == 1.5 ? "1.5×" : "2×")
    }

    func timeString(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "0:00" }
        let total = Int(t)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Share sheet (share note OUT — survey fold)

/// Markdown/word-count helpers for sharing a note out. Pure, unit-testable.
enum MemoShare {
    /// "# Title\n\nbody" with `[[img_NNN]]` markers stripped (they mean
    /// nothing outside the app; the photos travel as files when needed).
    static func markdown(title: String?, body: String) -> String {
        let cleaned = body
            .replacingOccurrences(of: #"\[\[img_\d+\]\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title = title?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { return cleaned }
        return "# \(title)\n\n\(cleaned)"
    }

    /// Spoken-word count — markers aren't words.
    static func wordCount(of transcript: String?) -> Int {
        guard let t = transcript else { return 0 }
        return t.replacingOccurrences(of: #"\[\[img_\d+\]\]"#, with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace }).count
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Name-linking presentation state

/// A transcript name span the user tapped → drives the resolve confirmationDialog.
struct NameResolveTarget: Identifiable { let id = UUID(); let span: NameSpan }

/// The reversible "unlink" toast (mock build note #6) — `undo` restores the exact prior
/// resolutions.
struct NameUndoToast: Identifiable { let id = UUID(); let message: String; let undo: () -> Void }

/// Routes to the person editor (mock state 5): `canonical` set = open an existing card;
/// `prefillAlias` set = a "New person…" / "Someone else…" flow seeded with the spoken word.
struct PersonSheetRequest: Identifiable {
    let id = UUID()
    let canonical: String?
    let prefillAlias: String?
}

/// A PDF capture rendered INLINE in the note (signed-off mock
/// `pdf-inline-capture.html` variant A, round-4 ask "text, PDF, text — like
/// Apple Notes"): the first page as a full-width block with an "N pages"
/// chip; tapping anywhere opens the viewer (all pages + markup). Replaces
/// the file card for readable PDFs — doc scans and shared PDFs alike.
struct CapturePDFInlineBlock: View {
    let entry: PDFThumbnailLoader.Entry
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            Image(uiImage: entry.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.skBorder, lineWidth: 1)
                )
                .overlay(alignment: .bottomTrailing) {
                    if entry.pageCount > 1 {
                        Text("\(entry.pageCount) pages")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: .rect(cornerRadius: 7, style: .continuous))
                            .padding(9)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("capture-pdf-inline")
        .accessibilityLabel(entry.pageCount > 1 ? "PDF, \(entry.pageCount) pages" : "PDF")
    }
}
