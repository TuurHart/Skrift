import XCTest

/// Q53 (C277/C282): "nothing heavy runs per keystroke" — proves each of the
/// four typing-path costs the phone/iPad sweep found (`plan/sweep-a-editor.md`,
/// `plan/sweep-b-list-launch.md`) runs AT MOST ONCE per commit, via the shared
/// (Shared/Pipeline) seams both apps route through. The mobile-only call sites
/// (`QuickNoteView`, `NotesRepository`, `MemoDetailView`) aren't reachable from
/// this host-less desktop bundle — `plan/mtest.sh QuickNoteTests` covers those
/// directly on the phone target.
@MainActor
final class TypingPathCostTests: XCTestCase {

    // MARK: - 1. Quick Note save debounce (was: `context.save()` per keystroke)

    func testQuickNoteStyleSaveCollapsesRapidKeystrokesToOneCommit() {
        let exp = expectation(description: "debounced save fires once")
        var fireCount = 0
        let debouncer = CommitDebouncer(interval: .milliseconds(30))

        // Simulate 5 keystrokes in quick succession, well inside the debounce window.
        for _ in 0..<5 {
            debouncer.schedule { fireCount += 1 }
        }

        Task {
            try? await Task.sleep(for: .milliseconds(150))
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(fireCount, 1, "5 rapid keystrokes must collapse to exactly one save")
    }

    func testDebouncerFlushRunsImmediatelyAndCancelsThePendingFire() {
        var fireCount = 0
        let debouncer = CommitDebouncer(interval: .seconds(5))
        debouncer.schedule { fireCount += 1 }
        debouncer.flush { fireCount += 1 }
        XCTAssertEqual(fireCount, 1, "flush must run exactly once, synchronously, and cancel the pending timer")
    }

    // MARK: - 2. `allTags()`-style cache (was: full memo re-fetch per read)

    func testKeyedCacheComputesOnceUntilTheKeyChanges() {
        let cache = CommitOnceCache<Int, [String]>()
        var version = 0

        _ = cache.value(for: version) { ["a", "b"] }
        _ = cache.value(for: version) { ["a", "b"] }
        _ = cache.value(for: version) { ["a", "b"] }
        XCTAssertEqual(cache.computeCount, 1, "repeated reads at the same memo-set version must not recompute")

        version += 1   // a save() bumped the version — one real change
        _ = cache.value(for: version) { ["a", "b", "c"] }
        XCTAssertEqual(cache.computeCount, 2, "a version bump must recompute exactly once")
    }

    // MARK: - 3. `SpeakerTranscript.parse` (was: fresh regex + full rescan per call site)

    func testSpeakerTranscriptParseRunsOnceForRepeatedCallsOnTheSameText() {
        let text = "**Tuur:** hello\n\n**Fable:** hi there\n\n**Tuur:** how's it going"
        // Prime with a distinct text so this test is independent of run order.
        _ = SpeakerTranscript.parse("**A:** x\n\n**B:** y")
        let before = SpeakerTranscript.debugParseComputeCount

        // Mirrors MemoDetailView's real shape: several call sites parse the SAME
        // committed text once each (page-kind switch, recomputeSpans, macPolish, …).
        for _ in 0..<5 {
            XCTAssertNotNil(SpeakerTranscript.parse(text))
        }
        XCTAssertEqual(SpeakerTranscript.debugParseComputeCount, before + 1,
                       "5 parses of the SAME committed text must compile+scan exactly once")

        // A genuinely new commit (different text) must still recompute.
        _ = SpeakerTranscript.parse(text + "\n\n**Fable:** one more")
        XCTAssertEqual(SpeakerTranscript.debugParseComputeCount, before + 2,
                       "a changed transcript must recompute")
    }

    // MARK: - 4. `recomputeSpans`-style double-fire (was: onChange + onCommit both firing)

    func testRecomputeSpansStyleDoubleTriggerCollapsesToOneComputeCommit() {
        let cache = CommitOnceCache<String, Int>()
        var computeCalls = 0
        let transcript = "hello world"

        func recomputeSpans() {
            _ = cache.value(for: transcript) { computeCalls += 1; return computeCalls }
        }

        // The commit fires BOTH triggers that used to double-run the name-span
        // scan: the `.onChange(of: memo.transcript)` and the (now-removed)
        // direct call from `onCommit`. Same key ⇒ the second is free.
        recomputeSpans()
        recomputeSpans()
        XCTAssertEqual(computeCalls, 1, "two triggers on the same commit must scan once")

        // A later, real commit (new text) recomputes again.
        func recomputeSpans(for text: String) {
            _ = cache.value(for: text) { computeCalls += 1; return computeCalls }
        }
        recomputeSpans(for: "hello world, more")
        XCTAssertEqual(computeCalls, 2, "a new commit's text must still recompute")
    }
}
