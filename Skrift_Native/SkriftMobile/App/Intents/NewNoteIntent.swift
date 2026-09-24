import AppIntents

/// Open an empty Skrift note from Control Center / Siri / the Lock Screen
/// widget (C112/C114). Plain `AppIntent` with `openAppWhenRun: true` and no
/// haptic (C222) — same shape as `StartRecordingIntent`, its own control next
/// to Record rather than a mode on it (D135: "a second button, not a changed
/// one").
///
/// Multi-target source membership (see project.yml): this file compiles into
/// the app AND the widget. Only `Self.performer` is referenced, so it builds
/// in the widget too; the app sets `performer` at launch.
struct NewNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "New Note in Skrift"
    static var description = IntentDescription("Open an empty Skrift note with the keyboard up.")
    static var openAppWhenRun: Bool = true

    static var performer: (@Sendable () async -> Void)?

    init() {}

    func perform() async throws -> some IntentResult {
        await Self.performer?()
        return .result()
    }
}
