import SwiftUI

/// Audio transport: skip ±10 (SF Symbols gobackward.10 / goforward.10), play/pause,
/// a draggable click-to-seek scrubber, and a speed cycle. Duration label comes from
/// the file metadata so it shows even before the audio file loads.
struct NoteToolbar: View {
    @Bindable var audio: AudioController
    let durationSeconds: Double

    private var progress: Double {
        durationSeconds > 0 ? min(1, max(0, audio.currentTime / durationSeconds)) : 0
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
                Text(SkriftFormat.clock(durationSeconds))
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
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline.opacity(0.15)).frame(height: 5)
                Capsule().fill(Theme.accent).frame(width: geo.size.width * progress, height: 5)
                Circle().fill(.white).frame(width: 11, height: 11)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: max(0, geo.size.width * progress - 5.5))   // drag handle + position
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { v in
                    let p = min(1, max(0, v.location.x / geo.size.width))
                    audio.seek(to: p * durationSeconds)
                }
            )
        }
        .frame(height: 16)
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
