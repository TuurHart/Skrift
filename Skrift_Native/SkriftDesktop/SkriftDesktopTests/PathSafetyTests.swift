import XCTest

/// Q534: every place a name from outside the app becomes a file path stays inside its folder.
/// Real temporary folders, real symlinks; nothing outside the temp folder is touched.
final class PathSafetyTests: XCTestCase {

    private var base: URL!
    private var root: URL!
    private var outside: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("pathsafety-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("root", isDirectory: true)
        outside = base.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    // MARK: the helper

    func testPlainNamesPass() {
        for n in ["a.m4a", "My Book (1).mp3", "..hidden", ".hidden.png", "a..b", "ünï.png", "a\\b"] {
            XCTAssertNotNil(PathSafety.child(n, in: root), "\(n) is a plain name and must keep working")
        }
    }

    func testTraversalAbsoluteAndControlNamesAreRefused() {
        for n in ["", ".", "..", "../x", "a/../../x", "/etc/passwd", "a/b", "x\u{0}y", "x\ny", "x\ty", "x\u{7F}"] {
            XCTAssertNil(PathSafety.child(n, in: root), "\(n.debugDescription) must be refused")
        }
        XCTAssertNil(PathSafety.descendant("../x", in: root))
        XCTAssertNil(PathSafety.descendant("/abs", in: root))
        XCTAssertNil(PathSafety.descendant("a//b", in: root))
        XCTAssertNotNil(PathSafety.descendant("audio/part1.m4a", in: root))
    }

    func testInertPathNeverEscapes() {
        let url = PathSafety.childOrInert("../../x", in: root)
        XCTAssertTrue(PathSafety.isContained(url, in: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testSymlinkedFileAndFolderCannotCarryAnEscape() throws {
        let secret = outside.appendingPathComponent("secret.txt")
        try "s".write(to: secret, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.txt"), withDestinationURL: secret)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("dirlink"), withDestinationURL: outside)
        // a dangling link to a not-yet-existing file outside
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("dangling"),
                                                   withDestinationURL: outside.appendingPathComponent("new.txt"))
        XCTAssertNil(PathSafety.child("link.txt", in: root), "a file symlink out of the folder")
        XCTAssertNil(PathSafety.child("dangling", in: root), "a dangling symlink out of the folder")
        XCTAssertNil(PathSafety.descendant("dirlink/secret.txt", in: root), "a symlinked folder")
        XCTAssertNil(PathSafety.descendant("dirlink/new.txt", in: root), "a new file under a symlinked folder")
    }

    func testSymlinkLoopTerminates() throws {
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"),
                                                   withDestinationURL: root.appendingPathComponent("loop"))
        XCTAssertNil(PathSafety.child("loop", in: root))
    }

    func testRootItselfIsNotInsideRoot() {
        XCTAssertFalse(PathSafety.isContained(root, in: root))
        XCTAssertFalse(PathSafety.isContained(root.appendingPathComponent("a/.."), in: root))
    }

    func testSanitisedFilenameStripsSeparatorsDotsAndControls() {
        XCTAssertEqual(PathSafety.sanitisedFilename("../../etc/passwd"), "etc passwd")
        XCTAssertEqual(PathSafety.sanitisedFilename("..."), "file")
        XCTAssertEqual(PathSafety.sanitisedFilename(".hidden"), "hidden")
        XCTAssertEqual(PathSafety.sanitisedFilename("a\nb\u{0}c"), "a b c")
        XCTAssertEqual(PathSafety.sanitisedFilename("a\\b"), "a b")
        XCTAssertEqual(PathSafety.sanitisedFilename("Plain name.m4a"), "Plain name.m4a")
        XCTAssertEqual(PathSafety.sanitisedFilename("", fallback: "x"), "x")
    }

    // MARK: the export call sites

    /// An export title can never leave the vault folder: the note's path has no separator.
    func testExportTitleStaysInTheVaultRoot() {
        for title in ["../../evil", "/etc/passwd", "a/../b", "..", "...", "\\..\\x", "x/\ny/z"] {
            let stem = VaultName.stem(title: title, filename: "memo.m4a")
            let url = root.appendingPathComponent(stem + ".md")
            XCTAssertFalse(stem.contains("/"), "stem for \(title.debugDescription): \(stem)")
            XCTAssertTrue(PathSafety.isContained(url, in: root), "\(title.debugDescription) -> \(stem)")
        }
    }

    /// An Apple Note's `(Attachments/../x)` reference, plain or percent-encoded, copies nothing
    /// from outside the note's Attachments folder and writes nothing outside the vault folder.
    func testAppleNoteAttachmentRefCannotReadOrWriteOutside() throws {
        let attachments = base.appendingPathComponent("note/Attachments", isDirectory: true)
        let vault = base.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "secret".write(to: base.appendingPathComponent("note/secret.txt"), atomically: true, encoding: .utf8)
        try "ok".write(to: attachments.appendingPathComponent("ok.png"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: attachments.appendingPathComponent("evil.png"),
                                                   withDestinationURL: base.appendingPathComponent("note/secret.txt"))

        let md = "![](Attachments/../secret.txt) ![](Attachments/..%2Fsecret.txt) ![](Attachments/evil.png) ![](Attachments/ok.png)"
        let attDir = vault.appendingPathComponent("Images", isDirectory: true)
        let (out, copied) = VaultExporter.convertNoteAttachments(md, attachmentsSrc: attachments, into: attDir,
                                                                 id: UUID(), profile: .obsidian)
        XCTAssertEqual(copied, 1, "only ok.png is inside the Attachments folder")
        XCTAssertTrue(out.contains("![[ok.png]]"))
        XCTAssertTrue(out.contains("Attachments/../secret.txt"), "a refused ref stays as the author's text")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: attDir.path)) ?? []
        XCTAssertEqual(names, ["ok.png"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("secret.txt").path))
    }
}
