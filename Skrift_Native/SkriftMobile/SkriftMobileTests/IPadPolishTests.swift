import XCTest
@testable import SkriftMobile

/// POLISH (iPad wave, v2). Exercises the parts that CAN be tested without MLX (honesty
/// contract — the sim can't run Metal-JIT MLX, so live generation is device-owed): the
/// device gate and the shared `PolishPrompts` budget/guard functions. The polish pass itself
/// is copy-edit v2 (`PolishV2Tests`); v1's `PolishEscrow` went with v1 (Q427). No
/// `MLXPolishEngine` is instantiated here.
final class IPadPolishTests: XCTestCase {

    // MARK: - Gate (runs on the iPhone 17 sim, which is unsupported)

    func testPolishGateUnsupportedOnSimulator() {
        // The unit suite runs on the simulator; MLX needs a real Metal GPU, so the gate is
        // false here (and on every phone). Capable-iPad behavior is device-owed.
        XCTAssertFalse(PolishGate.isSupported)
    }

    // MARK: - Copy-edit token budget (restored 2026-08-18 — the flat 1024 cut long notes)

    /// The budget is sized from the INPUT: floor 1024 (short notes lose nothing — the
    /// cap is a ceiling, not a target), ×1.5 over the ~4-chars/token estimate, hard
    /// ceiling 8192. Both engines read this one function (PolishPrompts) — the old
    /// Python backend had exactly this per-memo sizing and the native ports lost it.
    func testCopyEditTokenBudgetScalesWithInput() {
        XCTAssertEqual(PolishPrompts.copyEditTokenBudget(forInput: "short note"), 1024, "floor")
        let words2k = Array(repeating: "word", count: 2_000).joined(separator: " ")   // ~10k chars → ~2.5k tokens
        let budget = PolishPrompts.copyEditTokenBudget(forInput: words2k)
        XCTAssertGreaterThan(budget, 3_000, "a long note gets room to finish")
        XCTAssertLessThanOrEqual(budget, 8_192)
        let huge = String(repeating: "x", count: 200_000)
        XCTAssertEqual(PolishPrompts.copyEditTokenBudget(forInput: huge), 8_192, "ceiling bounds a runaway")
    }

    /// Truncation guard: an output that fills ~the whole cap most likely stopped at
    /// the cap, not at end-of-text — callers keep the unedited body (a raw note is
    /// honest; a half note is silent data loss).
    func testLooksTruncated() {
        let cap = 1_024
        XCTAssertTrue(PolishPrompts.looksTruncated(output: String(repeating: "x", count: 4_096), cap: cap))
        XCTAssertFalse(PolishPrompts.looksTruncated(output: String(repeating: "x", count: 2_000), cap: cap))
    }

    // MARK: - The wall cure + shrink guard (2026-08-19)

    /// Long text with no breaks gets deterministic paragraphs (~4 sentences each);
    /// already-paragraphed or short text passes through byte-identical.
    func testEnsureParagraphsBreaksAWall() {
        let wall = Array(repeating: "Dit is een zin over het atelier en het licht.", count: 30).joined(separator: " ")
        let out = PolishPrompts.ensureParagraphs(wall)
        XCTAssertGreaterThanOrEqual(out.components(separatedBy: "\n\n").count, 5)
        XCTAssertEqual(out.replacingOccurrences(of: "\n\n", with: " "), wall, "content untouched, only breaks added")
        let already = "One.\n\nTwo.\n\nThree." + String(repeating: " padding zin hier.", count: 60)
        XCTAssertEqual(PolishPrompts.ensureParagraphs(already), already)
        XCTAssertEqual(PolishPrompts.ensureParagraphs("Kort."), "Kort.")
    }

    /// Output far below the input's word count = the model ate the note (fx5).
    func testLostTooMuch() {
        let input = Array(repeating: "word", count: 100).joined(separator: " ")
        XCTAssertTrue(PolishPrompts.lostTooMuch(input: input, output: "just a few words left here"))
        XCTAssertFalse(PolishPrompts.lostTooMuch(input: input, output: Array(repeating: "word", count: 70).joined(separator: " ")))
        XCTAssertFalse(PolishPrompts.lostTooMuch(input: "tiny note", output: "tiny"), "tiny notes may compress")
    }

    // (The v1 auto-polish tracker was REMOVED in v2 — the iPad polishes only on
    // the visible Polish verb, the Mac's idiom; Tuur 2026-07-23.)
}
