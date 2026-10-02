import CoreLocation

/// What an onboarding permission card shows. Derived from what iOS actually
/// answered, never from "the button was tapped".
enum OnboardingPermissionState: Equatable {
    case notAsked
    case granted
    case denied

    /// Microphone + camera card. Both must be granted for the check; a no on
    /// either one is `denied` (the card then points at Settings).
    /// `nil` = not asked yet.
    static func media(microphone: Bool?, camera: Bool?) -> OnboardingPermissionState {
        if microphone == false || camera == false { return .denied }
        if microphone == true && camera == true { return .granted }
        return .notAsked
    }

    /// Location & Motion card, from the OS authorization status.
    static func location(_ status: CLAuthorizationStatus) -> OnboardingPermissionState {
        switch status {
        case .notDetermined: return .notAsked
        case .authorizedWhenInUse, .authorizedAlways: return .granted
        case .denied, .restricted: return .denied
        @unknown default: return .notAsked
        }
    }
}

/// Publishes the OS location authorization so the card flips when the user answers
/// the system prompt, not when "Allow" was tapped.
final class OnboardingLocationObserver: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus
    private let manager = CLLocationManager()

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    func request() { manager.requestWhenInUseAuthorization() }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
    }
}
