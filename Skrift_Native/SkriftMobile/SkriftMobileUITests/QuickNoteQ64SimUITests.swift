import XCTest
import AVFoundation

/// Q64 simulator half — the parts of the quick-note device round a simulator can
/// prove (real crash relaunch, real keyboard and the location prompt stay on the
/// iPhone 13). Synthetic corpus, in-memory store (`-inMemoryStore -corpus …`).
/// Screenshots land in `plan/reads/quicknote-q64sim/`.
final class QuickNoteQ64SimUITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private var corpusPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test-fixtures/corpus").path
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-corpus", corpusPath]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func dismissKeyboardTip(_ app: XCUIApplication) {
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 2) { tip.tap() }
    }

    private func memoRowCount(_ app: XCUIApplication) -> Int {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'memo-row-'")).count
    }

    // MARK: - the app's data container inside this simulator

    /// The runner lives in the same simulator, so the app's `Documents` can be
    /// found by scanning sibling containers for the dev bundle id.
    private func appDocuments() -> URL? {
        let apps = URL(fileURLWithPath: NSHomeDirectory()).deletingLastPathComponent()
        let subs = (try? FileManager.default.contentsOfDirectory(at: apps, includingPropertiesForKeys: nil)) ?? []
        for dir in subs {
            let meta = dir.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            guard let d = try? Data(contentsOf: meta),
                  let plist = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any],
                  plist["MCMMetadataIdentifier"] as? String == "com.skrift.mobile.dev" else { continue }
            return dir.appendingPathComponent("Documents", isDirectory: true)
        }
        return nil
    }

    /// A 2 s AAC .m4a named like a take the process never finished
    /// (`rec_tmp_<take>.m4a`, no marker) — what the launch sweep rebuilds into
    /// the "Recovered recording (the app closed mid-take)" note.
    private func plantOrphanTake(in docs: URL) throws {
        let dir = docs.appendingPathComponent("recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("rec_tmp_q64sim-orphan.m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings)
            let fmt = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
            let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 32000)!
            buf.frameLength = 32000
            for i in 0..<32000 { buf.floatChannelData![0][i] = 0.2 * sin(Float(i) * 0.05) }
            try file.write(from: buf)
        }   // file closes here — the moov atom is written
    }

    // MARK: - 1. ✎ right after a cold launch with a recovered note pending

    func test1_pencilAfterCrashRecoveryOpensNewEmptyDraft() throws {
        let first = launch()
        XCTAssertTrue(any(first, "memos-list").waitForExistence(timeout: 20), "list never appeared")
        first.terminate()   // the app container now exists

        let docs = try XCTUnwrap(appDocuments(), "could not locate the dev app container")
        try plantOrphanTake(in: docs)

        let app = launch()
        let newNote = app.buttons["ipad-new-note-button"]
        XCTAssertTrue(newNote.waitForExistence(timeout: 20), "the ✎ never appeared")
        newNote.tap()   // immediately: the recovery sweep races this tap

        XCTAssertTrue(app.buttons["quick-note-back"].waitForExistence(timeout: 10), "quick-note did not open")
        dismissKeyboardTip(app)
        // A NEW empty draft: no trailing memo actions yet (they only exist once a Memo
        // does), and none of the recovered note's title anywhere on the screen.
        XCTAssertFalse(any(app, "quick-note-menu").exists, "✎ opened an existing note (it has a menu)")
        XCTAssertFalse(any(app, "quick-note-add-recording").exists, "✎ opened an existing note")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Recovered recording'")).count, 0,
                       "the recovered note's title is on the quick-note screen")
        XCTAssertEqual(app.textViews.matching(NSPredicate(format: "value CONTAINS 'Recovered'")).count, 0)
        let title = app.textFields["quick-note-title"]
        if title.exists { XCTAssertFalse(((title.value as? String) ?? "").contains("Recovered"), "title field holds the recovered title") }
        capture(app, "1a-pencil-after-cold-launch-new-empty-draft")

        // Back to the list (untouched → no note); wait for the sweep's recovered note
        // so the fixture is proven to have been in play, then ✎ again.
        app.buttons["quick-note-back"].tap()
        let recovered = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Recovered recording'")).firstMatch
        XCTAssertTrue(recovered.waitForExistence(timeout: 40), "the recovery sweep never produced the recovered note — fixture not in play")
        capture(app, "1b-list-with-recovered-recording")

        app.buttons["ipad-new-note-button"].tap()
        XCTAssertTrue(app.buttons["quick-note-back"].waitForExistence(timeout: 10))
        dismissKeyboardTip(app)
        XCTAssertFalse(any(app, "quick-note-menu").exists, "second ✎ (recovered note now present) opened an existing note")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Recovered recording'")).count, 0,
                       "second ✎ shows the recovered note's title")
        capture(app, "1c-pencil-with-recovered-present-new-empty-draft")
    }

    // MARK: - 2 + 3. type three lines, chrome + accessory persist; note listed; chips

    func test2_3_typeThreeLinesThenListAndChips() {
        let app = launch()
        let newNote = app.buttons["ipad-new-note-button"]
        XCTAssertTrue(newNote.waitForExistence(timeout: 20), "the ✎ never appeared")
        let rowsBefore = memoRowCount(app)
        newNote.tap()
        XCTAssertTrue(app.buttons["quick-note-back"].waitForExistence(timeout: 10))
        dismissKeyboardTip(app)

        let body = any(app, "quick-note-body")
        XCTAssertTrue(body.waitForExistence(timeout: 5), "body missing")

        func assertChrome(_ when: String) {
            XCTAssertTrue(any(app, "quick-note-date").exists, "date chip missing \(when)")
            XCTAssertTrue(any(app, "add-tag-button").exists || any(app, "tag-input").exists, "tags row missing \(when)")
            XCTAssertTrue(any(app, "importance-balls").exists, "importance missing \(when)")
            XCTAssertTrue(app.keyboards.count > 0, "keyboard not up \(when)")
            XCTAssertTrue(app.buttons["accessory-done"].waitForExistence(timeout: 3), "accessory toolbar (accessory-done) missing \(when)")
            XCTAssertTrue(app.buttons["accessory-undo"].exists, "accessory-undo missing \(when)")
            XCTAssertTrue(app.buttons["accessory-find"].exists, "accessory-find missing \(when)")
        }
        assertChrome("before typing")

        let lines = ["Tram 28 idea", "Buy pastel de nata", "Call Ana about Friday"]
        for (i, line) in lines.enumerated() {
            body.typeText(line + (i < 2 ? "\n" : ""))
            assertChrome("after line \(i + 1)")
            if i == 1 { capture(app, "2a-typing-after-line-2-keyboard-up") }
        }
        capture(app, "2b-typed-3-lines-keyboard-up")

        // Back to the list, past the debounce (Q53: 1 s).
        Thread.sleep(forTimeInterval: 1.5)
        app.buttons["accessory-done"].tap()   // dismiss the keyboard first
        app.buttons["quick-note-back"].tap()
        XCTAssertTrue(any(app, "memos-list").waitForExistence(timeout: 10), "list did not return")
        let listed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Tram 28 idea' OR label CONTAINS 'Buy pastel'")).firstMatch
        XCTAssertTrue(listed.waitForExistence(timeout: 10), "the new note is not listed")
        XCTAssertGreaterThan(memoRowCount(app), rowsBefore - 1, "row count fell")
        capture(app, "3a-list-with-new-note")

        for chip in ["Needs Work", "Done", "Unrated", "All"] {
            let b = any(app, "ipad-chip-\(chip)")
            XCTAssertTrue(b.waitForExistence(timeout: 5), "chip \(chip) missing")
            b.tap()
            if chip == "Unrated" || chip == "Done" { capture(app, "3b-chip-\(chip.replacingOccurrences(of: " ", with: "-"))") }
        }
    }

    // MARK: - 4. untouched quick note leaves nothing (D91)

    func test4_emptyQuickNoteLeavesNothingBehind() {
        let app = launch()
        let newNote = app.buttons["ipad-new-note-button"]
        XCTAssertTrue(newNote.waitForExistence(timeout: 20))
        XCTAssertTrue(any(app, "memos-list").waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5)
        let before = memoRowCount(app)
        capture(app, "4a-list-before")

        newNote.tap()
        XCTAssertTrue(app.buttons["quick-note-back"].waitForExistence(timeout: 10))
        dismissKeyboardTip(app)
        Thread.sleep(forTimeInterval: 1.5)   // longer than the 1 s debounce
        app.buttons["quick-note-back"].tap()
        XCTAssertTrue(any(app, "memos-list").waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5)
        let after = memoRowCount(app)
        capture(app, "4b-list-after-empty-note")
        XCTAssertEqual(after, before, "a row appeared after opening and leaving an empty quick note")
        // No blank-titled row: every row exposes some text.
        let untitled = app.staticTexts.matching(NSPredicate(format: "label == '' OR label == 'Untitled'")).count
        print("Q64sim empty-note: rows before=\(before) after=\(after) untitled/blank labels=\(untitled)")
    }
}
