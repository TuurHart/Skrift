import XCTest

/// Q176 (parity audit §3.5, C239/C240, R58): the Settings + Names strings both apps show
/// live ONCE in `Shared/UI/SettingsCopy.swift` / `RetrievalGate.Copy`, and the names filter is
/// one matcher. Reads both apps' source to prove each shared name is used by the phone tree
/// AND the Mac tree and the old twin literals are gone.
final class SharedSettingsCopyTests: XCTestCase {

    private static var nativeRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func source(of app: String) throws -> String {
        let dir = nativeRoot.appendingPathComponent(app, isDirectory: true)
        guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else {
            throw XCTSkip("no \(app) tree at \(dir.path)")
        }
        var out = ""
        for case let url as URL in walker where url.pathExtension == "swift" {
            let p = url.path
            if p.contains("Tests/") || p.contains("/build") || p.contains("/mocks/") { continue }
            if let s = try? String(contentsOf: url, encoding: .utf8) { out += "\n// FILE \(p)\n" + s }
        }
        return out
    }

    private static func noComments(_ s: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    // MARK: the names matcher

    private func person(_ name: String, _ aliases: [String]) -> Person {
        Person(canonical: "[[\(name)]]", aliases: aliases, short: nil, lastModifiedAt: "")
    }

    func testNamesFilterMatchesDisplayNameOrAlias() {
        let bruno = person("Bruno Aragorn", ["Bru", "Brunito"])
        XCTAssertTrue(NamesFilter.matches(bruno, query: "aragorn"), "display name, any case")
        XCTAssertTrue(NamesFilter.matches(bruno, query: "BRUNI"), "an alias finds the person (the phone matched names only)")
        XCTAssertTrue(NamesFilter.matches(bruno, query: "  bru  "), "query is trimmed")
        XCTAssertFalse(NamesFilter.matches(bruno, query: "jack"))
        XCTAssertTrue(NamesFilter.matches(bruno, query: ""), "empty query keeps everyone")
        XCTAssertTrue(NamesFilter.matches(person("José Silva", []), query: "jose"), "accent-insensitive")
    }

    func testNamesFilterApplyKeepsOrder() {
        let people = [person("Anna", ["An"]), person("Bruno", ["Bru"]), person("Hanna", [])]
        XCTAssertEqual(NamesFilter.apply(people, query: "an").map(\.displayName), ["Anna", "Hanna"])
        XCTAssertEqual(NamesFilter.apply(people, query: "").count, 3)
    }

    // MARK: the strings

    func testStaleNamesCopyIsFixed() {
        XCTAssertFalse(NamesCopy.emptyBody.contains("the Mac"), "C80/D77: the phone links names too")
        XCTAssertFalse(NamesCopy.voiceMissingHint.contains("record in a note"), "contradicted the detail recorder")
        XCTAssertEqual(NamesCopy.fullNameHelp(isNew: true).contains("rename"), false)
        XCTAssertTrue(NamesCopy.fullNameHelp(isNew: false).contains("rename"))
    }

    func testObsidianAndDestinationsHelpStates() {
        XCTAssertTrue(SettingsCopy.obsidianHelp(folderName: "Skrift", canProcess: true).contains("“Skrift”"))
        XCTAssertTrue(SettingsCopy.obsidianHelp(folderName: nil, canProcess: false).contains("this iPhone"))
        XCTAssertTrue(SettingsCopy.destinationsHelp(on: true, hasFolder: false)
            .contains(DestinationSettings.needsFolderNotice), "on without a folder names what is missing")
        XCTAssertTrue(SettingsCopy.destinationsHelp(on: true, hasFolder: false).contains("chosen per device"))
        XCTAssertTrue(SettingsCopy.destinationsHelp(on: false, hasFolder: true).hasPrefix("Off,"))
    }

    func testFailureLinesAreOneCopy() {
        XCTAssertEqual(RetrievalGate.Copy.downloadFailed("x"), "Download failed — x")
        XCTAssertEqual(RetrievalGate.Copy.sweepFailed("x"), "Index sweep failed: x")
    }

    // MARK: usage in both apps

    private let both = [
        "SettingsCopy.customWordPlaceholder", "SettingsCopy.customWordsHelp",
        "SettingsCopy.obsidianFolderLabel", "SettingsCopy.chooseVerb", "SettingsCopy.obsidianHelp",
        "SettingsCopy.destinationsToggleLabel", "SettingsCopy.portfolioFolderLabel", "SettingsCopy.destinationsHelp",
        "NamesCopy.emptyTitle", "NamesCopy.emptyBody", "NamesCopy.searchPlaceholder",
        "NamesCopy.voiceEnrolled", "NamesCopy.voiceMissing", "NamesCopy.voiceMissingHint",
        "NamesCopy.voiceEnrolledHelp", "NamesCopy.newPersonTitle", "NamesCopy.editorTitle",
        "NamesCopy.doneVerb", "NamesCopy.cancelVerb", "NamesCopy.fullNameHelp", "NamesCopy.fullNamePlaceholder",
        "NamesFilter.apply",
        "NameRowLook.avatarSize", "NameRowLook.nameSize", "NameRowLook.chevronSize",
        "RetrievalGate.Copy.readyLine", "RetrievalGate.Copy.pausedLine",
        "RetrievalGate.Copy.downloadFailed", "RetrievalGate.Copy.sweepFailed",
        "RetrievalGate.Copy.indexingSub",
    ]

    func testEverySharedNameIsReadByPhoneAndMac() throws {
        let phone = Self.noComments(try Self.source(of: "SkriftMobile"))
        let mac = Self.noComments(try Self.source(of: "SkriftDesktop"))
        for ref in both {
            XCTAssertTrue(phone.contains(ref), "\(ref) is not referenced from the phone tree")
            XCTAssertTrue(mac.contains(ref), "\(ref) is not referenced from the Mac tree")
        }
    }

    func testTwinLiteralsAreGone() throws {
        let banned = [
            "\"Add a word or name…\"", "\"Add a word…\"", "\"Search people\"", "\"Filter names…\"",
            "so the Mac can link", "record in a note or on your Mac", "\"No voice yet\"", "\"Not enrolled",
            "\"Voice enrolled\"", "\"Add voice\"", "\"Edit person\"", "\"Add person\"", "\"Add Person\"",
            "\"Bruno Aragorn\"", "Download failed — \\(", "Model download failed", "\"Index sweep failed",
            "Ready — your notes index", "\"Model downloaded · index paused\"",
            "Separate destinations\"", "\"Portfolio folder\"", "Pick a portfolio folder on this device to export. ",
            "The transcriber listens for these words", "downloads a ~100 MB spotter model",
            "Off, every note goes to your Obsidian vault",
            "\"Obsidian folder\"", "Pick the folder inside your vault",
        ]
        for app in ["SkriftMobile", "SkriftDesktop"] {
            let src = Self.noComments(try Self.source(of: app))
            for lit in banned {
                XCTAssertFalse(src.contains(lit), "\(app) still types \(lit) itself — read SettingsCopy / NamesCopy / RetrievalGate.Copy")
            }
        }
    }
}
