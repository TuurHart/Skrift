import XCTest
@testable import SkriftMobile

/// POLISH lane (iPad wave 1). Exercises the parts that CAN be tested without MLX (honesty
/// contract — the sim can't run Metal-JIT MLX, so live generation is device-owed): the
/// device gate, the pure `PolishEscrow` round-trips (quote protection + memo-link + image
/// markers, via an injected generator), the summary threshold, and the once-per-session
/// auto-polish tracker. No `MLXPolishEngine` is instantiated here.
final class IPadPolishTests: XCTestCase {

    // MARK: - Gate (runs on the iPhone 17 sim, which is unsupported)

    func testPolishGateUnsupportedOnSimulator() {
        // The unit suite runs on the simulator; MLX needs a real Metal GPU, so the gate is
        // false here (and on every phone). Capable-iPad behavior is device-owed.
        XCTAssertFalse(PolishGate.isSupported)
        XCTAssertEqual(PolishGate.polishOnOpenKey, "polishOnOpen")
    }

    // MARK: - Escrow round-trips (identity + mutating generators, MLX-free)

    func testCopyEditKeepsQuoteLinkAndMarker() async throws {
        let uuid = UUID()
        let quote = "> To be, or not to be, that is the question."
        let ramble = "This ties into [[memo:\(uuid.uuidString)|Chapter Two]] and the sketch. [[img_001]] It matters."
        let transcript = quote + "\n\n" + ramble

        // Identity generator: the LLM "changes nothing", so every escrowed piece must return.
        let result = try await PolishEscrow.copyEdit(transcript) { $0 }

        XCTAssertTrue(QuoteProtection.leadingQuoteIntact(original: transcript, edited: result),
                      "the captured quote block must survive byte-identical")
        XCTAssertTrue(result.contains("[[memo:\(uuid.uuidString)|Chapter Two]]"),
                      "the memo link must be reattached")
        XCTAssertTrue(result.contains("[[img_001]]"), "the image marker must be reinserted")
    }

    func testCopyEditProtectsQuoteWhileEditingRamble() async throws {
        let quote = "> Immutable words."
        let transcript = quote + "\n\n" + "some spoken ramble here"

        // A generator that rewrites the ramble (uppercase) must NOT be able to touch the quote.
        let result = try await PolishEscrow.copyEdit(transcript) { $0.uppercased() }

        XCTAssertTrue(result.hasPrefix(quote), "quote block stays byte-identical at the top")
        XCTAssertTrue(QuoteProtection.leadingQuoteIntact(original: transcript, edited: result))
        XCTAssertTrue(result.contains("SOME SPOKEN RAMBLE HERE"), "the ramble WAS edited")
    }

    func testCopyEditQuoteOnlyCaptureSkipsTheLLM() async throws {
        let transcript = "> A lone captured quote.\n> second line."
        var generatorCalled = false

        let result = try await PolishEscrow.copyEdit(transcript) { input in
            generatorCalled = true
            return input
        }

        XCTAssertEqual(result, transcript, "a quote-only capture (no ramble) is returned untouched")
        XCTAssertFalse(generatorCalled, "nothing for the LLM to edit → it is never called")
    }

    func testCopyEditFallsBackWhenLinkTitleIsLost() async throws {
        let uuid = UUID()
        let transcript = "Refer to [[memo:\(uuid.uuidString)|Chapter Two]] soon."

        // The generator drops the title, so the link can't be reattached → the WHOLE body
        // falls back to unedited (never ship a lost reference).
        let result = try await PolishEscrow.copyEdit(transcript) { _ in
            "totally different text without the title"
        }

        XCTAssertEqual(result, transcript, "a lost link title falls the body back to the original")
    }

    // MARK: - Summary threshold (Mac parity)

    func testSummaryThresholdMirrorsMac() {
        XCTAssertEqual(PolishEscrow.summaryMinWords, 75, "matches BatchRunner effectiveSummaryMinWords default")
        XCTAssertFalse(PolishEscrow.wordsMeetSummaryThreshold("just a few words here"))
        let long = Array(repeating: "word", count: 80).joined(separator: " ")
        XCTAssertTrue(PolishEscrow.wordsMeetSummaryThreshold(long))
    }

    // MARK: - Auto-polish once-per-session

    func testAutoPolishTrackerFiresOncePerMemo() {
        var tracker = AutoPolishTracker()
        let a = UUID(), b = UUID()
        XCTAssertTrue(tracker.firstAttempt(a), "first open of a → attempt")
        XCTAssertFalse(tracker.firstAttempt(a), "second open of a → no loop")
        XCTAssertTrue(tracker.firstAttempt(b), "a different memo still gets its one attempt")
        XCTAssertFalse(tracker.firstAttempt(b))
    }
}
