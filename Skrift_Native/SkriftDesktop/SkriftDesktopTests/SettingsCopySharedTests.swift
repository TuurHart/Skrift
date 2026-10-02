import XCTest

/// Q159 (D119, C217, parity audit setexp-13/-15/-25/-42): the sync sentences, the language
/// footer and the model download sizes are single-sourced in `SharedCopy` / `ASRLanguageMode`
/// / `ModelSizes` and read from BOTH apps' trees. The phone target carries the same-named
/// class (SkriftMobileTests) so `plan/mtest.sh SettingsCopySharedTests` runs there too.
final class SettingsCopySharedTests: XCTestCase {

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

    // MARK: values

    func testSyncSentenceNamesEverythingTheSwitchGates() {
        let s = SharedCopy.syncWhatSyncs
        for word in ["notes", "names", "custom words", "language", "destinations", "polish prompts", "iCloud"] {
            XCTAssertTrue(s.contains(word), "the one sync sentence must name \(word)")
        }
        XCTAssertTrue(SharedCopy.syncSameAccount.contains("same iCloud account"))
    }

    func testLanguageFooterSaysItSyncs() {
        XCTAssertTrue(ASRLanguageMode.footer.contains("syncs to your other devices"))
    }

    func testModelSizesAreOneFigure() {
        XCTAssertEqual(ModelSizes.parakeet, "494 MB")
        XCTAssertEqual(ModelSizes.gemma, "8.9 GB")
        XCTAssertEqual(ModelSizes.gemmaFreeSpace, "~9 GB free")
        XCTAssertEqual(ModelSizes.spotter, "~100 MB")
        XCTAssertTrue(SettingsCopy.customWordsHelp.contains(ModelSizes.spotter))
    }

    // MARK: usage — both trees read them

    private let both = [
        "SharedCopy.syncWhatSyncs", "SharedCopy.syncSameAccount",
        "ASRLanguageMode.footer",
        "ModelSizes.parakeet",
    ]

    func testEverySharedNameIsReadByPhoneAndMac() throws {
        let phone = Self.noComments(try Self.source(of: "SkriftMobile"))
        let mac = Self.noComments(try Self.source(of: "SkriftDesktop"))
        for ref in both {
            XCTAssertTrue(phone.contains(ref), "\(ref) is not referenced from the phone tree")
            XCTAssertTrue(mac.contains(ref), "\(ref) is not referenced from the Mac tree")
        }
        // The two Gemma figures: the Mac wizard and the iPad's polish screen.
        XCTAssertTrue(mac.contains("ModelSizes.gemma)"), "the Mac wizard must read the Gemma size")
        XCTAssertTrue(phone.contains("ModelSizes.gemma)"), "the iPad polish screen must read the Gemma size")
        XCTAssertTrue(phone.contains("ModelSizes.gemmaFreeSpace"))
    }

    func testTwinLiteralsAreGone() throws {
        let banned = [
            "494 MB", "~0.6 GB", "8.9 GB", "~9 GB",
            "Needs the Mac signed into the same iCloud account",
            "Your notes, names, and custom words sync",
            "keep English for the cleanest English",
            "neither picks up your phone's memos",
        ]
        for app in ["SkriftMobile", "SkriftDesktop"] {
            let src = Self.noComments(try Self.source(of: app))
            for lit in banned {
                XCTAssertFalse(src.contains(lit), "\(app) still types \(lit) itself — read SharedCopy / ModelSizes")
            }
        }
    }
}
