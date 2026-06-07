import AppIntents

/// Registers Skrift's App Shortcuts with the system (Siri / Spotlight). One
/// phrase, like Shhhcribble — extra shortcuts dilute Siri match confidence.
/// StartRecordingIntent is a plain AppIntent (no AudioRecordingIntent), so this
/// registration is SIGTRAP-free.
struct SkriftShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Record with \(.applicationName)",
                "Start a \(.applicationName) recording",
            ],
            shortTitle: "Record",
            systemImageName: "mic.circle.fill"
        )
    }
}
