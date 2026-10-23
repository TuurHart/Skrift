import XCTest
@testable import SkriftMobile

/// Q426 (C2, C28, C36): the iPad polishes through copy-edit v2 — the same `CopyEditV2.runPass`
/// and `CopyEditV2.turn` the Mac runs. MLX-free: the model is a closure that records its calls.
@MainActor
final class PolishV2Tests: XCTestCase {

    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [(prompt: String, text: String, cap: Int)] = []
        func add(_ p: String, _ t: String, _ c: Int) { lock.lock(); list.append((p, t, c)); lock.unlock() }
        var all: [(prompt: String, text: String, cap: Int)] { lock.lock(); defer { lock.unlock() }; return list }
    }

    final class Steps: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [PolishStep] = []
        func add(_ s: PolishStep) { lock.lock(); list.append(s); lock.unlock() }
        var all: [PolishStep] { lock.lock(); defer { lock.unlock() }; return list }
    }

    private let prompts = CopyEditV2.Prompts(copyEdit: "EDIT", title: "TITLE", summary: "SUMMARY")

    /// A model that copy-edits by returning the text unchanged, and answers title/summary.
    private func model(_ calls: Calls) -> CopyEditV2.Generate {
        { prompt, text, cap in
            calls.add(prompt, text, cap)
            switch prompt {
            case "TITLE": return "  A title \n"
            case "SUMMARY": return "A summary."
            default: return text
            }
        }
    }

    private func longText(_ words: Int) -> String {
        (0..<words).map { "word\($0 % 7)" }.joined(separator: " ") + "."
    }

    func testASpokenNoteGoesThroughTheV2Pass() async throws {
        let calls = Calls(), steps = Steps()
        let body = longText(90)
        let r = try await PolishV2.polish(transcript: body, source: .spoken, prompts: prompts,
                                          generate: model(calls), onStep: { s, _ in steps.add(s) })
        XCTAssertEqual(calls.all.map(\.cap).suffix(2), [64, 256], "title, then summary past the threshold")
        XCTAssertTrue(calls.all[0].prompt.hasPrefix("EDIT"), "the copy-edit prompt carries v2's keep-spelling rule")
        XCTAssertNotEqual(calls.all[0].prompt, "EDIT")
        XCTAssertEqual(r.title, "A title")
        XCTAssertEqual(r.summary, "A summary.")
        XCTAssertFalse(r.copyedit.isEmpty)
        XCTAssertEqual(steps.all.last, .summary)
        XCTAssertTrue(steps.all.contains(.title))
    }

    func testAShortNoteGetsNoSummary() async throws {
        let calls = Calls()
        let r = try await PolishV2.polish(transcript: "Call the bank about the kiln loan.", source: .spoken,
                                          prompts: prompts, generate: model(calls), onStep: { _, _ in })
        XCTAssertEqual(r.summary, "")
        XCTAssertFalse(calls.all.contains { $0.prompt == "SUMMARY" })
    }

    func testATypedNoteIsNeverReparagraphed() async throws {
        let body = "First line of a typed note about the glaze and the kiln.\nSecond line, same paragraph."
        let r = try await PolishV2.polish(transcript: body, source: .typed, prompts: prompts,
                                          generate: { p, t, _ in p == "TITLE" ? "T" : p == "SUMMARY" ? "" : "First line.\n\nSecond line." },
                                          onStep: { _, _ in })
        XCTAssertEqual(r.copyedit, body, "a typed note the model re-paragraphed ships as typed (C34)")
    }

    func testSpeakerTurnsAreNeverCopyEdited() async throws {
        let calls = Calls()
        let body = "**Fenna:** Who cleans the bike side?\n\n**Lotte:** You do."
        let r = try await PolishV2.polish(transcript: body, source: .conversation, prompts: prompts,
                                          generate: model(calls), onStep: { _, _ in })
        XCTAssertEqual(r.copyedit, body)
        XCTAssertFalse(calls.all.contains { $0.prompt.hasPrefix("EDIT") }, "no copy-edit call for a conversation")
    }

    func testAShareCaptureGetsTitleAndSummaryButNoCopyEdit() async throws {
        let calls = Calls()
        let r = try await PolishV2.polish(transcript: "Good read on local-first software.", source: .share,
                                          prompts: prompts, generate: model(calls), onStep: { _, _ in })
        XCTAssertEqual(r.copyedit, "")
        XCTAssertEqual(r.title, "A title")
        XCTAssertEqual(r.summary, "A summary.", "a share capture's annotation always gets a summary")
        XCTAssertFalse(calls.all.contains { $0.prompt.hasPrefix("EDIT") })
    }

    func testTitleAndSummaryReadProseWithoutLinksOrPictures() async throws {
        let calls = Calls()
        _ = try await PolishV2.redo(.title, transcript: "Lunch with [[Lotte Vos|Lotte]] [[img_001]] at noon.",
                                    source: .spoken, prompts: prompts, generate: model(calls))
        XCTAssertEqual(calls.all.map(\.text), ["Lunch with Lotte at noon."])
    }

    func testRedoCopyEditLeavesConversationsAlone() async throws {
        let calls = Calls()
        let body = "**Fenna:** Hi.\n\n**Lotte:** Hello."
        let out = try await PolishV2.redo(.copyEdit, transcript: body, source: .conversation,
                                          prompts: prompts, generate: model(calls))
        XCTAssertEqual(out, body)
        XCTAssertTrue(calls.all.isEmpty)
    }

    func testAPicturesOnlyBodyGetsNoTitleCall() async throws {
        let calls = Calls()
        let out = try await PolishV2.redo(.title, transcript: "[[img_001]]", source: .spoken,
                                          prompts: prompts, generate: model(calls))
        XCTAssertEqual(out, "")
        XCTAssertTrue(calls.all.isEmpty, "a model given nothing invents a note (C177)")
    }

    func testTheMemoSaysWhichSourceItIs() {
        XCTAssertEqual(Memo(audioFilename: "a.m4a", transcript: "Hello there.").copyEditV2Source, .spoken)
        XCTAssertEqual(Memo(audioFilename: "", transcript: "Typed.").copyEditV2Source, .typed)
        XCTAssertEqual(Memo(audioFilename: "a.m4a", transcript: "**Fenna:** Hi.\n\n**Lotte:** Hello.").copyEditV2Source,
                       .conversation)
        let share = Memo.make(audioFilename: "", title: "Link",
                              sharedContent: SharedContent(type: .url, url: "https://example.com", urlTitle: "Page"))
        XCTAssertEqual(share.copyEditV2Source, .share)
    }
}
