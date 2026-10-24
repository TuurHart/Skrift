import XCTest

/// Q468 (C63, C71, D210): a video note's kept movie never reaches the vault, but its poster frame
/// does, as an image embed in the movie's place; and a machine-named share's card is titled by
/// the date it was filmed, not by the bare word "Video".
final class VideoNoteVaultFrameTests: XCTestCase {

    /// A working folder the way a Mac video import leaves it: the manifest naming the kept movie,
    /// and `source.mov` beside it.
    private func workingFolder(movie: Bool = true, capturedAt: Date? = nil) throws -> URL {
        let work = makeTempDir()
        let entry = NoteAttachment.keptMovieEntry(
            filename: VideoKeep.filename(memoID: UUID(), sourceExtension: "mov"),
            originalName: "Video", byteCount: 5, durationSeconds: 1, capturedAt: capturedAt)
        try JSONEncoder().encode([entry]).write(to: work.appendingPathComponent(MacNoteAttachments.manifestName))
        if movie { NoteAttachmentFixture.writeMovie(to: work.appendingPathComponent("source.mov"), seconds: 1) }
        else { try Data("not a movie".utf8).write(to: work.appendingPathComponent("source.mov")) }
        return work
    }

    func testTheKeptMovieMarkerBecomesItsPosterFrameEmbed() throws {
        let work = try workingFolder(); defer { try? FileManager.default.removeItem(at: work) }
        let out = try ExportV2Test.export(body: "[[vid_001]]\n\nSaid something.", working: work, title: "Kiln")

        XCTAssertEqual(out.result.imageCount, 1)
        XCTAssertEqual(out.body, "![[Kiln_frame.jpg]]\n\nSaid something.", "the frame sits where the movie's marker was")
        XCTAssertEqual(out.files, ["Kiln_frame.jpg"], "only the frame is placed, never the movie")
        let frame = try XCTUnwrap(out.file("Kiln_frame.jpg"))
        XCTAssertEqual(Array(try Data(contentsOf: frame).prefix(3)), [0xFF, 0xD8, 0xFF], "a real JPEG")
    }

    func testThePortfolioGetsTheFrameToo() throws {
        let work = try workingFolder(); defer { try? FileManager.default.removeItem(at: work) }
        let out = try ExportV2Test.export(body: "[[vid_001]]\n\nwords", working: work, title: "Kiln", profile: .portfolio)
        XCTAssertEqual(out.result.imageCount, 1)
        let stem = out.result.markdownURL.deletingPathExtension().lastPathComponent
        XCTAssertEqual(out.body, "![](\(stem)_frame.jpg)\n\nwords")
    }

    func testTheFrameIsMadeOnceAndReused() throws {
        let work = try workingFolder(); defer { try? FileManager.default.removeItem(at: work) }
        let first = try XCTUnwrap(MacNoteAttachments.posterFrame(in: work))
        let bytes = try Data(contentsOf: first)
        let second = try XCTUnwrap(MacNoteAttachments.posterFrame(in: work))
        XCTAssertEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: second), bytes, "the dry run and the real write place the same bytes")
    }

    func testAMovieWithNoReadableFrameDropsTheMarker() throws {
        let work = try workingFolder(movie: false); defer { try? FileManager.default.removeItem(at: work) }
        let out = try ExportV2Test.export(body: "[[vid_001]]\n\nwords", working: work, title: "Kiln")
        XCTAssertEqual(out.result.imageCount, 0)
        XCTAssertTrue(out.files.isEmpty, "\(out.files)")
        XCTAssertFalse(out.body.contains("[[vid_"), "a dangling marker is dropped, never printed")
        XCTAssertTrue(out.body.contains("words"))
    }

    /// Export v2's compile of `body` with these attachments, `place` and `poster` as an engine passes them.
    private func compile(_ body: String, manifest: [NoteAttachmentEntry], place: @escaping ExportV2.Place,
                         poster: @escaping ExportV2.Place = { _, _ in nil }) -> ExportV2.Output {
        var note = ExportV2.Note(input: CompilerInput(filename: "n.md", transcript: body, sourceType: .note), title: "Kiln")
        note.attachments = manifest
        return ExportV2.compile(note, profile: .obsidian, stem: "Kiln", placeAttachment: place, poster: poster)
    }

    func testAnEngineWithoutAFrameDropsTheKeptMovieInTheSharedConversion() {
        let entry = NoteAttachment.keptMovieEntry(filename: VideoKeep.filename(memoID: UUID(), sourceExtension: "mov"),
                                                  originalName: "Video", byteCount: 5, durationSeconds: 1)
        let r = compile("[[vid_001]]\n\nwords", manifest: [entry], place: { _, _ in "never" })
        XCTAssertEqual(r.attachments, 0)
        XCTAssertFalse(r.markdown.contains("vid_001"))
        XCTAssertFalse(r.markdown.contains("never"), "the movie is never placed")
    }

    func testABodyAttachedVideoStillGoesBesideTheNote() throws {
        // `video_<uuid>_NNN.<ext>` is a video the person attached in the body, not the kept movie.
        let body = NoteAttachmentEntry(kind: NoteAttachment.Kind.video, filename: "video_\(UUID().uuidString)_002.mov",
                                       name: "clip.mov", uti: "com.apple.quicktime-movie", byteCount: 3)
        var seen: [String] = []
        let r = compile("[[vid_001]]", manifest: [body], place: { source, preferred in
            seen.append(source); return preferred
        }, poster: { _, _ in "frame.jpg" })
        XCTAssertEqual(r.attachments, 1)
        XCTAssertEqual(seen, [body.filename])
        XCTAssertTrue(r.markdown.contains("Kiln_video_001.mov"))
    }

    // MARK: the card's title

    func testAMachineNamedShareIsTitledByTheDateItWasFilmed() throws {
        let when = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-15T12:00:00Z"))
        let entry = NoteAttachment.keptMovieEntry(filename: VideoKeep.filename(memoID: UUID(), sourceExtension: "mov"),
                                                  originalName: "Video", byteCount: 5, durationSeconds: 6, capturedAt: when)
        let card = NoteAttachment.card(entry)
        XCTAssertEqual(card.title, when.formatted(.dateTime.day().month(.abbreviated).year()))
        XCTAssertNotEqual(card.title, "Video")
        XCTAssertTrue(card.subtitle.hasPrefix("Video · 0:06"), card.subtitle)
        XCTAssertEqual(entry.name, "Video", "the stored name is unchanged")
    }

    func testANamedShareKeepsItsName() {
        let entry = NoteAttachment.keptMovieEntry(filename: VideoKeep.filename(memoID: UUID(), sourceExtension: "mov"),
                                                  originalName: "kiln test.mov", byteCount: 5, durationSeconds: 6,
                                                  capturedAt: Date())
        XCTAssertEqual(NoteAttachment.card(entry).title, "kiln test.mov")
    }

    func testAnEntryWithNoDateStillReadsVideo() {
        let entry = NoteAttachment.keptMovieEntry(filename: VideoKeep.filename(memoID: UUID(), sourceExtension: "mov"),
                                                  originalName: "Video", byteCount: 5, durationSeconds: 6)
        XCTAssertEqual(NoteAttachment.card(entry).title, "Video")
        // An older synced entry (no date key) decodes.
        let json = #"{"kind":"video","filename":"video_x.mov","name":"Video","uti":"com.apple.quicktime-movie","byteCount":1}"#
        XCTAssertNoThrow(try JSONDecoder().decode(NoteAttachmentEntry.self, from: Data(json.utf8)))
    }
}
