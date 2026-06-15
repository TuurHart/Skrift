import XCTest

/// Verifies the DIRECT voice-enrollment screen renders + is wired (the Names →
/// person → "Add voice" button used to open a "Got it" placeholder; it now opens
/// a real recorder). `-seedDemoNames` seeds "Bob Smith" with NO voiceprint, so the
/// "Add voice" path is reachable (the enrolled "Jane Doe" would hide it).
final class VoiceEnrollUITests: XCTestCase {

    private let shotDir = "/tmp/skrift-enroll-shots"

    override func setUpWithError() throws {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(atPath: shotDir, withIntermediateDirectories: true)
    }

    private func snap(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "\(shotDir)/\(name).png"))
    }

    func testAddVoiceOpensTheRecorder() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemoNames", "-skipOnboarding", "-appTheme", "dark"]
        app.launch()

        func el(_ id: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: id).firstMatch
        }

        el("settings-button").tap()
        let names = el("names-link")
        XCTAssertTrue(names.waitForExistence(timeout: 8), "Names link missing in Settings")
        names.tap()

        let bob = el("person-Bob Smith")
        XCTAssertTrue(bob.waitForExistence(timeout: 5), "unenrolled person row missing")
        bob.tap()

        let addVoice = el("add-voice-button")
        XCTAssertTrue(addVoice.waitForExistence(timeout: 5), "Add voice button missing for an unenrolled person")
        addVoice.tap()

        // The enroll sheet now shows the real recorder (was a 'Got it' placeholder).
        XCTAssertTrue(el("voice-enroll-record").waitForExistence(timeout: 5),
                      "voice-enroll record button missing — still the placeholder?")
        snap("01-enroll-idle")
    }
}
