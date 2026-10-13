import XCTest
import SwiftData
import Foundation

/// Q363 (D186, D191, C277; plan/perf2/f-mac-ui.md M4, M6, M6b, M13): work counters for
/// typing on the Mac. `MacCloudEditSync` (title + body push) and `BodyTextView.updateNSView`
/// live in App/ and Features/, which this host-less bundle does not compile, so these drive
/// the two decisions they delegate to (`MacTypingDebounce`, `BodyUpdateGate`) and the
/// off-main round trip (`MacEditRoundTrip`). The wiring itself is proven by the full
/// SkriftDesktop build.
@MainActor
final class MacTypingWorkTests: XCTestCase {

    // MARK: - M4: 20 title keystrokes → at most one store save

    func testTwentyTitleKeystrokesSaveTheStoreAtMostOnce() async throws {
        let container = try ModelContainer(
            for: Memo.self, MemoAsset.self, MemoEnhancement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let memo = Memo(audioFilename: "m.m4a", recordedAt: Date(), transcript: "Body.",
                        transcriptStatus: .done)
        ctx.insert(memo)
        try ctx.save()

        var saves = 0
        let token = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: ctx, queue: nil) { _ in saves += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        var commits = 0
        var title = ""
        let debounce = MacTypingDebounce(delay: .milliseconds(60))
        for ch in "A twenty char title!" {          // 20 keystrokes
            title.append(ch)
            let typed = title
            debounce.schedule(memo.id.uuidString) {
                commits += 1
                memo.title = typed
                try? ctx.save()
            }
        }
        XCTAssertEqual(saves, 0, "no keystroke saves the store on its own")
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(commits, 1, "one commit per typing pause, not per key")
        XCTAssertLessThanOrEqual(saves, 1, "20 title keystrokes → at most one store save")
        XCTAssertEqual(memo.title, "A twenty char title!", "the ONE commit carries the last text")
        XCTAssertFalse(debounce.isPending(memo.id.uuidString))
    }

    func testDebounceKeysAreIndependent() async throws {
        var fired: [String] = []
        let debounce = MacTypingDebounce(delay: .milliseconds(40))
        for _ in 0..<5 {
            debounce.schedule("a") { fired.append("a") }
            debounce.schedule("b") { fired.append("b") }
        }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(fired.sorted(), ["a", "b"], "one fire per note, two notes typed in")
    }

    // MARK: - M6: an unrelated SwiftUI update does not restyle (or rebuild the model string)

    private struct Style: Equatable { var suggested: [String]; var quote: String? }

    func testUnrelatedUpdateDoesNotRestyleOrRebuildModel() {
        var gate = BodyUpdateGate<Style>()
        let text = String(repeating: "word ", count: 5000)
        gate.accounted(text)                                 // makeNSView rendered it
        let style = Style(suggested: [], quote: nil)
        var rebuilds = 0
        let first = gate.plan(model: text, commitPending: false, style: style, playing: false,
                              storageModel: { rebuilds += 1; return text }, shown: { $0 })
        XCTAssertFalse(first.render)

        // 30 more updates: a sidebar-divider drag re-creating the closures, nothing else moved.
        var restyles = 0
        for _ in 0..<30 {
            let p = gate.plan(model: text, commitPending: false, style: style, playing: false,
                              storageModel: { rebuilds += 1; return text }, shown: { $0 })
            XCTAssertFalse(p.render)
            if p.restyle { restyles += 1 }
        }
        XCTAssertEqual(restyles, 0, "geometry-only updates never run the full restyle")
        XCTAssertEqual(rebuilds, 0, "an unchanged binding never rebuilds the O(document) model string")
    }

    func testStyleInputChangeAndLeavingPlaybackRestyleOnce() {
        var gate = BodyUpdateGate<Style>()
        gate.accounted("Hi")
        let a = Style(suggested: [], quote: nil)
        _ = gate.plan(model: "Hi", commitPending: false, style: a, playing: false,
                      storageModel: { "Hi" }, shown: { $0 })
        let b = Style(suggested: ["Jack"], quote: nil)
        XCTAssertTrue(gate.plan(model: "Hi", commitPending: false, style: b, playing: false,
                                storageModel: { "Hi" }, shown: { $0 }).restyle,
                      "a new suggestion list restyles")
        XCTAssertFalse(gate.plan(model: "Hi", commitPending: false, style: b, playing: false,
                                 storageModel: { "Hi" }, shown: { $0 }).restyle)
        XCTAssertFalse(gate.plan(model: "Hi", commitPending: false, style: b, playing: true,
                                 storageModel: { "Hi" }, shown: { $0 }).restyle,
                       "karaoke recolors in place")
        XCTAssertTrue(gate.plan(model: "Hi", commitPending: false, style: b, playing: false,
                                storageModel: { "Hi" }, shown: { $0 }).restyle,
                      "leaving karaoke restores the normal styling")
    }

    // MARK: - M6b: an update inside the 1 s debounce keeps the typed text

    func testUpdateInsideDebounceKeepsTypedText() {
        var gate = BodyUpdateGate<Style>()
        let style = Style(suggested: [], quote: nil)
        let stored = "Hello"
        gate.accounted(stored)
        // He typed " world"; the commit is pending, so the binding still says "Hello".
        let onScreen = "Hello world"
        var rebuilds = 0
        let p = gate.plan(model: stored, commitPending: true, style: style, playing: false,
                          storageModel: { rebuilds += 1; return onScreen }, shown: { $0 })
        XCTAssertFalse(p.render, "a re-render inside the debounce would put back the older model text")
        XCTAssertEqual(rebuilds, 0)

        // The commit lands: our own text, not an external change.
        gate.accounted(onScreen)
        let after = gate.plan(model: onScreen, commitPending: false, style: style, playing: false,
                              storageModel: { onScreen }, shown: { $0 })
        XCTAssertFalse(after.render)
    }

    func testExternalChangeStillRenders() {
        var gate = BodyUpdateGate<Style>()
        let style = Style(suggested: [], quote: nil)
        gate.accounted("Old body")
        let p = gate.plan(model: "Phone edit", commitPending: false, style: style, playing: false,
                          storageModel: { "Old body" }, shown: { $0 })
        XCTAssertTrue(p.render, "a phone sync with no local commit pending replaces the text")
        XCTAssertFalse(p.restyle, "render already restyled")
    }

    func testLegacyShownFormDoesNotLoop() {
        var gate = BodyUpdateGate<Style>()
        let style = Style(suggested: [], quote: nil)
        let raw = "Text with [[img_001]] mid sentence"
        let shown = "Text with mid sentence\n[[img_001]]"
        let p = gate.plan(model: raw, commitPending: false, style: style, playing: false,
                          storageModel: { shown }, shown: { _ in shown })
        XCTAssertFalse(p.render, "a pre-v2 body shown through the Q13 fallback is not an external change")
    }

    // MARK: - M13: the flush round trip runs off the main actor

    func testRoundTripOffMainMatchesAndTitleOnlyEditIsNotABodyMove() async {
        let people = [Person(canonical: "[[Nick Jansen]]", aliases: ["Nick"], short: "Nick",
                             lastModifiedAt: "2026-01-01T00:00:00.000Z")]
        let stored = "I met Nick today."
        let linked = Sanitiser.process(text: stored, people: people).sanitised
        let sync = MacEditRoundTrip.compute(body: linked, before: stored, people: people,
                                            neverLink: [], namePicks: [:])
        let off = await MacEditRoundTrip.offMain(body: linked, before: stored, people: people,
                                                 neverLink: [], namePicks: [:])
        XCTAssertEqual(sync, off)
        XCTAssertFalse(off.bodyMoved, "an unchanged body (title-only edit) is not a words edit")
        let moved = await MacEditRoundTrip.offMain(body: linked + " More.", before: stored,
                                                   people: people, neverLink: [], namePicks: [:])
        XCTAssertTrue(moved.bodyMoved)
    }
}
