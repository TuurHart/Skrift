import XCTest

/// Q157 / C28: a blank polish prompt is the shared default on every device. The Mac
/// used to autosave any text including blank, polish with an empty prompt and push an
/// empty blob that the iPad read as "default". These tests pin the ONE rule
/// (`PolishPrompts.effective` / `storable`, the same functions the iPad's
/// `PolishPromptsStore` calls) and the two Mac paths through it: the polisher's
/// effective prompt and the sync reconcile's never-an-empty-blob guarantee.
final class MacPromptBlankTests: XCTestCase {

    // MARK: - The store rule

    func testBlankAndWhitespaceAreTheDefault() {
        for blank in ["", "   ", "\n\t \n"] {
            XCTAssertEqual(PolishPrompts.effective(blank, fallback: PolishPrompts.copyEdit),
                           PolishPrompts.copyEdit)
            XCTAssertNil(PolishPrompts.storable(blank, fallback: PolishPrompts.copyEdit),
                         "a blank prompt stores nothing")
        }
    }

    func testCustomTextWinsTrimmedAndDefaultIsNotStored() {
        XCTAssertEqual(PolishPrompts.effective("  Be brief.\n", fallback: PolishPrompts.title), "Be brief.")
        XCTAssertEqual(PolishPrompts.storable("  Be brief.\n", fallback: PolishPrompts.title), "Be brief.")
        XCTAssertNil(PolishPrompts.storable(PolishPrompts.title, fallback: PolishPrompts.title))
    }

    // MARK: - The Mac polisher

    func testBlankMacPromptsPolishWithTheDefaults() {
        var prompts = AppSettings.Prompts()
        prompts.copyEdit = ""
        prompts.summary = "   "
        prompts.title = "\n"
        XCTAssertEqual(prompts.effectiveCopyEdit, PolishPrompts.copyEdit)
        XCTAssertEqual(prompts.effectiveSummary, PolishPrompts.summary)
        XCTAssertEqual(prompts.effectiveTitle, PolishPrompts.title)
        XCTAssertEqual(prompts.effective, AppSettings.Prompts())
    }

    func testCustomMacPromptSurvivesEffective() {
        var prompts = AppSettings.Prompts()
        prompts.copyEdit = "Tidy it."
        XCTAssertEqual(prompts.effectiveCopyEdit, "Tidy it.")
        XCTAssertEqual(prompts.effectiveSummary, PolishPrompts.summary)
    }

    // MARK: - Sync: never an empty blob

    func testBlankLocalPromptNeverPushesAnEmptyBlob() {
        var inserted: [PolishPromptsRecord] = []
        // Mac blanked the copy-edit prompt and edited (real stamp) → pushes.
        let outcome = PolishPromptsSyncCore.reconcile(
            localBlob: .init(copyEdit: "", summary: "  ", title: "My title prompt"),
            localModifiedAt: Date(timeIntervalSince1970: 1_000), records: [],
            insert: { inserted.append($0) }, delete: { _ in })
        guard case .pushedLocal = outcome else { return XCTFail("expected pushedLocal, got \(outcome)") }
        XCTAssertEqual(inserted.count, 1)
        XCTAssertEqual(inserted[0].copyEdit, PolishPrompts.copyEdit)
        XCTAssertEqual(inserted[0].summary, PolishPrompts.summary)
        XCTAssertEqual(inserted[0].title, "My title prompt")
    }

    func testBlankLocalPromptOverwritesCarrierWithDefaultNotEmpty() {
        let carrier = PolishPromptsRecord(copyEdit: "ipad voice", summary: "s", title: "t",
                                          modifiedAt: Date(timeIntervalSince1970: 1_000))
        let outcome = PolishPromptsSyncCore.reconcile(
            localBlob: .init(copyEdit: "", summary: "s", title: "t"),
            localModifiedAt: Date(timeIntervalSince1970: 5_000), records: [carrier],
            insert: { _ in }, delete: { _ in })
        guard case .pushedLocal = outcome else { return XCTFail("expected pushedLocal, got \(outcome)") }
        XCTAssertEqual(carrier.copyEdit, PolishPrompts.copyEdit)
        XCTAssertFalse(carrier.copyEdit.isEmpty)
    }

    func testAnEmptyCarrierAlreadyOnTheServerAdoptsAsTheDefault() {
        let carrier = PolishPromptsRecord(copyEdit: "", summary: "", title: "",
                                          modifiedAt: Date(timeIntervalSince1970: 5_000))
        let outcome = PolishPromptsSyncCore.reconcile(
            localBlob: .defaults, localModifiedAt: Date(timeIntervalSince1970: 1_000),
            records: [carrier], insert: { _ in }, delete: { _ in })
        guard case .adoptRemote(let blob, _) = outcome else {
            return XCTFail("expected adoptRemote, got \(outcome)")
        }
        XCTAssertEqual(blob, .defaults)
    }
}
