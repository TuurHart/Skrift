import AVFoundation
import Combine
import Foundation
import UIKit

/// Captures timestamped photos during recording. Each capture records the photo's
/// recording-time offset (paused time excluded — supplied by the caller). On save
/// these become the `imageManifest` and drive `[[img_NNN]]` marker placement.
///
/// In **mock mode** (`-seedTranscript`) it skips the camera entirely (the Simulator
/// has none) and writes a tiny placeholder JPEG, so the capture→offset→manifest
/// pipeline is UI-testable. Real capture is device-owed.
@MainActor
final class PhotoCaptureService: NSObject, ObservableObject {
    @Published private(set) var capturedCount = 0
    /// Which camera feeds the session (CameraSheet's flip button toggles it).
    /// Reverted if a switch fails so the UI stays truthful.
    @Published private(set) var position: AVCaptureDevice.Position = .back
    /// The active camera's supported zoom range (capped at the UI ceiling), so the
    /// sheet clamps pinch zoom to what the hardware can actually do. The mock keeps
    /// the default.
    @Published private(set) var zoomRange: ClosedRange<CGFloat> = 0.5...CameraZoom.uiCeiling
    /// Which camera is active; drives which zoom chips the sheet shows. Zoom is in display
    /// units (1 = the wide lens), see `CameraLens`.
    @Published private(set) var lens: CameraLens = .tripleBack

    let mock: Bool
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "skrift.camera.session")
    private var captured: [(url: URL, offset: Double)] = []
    private var pendingOffsets: [Double] = []
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    /// `videoZoomFactor` that frames display 1x on the active device (sessionQueue only).
    private nonisolated(unsafe) var zoomBase: CGFloat = 1
    private var lastCaptureAt: Date?
    /// Session inputs/outputs are built once; configure() after a stop() just
    /// restarts the session. Touched only on `sessionQueue`, like the session.
    private var configured = false

    init(mock: Bool = LaunchFlags.seedTranscript != nil) {
        self.mock = mock
        super.init()
    }

    /// Build the session (once) and start it. Called when the camera UI is
    /// about to show — NOT at record-screen open: a running AVCaptureSession
    /// keeps the camera + ISP powered for the entire recording, a real heat +
    /// battery cost on an older phone, for a feature most recordings never
    /// touch. Idempotent and safe after `stop()` (the session just restarts).
    func configure() {
        guard !mock else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                self.configured = true
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                if let (device, kind) = Self.pickDevice(position: .back),
                   let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.videoDevice = device
                    self.videoInput = input
                    self.activate(device, kind: kind)
                }
                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                }
                self.session.commitConfiguration()
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        guard !mock else { return }
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
    }

    /// Flip between the back and front camera mid-recording (CameraSheet's flip
    /// button). Swaps the session's video input on the session queue — the photo
    /// output and the capture→offset→manifest pipeline are untouched. The new
    /// device starts at 1× (the previous device may have a stale zoom factor).
    /// If the target camera can't be added (missing device / rejected input) the
    /// previous input is restored and `position` reverts. In the camera-less
    /// mock only the published `position` toggles (keeps the sheet testable).
    func flipCamera() {
        let previous = position
        let target: AVCaptureDevice.Position = previous == .back ? .front : .back
        position = target
        guard !mock else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            guard let (device, kind) = Self.pickDevice(position: target),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                Task { @MainActor in self.position = previous }
                return
            }
            let oldInput = self.videoInput
            if let oldInput { self.session.removeInput(oldInput) }
            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.videoInput = input
                self.videoDevice = device
                // activate() resets to display 1x: shared AVCaptureDevice instances keep
                // their last zoom factor, so a flip must always land on a known framing.
                self.activate(device, kind: kind)
            } else {
                // Target rejected — put the previous camera back and revert the UI.
                if let oldInput, self.session.canAddInput(oldInput) {
                    self.session.addInput(oldInput)
                }
                Task { @MainActor in self.position = previous }
            }
        }
    }

    /// Back: the virtual device (triple, else dual-wide) so zoom below 1x reaches the real
    /// ultra-wide; else the plain wide. Front: the wide selfie camera.
    private nonisolated static func pickDevice(position: AVCaptureDevice.Position) -> (AVCaptureDevice, CameraLens)? {
        if position == .front {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front).map { ($0, .front) }
        }
        if let d = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) { return (d, .tripleBack) }
        if let d = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) { return (d, .dualWideBack) }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back).map { ($0, .wideBack) }
    }

    /// Make `device` the active camera: compute the display-1x base, publish the display
    /// range + lens, and frame display 1x. Session queue only.
    private nonisolated func activate(_ device: AVCaptureDevice, kind: CameraLens) {
        let switchOver = device.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat(truncating: $0) }
        let base = CameraLens.baseFactor(hasUltraWide: kind.hasUltraWide, firstSwitchOver: switchOver)
        zoomBase = base
        let range = CameraZoom.range(deviceMin: device.minAvailableVideoZoomFactor / base,
                                     deviceMax: device.maxAvailableVideoZoomFactor / base)
        Task { @MainActor [weak self] in
            self?.zoomRange = range
            self?.lens = kind
        }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = max(device.minAvailableVideoZoomFactor,
                                         min(base, device.maxAvailableVideoZoomFactor))
            device.unlockForConfiguration()
        } catch {}
    }

    /// Set the zoom in display units (0.5/1/2; 1 = the wide lens). Device-only; clamped
    /// to the camera's supported range. No-op in the camera-less mock.
    func setZoom(_ factor: CGFloat) {
        guard !mock else { return }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                let clamped = max(device.minAvailableVideoZoomFactor,
                                  min(factor * self.zoomBase, device.maxAvailableVideoZoomFactor))
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func capture(offsetSeconds: Double) {
        // Debounce: a single shutter tap was firing twice on device.
        let now = Date()
        if let last = lastCaptureAt, now.timeIntervalSince(last) < 0.6 { return }
        lastCaptureAt = now

        if mock {
            let url = AppPaths.recordingsDirectory.appendingPathComponent("cap_\(UUID().uuidString).jpg")
            let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
                UIColor.darkGray.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            }
            if let data = image.jpegData(compressionQuality: 0.6) {
                try? data.write(to: url)
                captured.append((url, offsetSeconds))
                capturedCount = captured.count
            }
            return
        }
        pendingOffsets.append(offsetSeconds)
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    /// Hand off the captured photos and clear internal state.
    func takeAll() -> [(url: URL, offset: Double)] {
        let out = captured
        captured.removeAll()
        capturedCount = 0
        return out
    }

    func discardAll() {
        for item in captured { try? FileManager.default.removeItem(at: item.url) }
        captured.removeAll()
        capturedCount = 0
    }
}

extension PhotoCaptureService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        let url = AppPaths.recordingsDirectory.appendingPathComponent("cap_\(UUID().uuidString).jpg")
        try? data.write(to: url)
        Task { @MainActor in
            let offset = self.pendingOffsets.isEmpty ? 0 : self.pendingOffsets.removeFirst()
            self.captured.append((url, offset))
            self.capturedCount = self.captured.count
        }
    }
}
