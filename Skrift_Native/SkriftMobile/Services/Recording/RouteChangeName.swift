import AVFoundation

/// Readable names for the DEV devlog's audio-session lines. `String(describing:)` on the
/// imported NS_ENUMs prints "AVAudioSessionRouteChangeReason(rawValue: N)" (Q218), which
/// is useless as the first tool for hardware audio bugs. Log-only: nothing here touches
/// the session.
enum RouteChangeName {

    /// Name for a route-change reason raw value (`AVAudioSessionRouteChangeReasonKey`).
    /// nil or an undocumented value → "unknown" (with the raw number when there is one).
    static func reason(rawValue: UInt?) -> String {
        guard let rawValue else { return "unknown" }
        guard let known = AVAudioSession.RouteChangeReason(rawValue: rawValue) else {
            return "unknown(\(rawValue))"
        }
        return reason(known)
    }

    static func reason(_ reason: AVAudioSession.RouteChangeReason) -> String {
        switch reason {
        case .newDeviceAvailable: return "newDeviceAvailable"
        case .oldDeviceUnavailable: return "oldDeviceUnavailable"
        case .categoryChange: return "categoryChange"
        case .override: return "override"
        case .wakeFromSleep: return "wakeFromSleep"
        case .noSuitableRouteForCategory: return "noSuitableRouteForCategory"
        case .routeConfigurationChange: return "routeConfigurationChange"
        case .unknown: return "unknown"
        @unknown default: return "unknown(\(reason.rawValue))"
        }
    }

    /// `AVAudioSession.Category` is a string-backed struct ("AVAudioSessionCategoryPlayAndRecord");
    /// strip the prefix so the log reads "PlayAndRecord".
    static func category(_ category: AVAudioSession.Category) -> String {
        strip(category.rawValue, prefix: "AVAudioSessionCategory")
    }

    /// Same for modes ("AVAudioSessionModeDefault" → "Default").
    static func mode(_ mode: AVAudioSession.Mode) -> String {
        strip(mode.rawValue, prefix: "AVAudioSessionMode")
    }

    static func strip(_ raw: String, prefix: String) -> String {
        raw.hasPrefix(prefix) && raw.count > prefix.count ? String(raw.dropFirst(prefix.count)) : raw
    }
}
