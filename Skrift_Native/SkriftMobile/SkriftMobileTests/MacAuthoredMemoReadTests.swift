import XCTest
import SwiftData
@testable import SkriftMobile

/// Q139 (R36, C71, C124): the phone reads a memo the Mac authored the way it reads its own.
/// The fixture is what `MacMemoAuthor.author` wrote (`test-fixtures/mac-authored-memos/memos.json`,
/// pinned by the Mac's `MacAuthoredMemoShapeTests`): it is loaded into the phone's store, its
/// assets materialize through `AssetMaterializer` (the receiving-device path), and every
/// reference the phone resolves by name (audio, `[[img_N]]`) lands on a real file.
@MainActor
final class MacAuthoredMemoReadTests: XCTestCase {

    static let videoID = UUID(uuidString: "11111111-1111-4111-8111-000000000001")!
    static let noteID = UUID(uuidString: "11111111-1111-4111-8111-000000000002")!
    static let pictureID = UUID(uuidString: "11111111-1111-4111-8111-000000000003")!
    static let mergedID = UUID(uuidString: "11111111-1111-4111-8111-000000000004")!
    static let clipPictureID = UUID(uuidString: "11111111-1111-4111-8111-000000000005")!
    static let movID = UUID(uuidString: "11111111-1111-4111-8111-000000000006")!

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test-fixtures/mac-authored-memos/memos.json")
    }

    private struct Fixture: Decodable {
        struct MemoRow: Decodable {
            var id: UUID
            var audioFilename: String
            var duration: Double
            var recordedAt: String
            var transcriptStatus: String
            var significance: Double
            var transcript: String?
            var metadata: String?
        }
        struct AssetRow: Decodable {
            var memoID: UUID
            var kind: String
            var filename: String
            var blob: String
        }
        var memos: [MemoRow]
        var assets: [AssetRow]
    }

    private var repo: NotesRepository!
    private var written: [String] = []

    override func setUp() async throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: Self.fixtureURL))
        repo = NotesRepository(inMemory: true)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for m in fixture.memos {
            repo.context.insert(Memo(
                id: m.id, audioFilename: m.audioFilename, duration: m.duration,
                recordedAt: try XCTUnwrap(iso.date(from: m.recordedAt)),
                transcript: m.transcript,
                transcriptStatus: TranscriptStatus(rawValue: m.transcriptStatus) ?? .pending,
                significance: m.significance,
                metadataData: m.metadata.map { Data($0.utf8) }))
        }
        for a in fixture.assets {
            repo.context.insert(MemoAsset(memoID: a.memoID, kind: a.kind, filename: a.filename,
                                          blob: try XCTUnwrap(Data(base64Encoded: a.blob))))
            written.append(a.filename)
        }
        repo.save()
        for name in written { try? FileManager.default.removeItem(at: url(name)) }
        AssetMaterializer.materializeMissing(repo)
    }

    override func tearDown() async throws {
        for name in written { try? FileManager.default.removeItem(at: url(name)) }
        repo = nil
    }

    private func url(_ name: String) -> URL { AppPaths.recordingsDirectory.appendingPathComponent(name) }

    private func memo(_ id: UUID) throws -> Memo { try XCTUnwrap(repo.memo(id: id)) }

    private func assertEveryPictureResolves(_ m: Memo, file: StaticString = #filePath, line: UInt = #line) {
        let manifest = m.metadata?.imageManifest ?? []
        XCTAssertFalse(manifest.isEmpty, "no picture manifest", file: file, line: line)
        for n in 1...max(1, manifest.count) {
            guard let u = m.imageURL(markerIndex: n) else {
                XCTFail("[[img_\(n)]] has no manifest entry", file: file, line: line); continue
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: u.path),
                          "[[img_\(n)]] → \(u.lastPathComponent) was not materialized", file: file, line: line)
        }
    }

    // MARK: - Per kind

    func testVideoReadsAsAVideoAndPlaysItsAudio() throws {
        let m = try memo(Self.videoID)
        XCTAssertEqual(SourceKind.of(m), .video, "capture-source-07")
        XCTAssertEqual(m.metadata?.sourceType, MemoMetadata.Source.video)
        let audio = try XCTUnwrap(m.audioURL)
        XCTAssertEqual(audio.pathExtension, "m4a", "the extracted audio is named as audio, never .MOV")
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
        assertEveryPictureResolves(m)
    }

    func testAppleNoteIsANoteWithNoAudio() throws {
        let m = try memo(Self.noteID)
        XCTAssertEqual(SourceKind.of(m), .appleNote, "capture-source-08")
        XCTAssertNil(m.audioURL)
        XCTAssertEqual(m.duration, 0)
    }

    func testPictureNoteIsNotAVoiceMemoAndEveryMarkerResolves() throws {
        let m = try memo(Self.pictureID)
        XCTAssertNotEqual(SourceKind.of(m), .voiceMemo, "capture-source-08")
        XCTAssertNil(m.audioURL)
        assertEveryPictureResolves(m)   // capture-source-20
        XCTAssertEqual(m.metadata?.imageManifest?.count, 2)
    }

    func testMergedNoteKeepsItsParagraphBreaks() throws {
        let m = try memo(Self.mergedID)
        let manifest = try XCTUnwrap(m.metadata?.clipManifest, "C124: the clip manifest reached the phone")
        XCTAssertEqual(manifest.count, 3)
        // What a phone re-transcribe feeds the paragrapher (MemoSaver).
        XCTAssertEqual(MixedBundle.breakStarts(manifest), [4.5, 9.25])
        let audio = try XCTUnwrap(m.audioURL)
        XCTAssertEqual(audio.pathExtension, "m4a", "the stitched audio is named as m4a, never .opus")
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
    }

    func testClipPlusPictureResolvesItsPicture() throws {
        let m = try memo(Self.clipPictureID)
        XCTAssertEqual(SourceKind.of(m), .voiceMemo)
        XCTAssertEqual(m.metadata?.imageManifest?.first?.offsetSeconds, 2.5)
        assertEveryPictureResolves(m)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(m.audioURL).path))
    }

    /// The open question in Q139: does a `.mov`-named audio blob keep its name on the phone?
    func testMovAudioBlobKeepsItsNameOnThePhone() throws {
        let m = try memo(Self.movID)
        XCTAssertEqual(m.audioFilename, "talk.mov")
        let audio = try XCTUnwrap(m.audioURL)
        XCTAssertEqual(audio.lastPathComponent, "talk.mov")
        XCTAssertEqual(try Data(contentsOf: audio), Data("AUDIO mov".utf8))
    }
}
