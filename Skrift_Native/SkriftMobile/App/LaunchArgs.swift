import Foundation

/// Launch-argument parsing, mirroring the Pike Companion test harness. Accepts
/// both `-key value` and `-key=value` forms.
extension Array where Element == String {
    func boolFlag(_ key: String) -> Bool {
        contains { $0 == key || $0.hasPrefix("\(key)=") }
    }

    func stringValue(_ key: String) -> String? {
        if let i = firstIndex(of: key), i + 1 < count { return self[i + 1] }
        if let raw = first(where: { $0.hasPrefix("\(key)=") }) {
            return String(raw.dropFirst("\(key)=".count))
        }
        return nil
    }

    func intValue(_ key: String) -> Int? { stringValue(key).flatMap(Int.init) }
}

/// Test seams the app reads at launch (`MOBILE_NATIVE_REWRITE_PLAN.md` §5). The
/// Simulator has no Neural Engine and FluidAudio pulls ~600MB, so UI tests SEED
/// state via these flags rather than running real ASR.
enum LaunchFlags {
    private static var args: [String] { ProcessInfo.processInfo.arguments }

    /// Fresh in-memory SwiftData store per launch — deterministic UI tests, and
    /// the demo seeder runs every time (the persistent store would otherwise
    /// survive across runs and the idempotent seeder would skip).
    static var inMemoryStore: Bool { args.boolFlag("-inMemoryStore") }
    static var seedDemoMemos: Bool { args.boolFlag("-seedDemoMemos") }
    /// Seed ONE long memo (long transcript + an image marker) so a UI test can
    /// scroll content UNDER the glass player bar and screenshot the refraction.
    static var seedLongMemo: Bool { args.boolFlag("-seedLongMemo") }
    /// Show the conversation-mode design mock (static; no real diarization).
    static var conversationMock: Bool { args.boolFlag("-conversationMock") }
    /// Seed ONE memo whose transcript is a `**Name:**` conversation, to verify the real
    /// detail view renders speaker turns (`SpeakerTurnsView`).
    static var seedConversationMemo: Bool { args.boolFlag("-seedConversationMemo") }
    /// Seed ONE video-import memo with a real LANDSCAPE (16:9) frame thumbnail (a
    /// centered circle — distorts to an ellipse if the thumbnail squishes aspect),
    /// so a UI test can screenshot-verify the video source glyph + thumbnail aspect.
    static var seedVideoMemo: Bool { args.boolFlag("-seedVideoMemo") }
    static var seedDemoNames: Bool { args.boolFlag("-seedDemoNames") }
    /// Seed the name-linking demo (the mock's "Studio afternoon" memo + 4 people: two
    /// Jacks → ambiguous, Hendri → linked, Rose → suggested) and open its detail directly,
    /// so the in-place name-linking surface can be screenshot-verified on the Simulator.
    static var seedNameLinking: Bool { args.boolFlag("-seedNameLinking") }
    /// Wipe the local names.json at launch so a conversation/voice test starts from a
    /// known-empty names slate (names.json persists across sim runs, unlike the SwiftData
    /// store — `-inMemoryStore` doesn't reset it). Used by the diarization-split and
    /// voice-enroll UI tests.
    static var resetNames: Bool { args.boolFlag("-resetNames") }
    /// Stub the Mac sync layer so UI tests don't need a live backend.
    static var mockMac: Bool { args.boolFlag("-mockMac") }
    /// Inject fake Bonjour-discovered Macs (the sim can't see the real one) so
    /// the Pair-a-Mac discovered list is UI-testable.
    static var seedDiscoveredMacs: Bool { args.boolFlag("-seedDiscoveredMacs") }
    /// Force the first-run onboarding on (the onboarding UI test). Existing tests
    /// pass `-inMemoryStore` and auto-skip onboarding without it.
    static var forceOnboarding: Bool { args.boolFlag("-forceOnboarding") }
    static var skipOnboarding: Bool { args.boolFlag("-skipOnboarding") }
    /// Inject a deterministic transcript instead of running FluidAudio (the
    /// Simulator has no Neural Engine). Its presence also puts recording in mock
    /// mode (no mic, no permission prompt) so the record→save→transcribe flow is
    /// hermetically UI-testable.
    static var seedTranscript: String? { args.stringValue("-seedTranscript") }
}
