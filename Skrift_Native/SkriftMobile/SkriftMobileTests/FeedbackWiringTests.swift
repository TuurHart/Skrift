import XCTest
@testable import SkriftMobile

/// Q299 / D179: FeedbackKit wiring. The Info.plist carries the app id and a key that
/// is RESOLVED from the build (never a literal in project.yml), and the voice-pause rule
/// keeps FeedbackKit's recorder off Skrift's audio session. Assertions never print the key.
final class FeedbackWiringTests: XCTestCase {

    private var projectYML: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("project.yml")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    func testInfoPlistAppIDIsSkrift() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "FeedbackAppID") as? String, "skrift")
        XCTAssertEqual(FeedbackKitWiring.appID, "skrift")
    }

    func testFeedbackKeyIsABuildVariableNotALiteral() throws {
        let yml = try projectYML
        XCTAssertTrue(yml.contains("FeedbackKey: $(FEEDBACK_KEY)"),
                      "project.yml must take FeedbackKey from the xcconfig variable")
        // The xcconfig itself carries no key: an empty default plus an include from outside git.
        let xcconfig = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Config/Feedback.xcconfig"), encoding: .utf8)
        let assignments = xcconfig.split(separator: "\n").filter { $0.hasPrefix("FEEDBACK_KEY") }
        XCTAssertEqual(assignments.map { $0.replacingOccurrences(of: " ", with: "") }, ["FEEDBACK_KEY="],
                       "the tracked xcconfig must not hold a key")
        XCTAssertTrue(xcconfig.contains("#include? \"/Users/tiurihartog/.config/feedback-kit/skrift.xcconfig\""))
        // The built plist value is resolved (no unexpanded "$(" left). Value never printed.
        let built = Bundle.main.object(forInfoDictionaryKey: "FeedbackKey") as? String
        XCTAssertNotNil(built, "FeedbackKey missing from the built Info.plist")
        XCTAssertFalse(built?.contains("$(") ?? true, "FeedbackKey was not expanded by the build")
    }

    // MARK: - Voice-pause rule

    typealias S = FeedbackVoicePause.AudioStates

    func testVoiceOnWhenSkriftIsSilent() {
        XCTAssertNil(FeedbackVoicePause.reason(for: S()))
    }

    func testVoicePausedForEachAudioOwner() {
        let line = "Voice notes are off while Skrift is recording or playing."
        XCTAssertEqual(FeedbackVoicePause.line, line)
        XCTAssertEqual(FeedbackVoicePause.reason(for: S(recording: true)), line)
        XCTAssertEqual(FeedbackVoicePause.reason(for: S(playingBook: true)), line)
        XCTAssertEqual(FeedbackVoicePause.reason(for: S(playingMemo: true)), line)
        XCTAssertEqual(FeedbackVoicePause.reason(for: S(capturingQuote: true)), line)
        XCTAssertEqual(FeedbackVoicePause.reason(for: S(recording: true, playingBook: true,
                                                        playingMemo: true, capturingQuote: true)), line)
    }

    func testVoiceReturnsOnlyWhenAllStop() {
        var s = S(recording: true, capturingQuote: true)
        s.recording = false
        XCTAssertNotNil(FeedbackVoicePause.reason(for: s), "capture still open")
        s.capturingQuote = false
        XCTAssertNil(FeedbackVoicePause.reason(for: s))
    }

    @MainActor
    func testGateFollowsPushedOwners() {
        defer { FeedbackAudioGate.playingBook = false; FeedbackAudioGate.capturingQuote = false }
        XCTAssertFalse(FeedbackAudioGate.states.recording)
        FeedbackAudioGate.playingBook = true
        XCTAssertTrue(FeedbackAudioGate.states.playingBook)
        XCTAssertNotNil(FeedbackVoicePause.reason(for: FeedbackAudioGate.states))
        FeedbackAudioGate.playingBook = false
        XCTAssertNil(FeedbackVoicePause.reason(for: FeedbackAudioGate.states))
    }
}
