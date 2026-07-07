import AppIntents

/// Stop the active recording from the Live Activity's Stop button.
///
/// `openAppWhenRun: true` foregrounds the app so the existing
/// stop→save→show-memo flow runs reliably (a plain SwiftUI `.onChange` is only
/// guaranteed once foregrounded). Stopping produces a saved memo you'd want to
/// see anyway, so foregrounding is the right UX. (Stop-without-unlock from the
/// lock screen would need a shared recording session controller — a device-owed
/// refinement, noted in the handoff.)
///
/// Like StartRecordingIntent: plain AppIntent, source-membered into the widget,
/// references only `Self.performer`.
struct StopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Skrift Recording"
    static var description = IntentDescription("Stop the current Skrift recording and save the note.")
    static var openAppWhenRun: Bool = true

    static var performer: (@Sendable () async -> Void)?

    init() {}

    func perform() async throws -> some IntentResult {
        await Self.performer?()
        return .result()
    }
}
