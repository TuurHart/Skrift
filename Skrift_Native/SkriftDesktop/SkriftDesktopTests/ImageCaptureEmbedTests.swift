import XCTest

/// Q518 (C57, C58): a marker-less shared image capture embeds its picture under the one name the
/// copied file gets (`ExportProfile.pictureName`), so the embed resolves in the vault and in the
/// Export all zip. Before, it embedded the shared file's name (`IMG_4471.jpg`) while the picture
/// was copied as `photo_<memoid>_001.jpg`. Corpus: cap-image-no-words, -voice-ramble, -typed-note.
@MainActor
final class ImageCaptureEmbedTests: XCTestCase {
    typealias H = ExportDiffHarnessTests

    private static let captures = ["cap-image-no-words", "cap-image-voice-ramble", "cap-image-typed-note"]
    private static let embed = try! NSRegularExpression(pattern: #"!\[\[([^\]|#]+)\]\]|!\[\]\(([^)]+)\)"#)

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("q518-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: scratch) }

    private func embeds(in md: String) -> [String] {
        Self.embed.matches(in: md, range: NSRange(md.startIndex..., in: md)).map { m in
            let r = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
            return String(md[Range(r, in: md)!])
        }
    }

    func testEveryEmbedInTheCapturesResolvesToAFileInTheVault() throws {
        let out = try H.V2Engine().exports(corpus: H.corpusRoot, scratch: scratch)
        var checked = 0
        for slug in Self.captures {
            for profile in H.Profile.allCases {
                let key = "\(slug).\(profile.rawValue)"
                let o = try XCTUnwrap(out[key], key)
                let rel = try XCTUnwrap(o.path, "\(key) exports: \(o.markdown)")
                let root = scratch.appendingPathComponent("v2-export-\(profile.rawValue)", isDirectory: true)
                let noteURL = root.appendingPathComponent(rel)
                let stem = noteURL.deletingPathExtension().lastPathComponent
                let assets = profile == .vault
                    ? noteURL.deletingLastPathComponent().appendingPathComponent(VaultLayout.images)
                    : noteURL.deletingLastPathComponent()

                let names = embeds(in: o.markdown)
                XCTAssertEqual(names, [stem + "_001.jpg"], "\(key): one embed, the export name")
                for name in names {
                    XCTAssertTrue(FileManager.default.fileExists(atPath: assets.appendingPathComponent(name).path),
                                  "\(key) embeds \(name), and it is in the export")
                    checked += 1
                }
                XCTAssertFalse(names.contains("IMG_4471.jpg"), "\(key): the shared file's own name is no embed")
                let strays = ((try? FileManager.default.contentsOfDirectory(atPath: assets.path)) ?? [])
                    .filter { $0.hasPrefix("photo_") }
                XCTAssertTrue(strays.isEmpty, "\(key): no second copy under the stored name: \(strays)")
            }
        }
        XCTAssertEqual(checked, 6)
    }

    // MARK: - the rule, without a vault

    private func captureNote(manifest: [String]) -> ExportV2.Note {
        var input = CompilerInput(filename: "capture", sourceType: .capture)
        input.sharedContent = SharedContent(type: .image, fileName: "IMG_4471.jpg", mimeType: "image/jpeg")
        var note = ExportV2.Note(input: input, title: "Shared photo")
        note.pictureManifest = manifest
        return note
    }

    func testAManifestPictureIsPlacedUnderItsExportName() {
        let out = ExportV2.compile(captureNote(manifest: ["photo_X_001.jpg"]), profile: .obsidian, stem: "Shared photo")
        XCTAssertEqual(out.pictures, [PlacedPicture(source: "photo_X_001.jpg", embedName: "Shared photo_001.jpg")])
        XCTAssertTrue(out.markdown.contains("![[Shared photo_001.jpg]]"), out.markdown)
        XCTAssertTrue(out.removedPictures.isEmpty)
    }

    func testAPictureNotOnThisDeviceDropsItsEmbed() {
        let out = ExportV2.compile(captureNote(manifest: ["photo_X_001.jpg"]), profile: .obsidian, stem: "Shared photo",
                                   placePicture: { _, _ in nil })
        XCTAssertTrue(out.pictures.isEmpty)
        XCTAssertFalse(out.markdown.contains("!["), "C196: no embed for a picture it does not have: \(out.markdown)")
    }

    func testACaptureWithNoManifestKeepsTheSharedName() {
        let out = ExportV2.compile(captureNote(manifest: []), profile: .obsidian, stem: "Shared photo")
        XCTAssertTrue(out.markdown.contains("![[IMG_4471.jpg]]"), "the legacy folder copy places it under that name")
    }
}
