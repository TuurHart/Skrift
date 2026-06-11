import AppIntents

/// Registers Skrift's App Shortcuts with the system (Siri / Spotlight). Kept
/// to the few the user actually invokes — extra shortcuts dilute Siri match
/// confidence.
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
        AppShortcut(
            intent: ResumeAudiobookIntent(),
            phrases: [
                "Resume my book in \(.applicationName)",
                "Play \(.applicationName) book",
            ],
            shortTitle: "Resume book",
            systemImageName: "book.circle.fill"
        )
    }
}
