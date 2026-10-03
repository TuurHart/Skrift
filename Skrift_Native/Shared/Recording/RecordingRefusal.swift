import AVFoundation
import Foundation

/// The typed refusal + the "did this take hear anything" verdict, SHARED by the Mac recorder and
/// the phone's (Q164, C222/C224, recsj-014): a take with no signal is a dead take on both apps,
/// and a refused microphone is one alert with a way to Settings, not a silent retry loop.
extension RecordingCore {

    /// Why a take couldn't start — and, the part that matters, whether the user can DO
    /// anything about it. A refusal used to be a bare sentence, so the two cases that are
    /// worlds apart for the person holding the mouse ("this Mac has no microphone" and
    /// "we're switched off in Privacy settings") arrived looking identical: a wall of text
    /// with no way forward. `permissionDenied` in particular is a TRAP — once TCC holds a
    /// denial the system never prompts again, so pressing Record can look broken forever
    /// while every log line says the app asked politely. That case gets a button.
    enum Refusal: Equatable {
        /// No input device at all — a mini or a Studio with nothing plugged in.
        case noInputDevice
        /// TCC says no. Nothing the app does will prompt again; only Settings clears it.
        case permissionDenied
        /// Managed device / parental controls. Same dead end, different owner.
        case permissionRestricted
        /// A device exists (CoreAudio's default-input answers yes) but the capture layer
        /// can't get a usable object from it — the AVCaptureSession-era shape of the old
        /// "0 Hz format" case: same dead end, same fix.
        case noUsableFormat
        /// The session or the output file refused, with CoreAudio's own words.
        case engineFailed(String)
        /// The session ran but the input delivered no audio at all — carries the device name.
        /// This is the dozing-Bluetooth signature: the take LOOKS live (transport up, timer
        /// counting) while zero buffers arrive, and before this case existed the failure was
        /// routed to a value nothing renders, so the whole thing read as "the app did nothing"
        /// (Tuur, twice, 2026-07-28).
        case nothingCaptured(String)
        /// Buffers arrived but every sample was exactly zero — same family, said precisely.
        case recordedSilence(String)

        var message: String {
            switch self {
            case .noInputDevice:
                "This Mac has no microphone. Connect one (or a headset) and try again."
            case .permissionDenied:
                "Skrift isn't allowed to use the microphone. Turn it on in Privacy & Security ▸ Microphone — macOS won't ask again on its own."
            case .permissionRestricted:
                "Microphone access is restricted on this Mac, so Skrift can't record."
            case .noUsableFormat:
                "No microphone is available. Check System Settings ▸ Sound ▸ Input."
            case .engineFailed(let why):
                "Couldn't start recording: \(why)"
            case .nothingCaptured(let device):
                "“\(device)” delivered no audio — a Bluetooth mic may be asleep. Wake it, or pick another input in System Settings ▸ Sound ▸ Input."
            case .recordedSilence(let device):
                "“\(device)” recorded only silence. Check it's the mic you meant in System Settings ▸ Sound ▸ Input."
            }
        }

        /// The same refusal in the phone's words (Settings ▸ Privacy, no "Mac").
        var phoneMessage: String {
            switch self {
            case .noInputDevice, .noUsableFormat:
                "No microphone is available. Check that nothing else is using it and try again."
            case .permissionDenied:
                "Skrift isn't allowed to use the microphone. Turn it on in Settings ▸ Privacy & Security ▸ Microphone — iOS won't ask again on its own."
            case .permissionRestricted:
                "Microphone access is restricted on this iPhone (Screen Time or a profile), so Skrift can't record."
            case .engineFailed(let why):
                "Couldn't start recording: \(why)"
            case .nothingCaptured(let device):
                "“\(device)” delivered no audio, so nothing was saved. If it's a Bluetooth mic, wake it or switch to the iPhone's own microphone."
            case .recordedSilence(let device):
                "“\(device)” recorded only silence, so nothing was saved. Check it's the microphone you meant."
            }
        }

        /// True when System Settings ▸ Privacy & Security ▸ Microphone is where this gets
        /// fixed — the alert grows a button that goes straight there.
        var fixedInPrivacySettings: Bool {
            self == .permissionDenied || self == .permissionRestricted
        }

        /// Deep link to the exact pane. Only meaningful when `fixedInPrivacySettings`.
        static let privacySettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    }

    // MARK: - The dead-take verdict (one rule, both apps)

    /// A take whose file is this small or smaller holds no audio worth keeping: an AAC encoder
    /// fed nothing still writes its headers.
    static let minUsableTakeBytes = 1024

    /// A take that has delivered no buffer by this many seconds is given up on (Mac fail-fast).
    static let failFastSeconds: TimeInterval = 1.5

    /// Pure: has this take gone long enough with nothing delivered that it should be given up on?
    nonisolated static func shouldFailFast(elapsedSinceStart: TimeInterval, hasReceivedBuffer: Bool) -> Bool {
        !hasReceivedBuffer && elapsedSinceStart >= failFastSeconds
    }

    /// The verdict on a finished take: `nil` = keep it, otherwise the typed refusal naming the
    /// device. No signal = a broken take whatever its byte count: an encoder fed zeros (or
    /// nothing) still writes headers and frames, so size alone can't tell a quiet room from a
    /// dead input. Too small = nothing was captured; big enough but all-zero samples = the
    /// input recorded only silence.
    nonisolated static func deadTakeVerdict(fileBytes: Int, sawSignal: Bool, deviceName: String) -> Refusal? {
        guard fileBytes > minUsableTakeBytes, sawSignal else {
            return fileBytes > minUsableTakeBytes ? .recordedSilence(deviceName)
                                                  : .nothingCaptured(deviceName)
        }
        return nil
    }

    /// TCC's verdict for a status read BEFORE a take (works on iOS and macOS). `nil` = allowed,
    /// or not yet asked (the system prompt is still to come).
    nonisolated static func permissionRefusal(for status: AVAuthorizationStatus) -> Refusal? {
        switch status {
        case .authorized, .notDetermined: nil
        case .restricted: .permissionRestricted
        default: .permissionDenied
        }
    }

    /// The refusal for a prompt that was declined (or could not be shown): anything softer than
    /// "denied" would send the user looking for a prompt that will never come.
    nonisolated static func refusal(for status: AVAuthorizationStatus) -> Refusal {
        status == .restricted ? .permissionRestricted : .permissionDenied
    }
}
