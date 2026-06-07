import AppIntents

/// Start a Skrift recording from Control Center / Siri / Spotlight.
///
/// Plain `AppIntent` with `openAppWhenRun: true` — opens the app and records in
/// the foreground. Deliberately NOT an `AudioRecordingIntent` (the iOS-18
/// background-mic protocol): that conformance SIGTRAPs at AppShortcutsProvider
/// registration without the PushToTalk entitlement (Shhhcribble's history).
/// Skrift doesn't need record-from-another-app, so the foreground path is both
/// simpler and crash-free.
///
/// Multi-target source membership: this file compiles into the app AND the
/// widget. Only `Self.performer` is referenced (no app types), so it builds in
/// the widget too; the app sets `performer` at launch and `openAppWhenRun` routes
/// invocations into the app process where it runs.
struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Skrift Recording"
    static var description = IntentDescription("Open Skrift and start recording a voice memo.")
    static var openAppWhenRun: Bool = true

    static var performer: (@Sendable () async -> Void)?

    init() {}

    func perform() async throws -> some IntentResult {
        await Self.performer?()
        return .result()
    }
}
