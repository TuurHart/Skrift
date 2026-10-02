import XCTest

/// Q108 (parity audit P9, C115/C240): a string both apps show lives ONCE in
/// `Shared/UI/SharedCopy.swift` / `NoteMenu.swift`. This reads both apps' source and
/// asserts each shared constant is referenced from the phone tree AND the Mac tree,
/// and that the old twin literals are gone from both.
final class SharedCopyUsageTests: XCTestCase {

    /// Skrift_Native/ (this file → SkriftDesktopTests → SkriftDesktop → Skrift_Native)
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
            // App sources only: tests, build output and mocks do not count as usage.
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

    /// Referenced by BOTH apps.
    private let both = [
        "SharedCopy.recordVerb", "SharedCopy.processVerb",
        "SharedCopy.processingStep", "SharedCopy.processingDownload",
        "SharedCopy.emptyLibraryTitle", "SharedCopy.emptyLibraryBody",
        "SharedCopy.noMatchesTitle", "SharedCopy.noMatchesBody",
        "SharedCopy.reviewEmptyDay", "SharedCopy.backVerb",
        "SharedCopy.wayOutEmptyTitle", "SharedCopy.wayOutEmptyBody",
        "SharedCopy.wayOutIntro", "SharedCopy.wayOutFadingLabel",
        "SharedCopy.wayOutDeletedLabel", "SharedCopy.wayOutFooter",
        "SharedCopy.peekNoTranscript",
        "NoteMenuItem.lockItem", "NoteMenuItem.copyTranscript", "NoteMenuItem.delete",
    ]

    func testEverySharedConstantIsReadByPhoneAndMac() throws {
        let phone = Self.noComments(try Self.source(of: "SkriftMobile"))
        let mac = Self.noComments(try Self.source(of: "SkriftDesktop"))
        for ref in both {
            XCTAssertTrue(phone.contains(ref), "\(ref) is not referenced from the phone tree")
            XCTAssertTrue(mac.contains(ref), "\(ref) is not referenced from the Mac tree")
        }
        // Mac-only facts (the phone has no equivalent surface).
        for ref in ["SharedCopy.processingLoading", "SharedCopy.peekUndoLine", "NoteMenuItem.copyMarkdown"] {
            XCTAssertTrue(mac.contains(ref), "\(ref) is not referenced from the Mac tree")
        }
    }

    func testTwinLiteralsAreGone() throws {
        let banned = [
            "\"No memos yet\"", "\"No notes yet\"", "Tap the mic", "click + ",
            "\"Nothing recorded this day.\"", "\"No notes this day.\"", "\"back to calendar\"",
            "\"Lock Note\"", "\"Remove Lock\"", "\"Nothing is fading.\"", "\"No transcript.\"",
            "\"No transcript yet.\"", "Your iPhone does the permanent deleting", "Loading transcription model",
            "Text(\"Record\")", "Text(\"Process\")", "Menu(\"Copy\")",
        ]
        for app in ["SkriftMobile", "SkriftDesktop"] {
            let src = Self.noComments(try Self.source(of: app))
            for lit in banned {
                XCTAssertFalse(src.contains(lit), "\(app) still types \(lit) itself — read SharedCopy / NoteMenuItem")
            }
        }
    }

    /// The retention numbers come from the policy, never a literal.
    func testWayOutNumbersComeFromPolicy() {
        XCTAssertTrue(SharedCopy.wayOutFooter.contains("\(TrashPolicy.retentionDays) days"))
        XCTAssertTrue(SharedCopy.wayOutFooter.contains("\(MemoLifecycle.fadeAfterDays) days"))
        XCTAssertTrue(SharedCopy.wayOutEmptyBody.contains("\(MemoLifecycle.fadeAfterDays) days"))
        XCTAssertTrue(SharedCopy.peekUndoLine.contains("\(TrashPolicy.retentionDays) days"))
    }
}
