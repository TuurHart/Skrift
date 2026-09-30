import XCTest
import UIKit

/// Q79 (C112/C113): typing fast into a FRESH quick note never loses a character or a
/// Return while the first keystroke creates the draft Memo. The Q64 sim run lost the
/// first Return ("Tram 28 ideaBuy pastel de nata") at full speed; with pauses it survived.
/// Synthetic corpus, in-memory store.
final class QuickNoteFastTypingUITests: XCTestCase {

    private var corpusPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test-fixtures/corpus").path
    }

    private func openFreshQuickNote() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-corpus", corpusPath]
        app.launch()
        let newNote = app.buttons["ipad-new-note-button"]
        XCTAssertTrue(newNote.waitForExistence(timeout: 20), "the new-note button never appeared")
        newNote.tap()
        XCTAssertTrue(app.buttons["quick-note-back"].waitForExistence(timeout: 10), "quick note did not open")
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 2) { tip.tap() }
        let body = app.descendants(matching: .any).matching(identifier: "quick-note-body").firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5), "body missing")
        return (app, body)
    }

    private func bodyValue(_ body: XCUIElement) -> String { (body.value as? String) ?? "" }

    func testFullSpeedTypingKeepsEveryCharacterAndReturn() {
        let (_, body) = openFreshQuickNote()
        let text = "Tram 28 idea\nBuy pastel de nata\nCall Ana about Friday\n\nSecond paragraph, ok?\nlast line"
        body.typeText(text)   // ONE call = full speed, first keystroke creates the Memo
        Thread.sleep(forTimeInterval: 1.5)   // past the 1 s debounce; nothing may rewrite the text
        XCTAssertEqual(bodyValue(body), text)
    }

    func testFullSpeedLineByLineKeepsEveryReturn() {
        let (_, body) = openFreshQuickNote()
        // The Q64 pattern: separate typeText calls, no sleeps, Return at the end of a line.
        let lines = ["Tram 28 idea", "Buy pastel de nata", "Call Ana about Friday"]
        for (i, line) in lines.enumerated() { body.typeText(line + (i < 2 ? "\n" : "")) }
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(bodyValue(body), lines.joined(separator: "\n"))
    }

    func testFirstKeystrokeThenImmediateReturnSurvives() {
        let (_, body) = openFreshQuickNote()
        body.typeText("A\nB\nC\n")
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(bodyValue(body), "A\nB\nC\n")
    }

    func testPasteOfMultiLineTextIntoFreshNote() {
        let (app, body) = openFreshQuickNote()
        let pasted = "Pasted line one\nPasted line two\n\nPasted line four"
        UIPasteboard.general.string = pasted
        body.press(forDuration: 1.0)
        let paste = app.menuItems["Paste"].firstMatch
        let pasteBtn = app.buttons["Paste"].firstMatch
        if paste.waitForExistence(timeout: 3) { paste.tap() }
        else if pasteBtn.waitForExistence(timeout: 3) { pasteBtn.tap() }
        else { XCTFail("no Paste affordance appeared") }
        // iOS asks once whether this app may read the pasteboard.
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Paste"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(bodyValue(body), pasted)
        // ...and typing after the paste keeps working.
        body.typeText("\nend")
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(bodyValue(body), pasted + "\nend")
    }
}
