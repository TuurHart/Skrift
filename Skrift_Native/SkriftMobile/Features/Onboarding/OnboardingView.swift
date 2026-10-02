import SwiftUI
import AVFoundation
import CoreLocation

/// First-run onboarding (mockup4): permissions (mic/camera, location/motion) and
/// the one-time transcription-model download. None of it blocks — "Get started"
/// always proceeds; steps are best-effort. Real permission grants + the 494 MB
/// model download are device-owed. (Sync needs no step: it rides the user's iCloud
/// account automatically — no Mac pairing.)
struct OnboardingView: View {
    let onDone: () -> Void

    /// What iOS answered, `nil` = not asked yet. The cards show a check only for a real grant.
    @State private var micGranted: Bool?
    @State private var cameraGranted: Bool?
    @StateObject private var location = OnboardingLocationObserver()
    @ObservedObject private var modelStatus = ModelLoadStatus.shared
    @State private var modelRequested = false
    /// The last download attempt threw. Cleared on the next tap; keeps the row honest
    /// (a spinner forever after `.failed` was the old bug).
    @State private var modelFailed = false

    private var mediaState: OnboardingPermissionState {
        .media(microphone: micGranted, camera: cameraGranted)
    }
    private var locationState: OnboardingPermissionState { .location(location.status) }

    var body: some View {
        ZStack {
            Color.skBg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                logo.padding(.top, 14)
                Text("Welcome to Skrift")
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(Color.skText)
                    .padding(.top, 18)
                Text("Record voice notes, transcribed on-device, synced to your Mac. A couple of quick steps:")
                    .font(.subheadline).foregroundStyle(Color.skTextDim)
                    .padding(.top, 8)

                VStack(spacing: 10) {
                    stepCard(icon: "mic.fill", title: "Microphone & Camera", desc: "To record and snap photos") {
                        permissionTrailing(mediaState, id: "allow-media", action: requestMedia)
                    }
                    stepCard(icon: "location.fill", title: "Location & Motion", desc: "Tags notes with place, weather, steps") {
                        permissionTrailing(locationState, id: "allow-location", action: requestLocation)
                    }
                    stepCard(icon: "arrow.down.circle.fill", title: "Transcription model", desc: modelDesc) {
                        if modelStatus.ready {
                            doneBadge
                        } else if let progress = modelStatus.downloadProgress {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .frame(width: 64).tint(.skAccent)
                        } else if modelRequested {
                            ProgressView().controlSize(.small).tint(.skAccent)
                        } else {
                            Button(modelFailed ? "Retry" : "Get", action: downloadModel)
                                .font(.system(size: 12.5, weight: .bold)).foregroundStyle(Color.skAccent)
                        }
                    }
                }
                .padding(.top, 22)

                Spacer()

                Button(action: onDone) {
                    Text("Get started")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Color.skAccent, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
                        .shadow(color: .skAccent.opacity(0.4), radius: 10, y: 6)
                }
                .accessibilityIdentifier("get-started-button")
                .padding(.bottom, 26)
            }
            .padding(.horizontal, 22)
            // iPad: keep the first-run column at a reading measure instead of
            // stretching edge-to-edge. A no-op at phone width.
            .readingMeasure()
        }
        .onAppear(perform: readExistingMediaStatus)
    }

    @ViewBuilder
    private func permissionTrailing(_ state: OnboardingPermissionState, id: String,
                                    action: @escaping () -> Void) -> some View {
        switch state {
        case .granted: doneBadge
        case .notAsked: allowButton(id, action: action)
        case .denied:
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 12.5, weight: .bold)).foregroundStyle(Color.skAmber)
            .accessibilityIdentifier("\(id)-denied")
        }
    }

    private var logo: some View {
        RoundedRectangle.sk(16)
            .fill(LinearGradient(colors: [.skAccent, Color(hex: 0x9d8bff)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 60, height: 60)
            .overlay(Text("S").font(.system(size: 30, weight: .black)).foregroundStyle(.white))
    }

    private func stepCard<Trailing: View>(icon: String, title: String, desc: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16)).foregroundStyle(Color.skAccentText)
                .frame(width: 36, height: 36)
                .background(Color.skAccentSoft, in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Color.skText)
                Text(desc).font(.system(size: 12)).foregroundStyle(Color.skTextFaint)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 13).padding(.vertical, 12)
        .background(Color.skSurface, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle.sk(14).stroke(Color.skBorder, lineWidth: 1))
    }

    private var doneBadge: some View {
        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.skGreen)
    }

    private func allowButton(_ id: String, action: @escaping () -> Void) -> some View {
        Button("Allow", action: action)
            .font(.system(size: 12.5, weight: .bold)).foregroundStyle(Color.skAccent)
            .accessibilityIdentifier(id)
    }

    private var modelDesc: String {
        if modelStatus.ready { return "Ready · on-device" }
        if let p = modelStatus.downloadProgress { return "Downloading · 494 MB · \(Int(p * 100))%" }
        if modelFailed { return "Download failed · check your connection and retry" }
        return "494 MB · one-time, on-device"
    }

    // MARK: - Actions (best-effort; real grants are device-owed)

    private func readExistingMediaStatus() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: micGranted = true
        case .denied: micGranted = false
        default: break
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: cameraGranted = true
        case .denied, .restricted: cameraGranted = false
        default: break
        }
    }

    private func requestMedia() {
        Task {
            micGranted = await AVAudioApplication.requestRecordPermission()
            cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        }
    }

    private func requestLocation() {
        location.request()
    }

    private func downloadModel() {
        modelRequested = true
        modelFailed = false
        // Progress + ready come from ModelLoadStatus (driven by TranscriptionService);
        // the spinner is reset when the attempt settles, as `ModelsView.downloadASR` does.
        Task {
            let failed: Bool
            do { try await TranscriptionService.shared.ensureLoaded(); failed = false }
            catch { failed = true }
            await MainActor.run {
                modelRequested = false
                modelFailed = failed
            }
        }
    }
}
