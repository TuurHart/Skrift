import AppIntents

/// Resume the last-played audiobook from Siri / Spotlight ("Resume my book in
/// Skrift").
///
/// Same SIGTRAP-safe shape as `StartRecordingIntent`: a plain `AppIntent` with
/// `openAppWhenRun: true` — opens the app and playback starts in the foreground.
/// Deliberately NOT an audio-playback intent protocol (background start is a
/// separate, carefully device-tested experiment — see backlog).
///
/// Multi-target source membership: compiles into the app AND the widget. Only
/// `Self.performer` is referenced (no app types), so it builds in the widget
/// too; the app sets `performer` at launch and `openAppWhenRun` routes
/// invocations into the app process where it runs.
struct ResumeAudiobookIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Skrift Audiobook"
    static var description = IntentDescription("Open Skrift and resume the audiobook you were listening to.")
    static var openAppWhenRun: Bool = true

    static var performer: (@Sendable () async -> Void)?

    init() {}

    func perform() async throws -> some IntentResult {
        await Self.performer?()
        return .result()
    }
}
