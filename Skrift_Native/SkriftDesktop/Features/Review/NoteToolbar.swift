import SwiftUI

/// Audio transport: skip ±10 (SF Symbols gobackward.10 / goforward.10), play/pause,
/// a draggable click-to-seek scrubber, and a speed cycle. Duration label comes from
/// the file metadata so it shows even before the audio file loads.
struct NoteToolbar: View {
    @Bindable var audio: AudioController
    /// Phone-metadata duration hint; the loaded file's real duration wins once known.
    let durationSeconds: Double

    /// Real loaded duration when available, else the metadata hint (so the label reads
    /// something before the file loads).
    private var total: Double { audio.duration > 0 ? audio.duration : durationSeconds }

    private var progress: Double {
        total > 0 ? min(1, max(0, audio.currentTime / total)) : 0
    }

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                skipButton("gobackward.10") { audio.skip(-10) }
                Button(action: audio.playPause) {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.accent, in: Circle())
                }
                .buttonStyle(.plain)
                skipButton("goforward.10") { audio.skip(10) }
            }

            HStack(spacing: 11) {
                Text(SkriftFormat.clock(audio.currentTime))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                scrubber
                Text(SkriftFormat.clock(total))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }

            Button(action: audio.cycleRate) {
                Text("\(rateLabel)×")
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.hairline.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    private var scrubber: some View {
        TrackSlider(fraction: progress, trackHeight: 5, thumbSize: 11) { f in
            audio.seek(to: f * total)
        }
        .frame(maxWidth: .infinity)
    }

    private func skipButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(Theme.hairline.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var rateLabel: String {
        let r = audio.rate
        return r == r.rounded() ? String(Int(r)) : String(format: "%g", r)
    }
}
