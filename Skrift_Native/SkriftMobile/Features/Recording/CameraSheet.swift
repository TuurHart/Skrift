import SwiftUI

/// The on-demand camera viewfinder that slides up while recording continues
/// (mockup5 middle). Shutter captures a timestamped photo at the current
/// recording offset; pinch / .5×·1×·2× control zoom; the flip button swaps
/// front/back (front hides the zoom presets — the selfie camera has no 0.5×
/// ultrawide and preset zoom is pointless at arm's length; pinch still works,
/// floored at 1×); Done dismisses back to the caption-first record screen. The
/// real preview + zoom are device-owed; the Simulator shows a placeholder
/// viewfinder.
struct CameraSheet: View {
    @ObservedObject var camera: PhotoCaptureService
    /// The current recording offset, read AT SHUTTER TIME — taking it as a
    /// plain value would re-render the sheet's parent on every timer tick.
    let recordingOffset: () -> Double
    let onDone: () -> Void

    @State private var zoom: CGFloat = 1
    /// The zoom when the current pinch began; nil between pinches.
    @State private var pinchStart: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            // No grab-handle pill: the sheet is a fixed overlay, nothing drags.
            viewfinder
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                .padding(.top, 16)
                .padding(.horizontal, 16)

            // Shutter centered on screen; thumbnails left, Done right.
            ZStack {
                Button(action: capture) {
                    Circle().fill(.white).frame(width: 64, height: 64)
                        .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 4))
                }
                .accessibilityIdentifier("shutter-button")

                HStack {
                    thumbnails
                    Spacer()
                    Button(action: flip) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.12), in: .circle)
                    }
                    .accessibilityIdentifier("camera-flip")
                    Button(action: onDone) {
                        Text("Done").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.skAccent)
                    }
                    .accessibilityIdentifier("camera-done")
                    .padding(.leading, 10)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 540)
        .background(Color(hex: 0x0a0c12))
        .clipShape(.rect(topLeadingRadius: 28, topTrailingRadius: 28))
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .stroke(Color.skBorder, lineWidth: 1)
        )
    }

    private var viewfinder: some View {
        ZStack {
            if camera.mock {
                LinearGradient(colors: [Color(hex: 0x2a3350), Color(hex: 0x10131d)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "camera.fill")
                    .font(.largeTitle).foregroundStyle(.white.opacity(0.3))
                    .accessibilityIdentifier("camera-placeholder")
            } else {
                CameraPreviewView(session: camera.session)
            }

            VStack {
                Spacer()
                // Front camera: no preset row — there's no 0.5× ultrawide and
                // preset zoom is pointless at arm's length (pinch still works).
                if camera.position == .back {
                    zoomSelector.padding(.bottom, 12)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            // Scale is relative to the gesture start, so multiply the zoom
            // snapshotted when the pinch began (not the live value) — otherwise
            // it feeds back on itself and jumps straight to the limits.
            MagnificationGesture()
                .onChanged { scale in
                    let start = pinchStart ?? zoom
                    pinchStart = start
                    setZoom(CameraZoom.pinched(start: start, scale: scale, range: zoomLimits))
                }
                .onEnded { _ in pinchStart = nil }
        )
    }

    private var zoomSelector: some View {
        HStack(spacing: 6) {
            ForEach([CGFloat(0.5), 1, 2], id: \.self) { factor in
                let on = abs(zoom - factor) < 0.25
                Button { setZoom(factor) } label: {
                    Text(factor == 0.5 ? ".5×" : (factor == 1 ? "1×" : "2×"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(on ? .white : Color.skTextDim)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(on ? Color.white.opacity(0.16) : .clear, in: .capsule)
                }
            }
        }
        .padding(5)
        .background(.black.opacity(0.4), in: .capsule)
    }

    private var thumbnails: some View {
        HStack(spacing: 6) {
            ForEach(0..<min(camera.capturedCount, 3), id: \.self) { _ in
                RoundedRectangle.sk(9)
                    .fill(LinearGradient(colors: [Color(hex: 0x2b3350), Color(hex: 0x1a1f33)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 40, height: 40)
                    .overlay(RoundedRectangle.sk(9).stroke(Color.skBorder, lineWidth: 1))
            }
        }
        .frame(width: 92, alignment: .leading)
    }

    private func capture() {
        Haptics.recordingTap()
        camera.capture(offsetSeconds: recordingOffset())
    }

    private func flip() {
        Haptics.recordingTap()
        camera.flipCamera()
        // The service resets the new device to 1× — mirror that here.
        zoom = 1
        pinchStart = nil
    }

    /// The device range, floored at 1× on the front camera (no ultrawide there).
    private var zoomLimits: ClosedRange<CGFloat> {
        let r = camera.zoomRange
        let lo = camera.position == .front ? max(r.lowerBound, 1) : r.lowerBound
        return lo...max(lo, r.upperBound)
    }

    private func setZoom(_ factor: CGFloat) {
        zoom = CameraZoom.clamp(factor, to: zoomLimits)
        camera.setZoom(zoom)
    }
}
