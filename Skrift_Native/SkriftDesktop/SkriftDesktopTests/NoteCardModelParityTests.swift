import XCTest
import Foundation

/// Q106 (C115/C240/C172/C78): ONE card-content builder (`NoteCardBuilder`) feeds the phone's
/// `MemoCard` and both Mac row kinds. One synthetic note of each kind (voice, video, book
/// quote, link, text, image, PDF, typed) must yield the SAME `NoteCardContent` from
///   - the Mac RATED adapter  (`PipelineFile.cardFacts`, the row the pipeline ingests), and
///   - the Memo adapter       (`Memo.cardFacts`: the Mac's quiet rows AND the phone's rows),
/// and both must equal the golden table below. The same class name and the same golden table
/// live in the phone suite (`plan/mtest.sh NoteCardModelParityTests`), which drives the real
/// `MemoCard.cardModel`; so phone == Memo adapter == Mac rated adapter == golden.
final class NoteCardModelParityTests: XCTestCase {

    // MARK: corpus

    private func meta(_ m: MemoMetadata) -> Data { try! JSONEncoder().encode(m) }
    private func shared(_ s: SharedContent) -> Data { try! JSONEncoder().encode(s) }

    private func note(_ name: String) -> Memo {
        switch name {
        case "voice":
            return Memo(audioFilename: "a.m4a", duration: 83, tags: ["daily"],
                        transcript: "Walked past the bakery.\n\nThen home.",
                        metadataData: meta(MemoMetadata(
                            location: LocationInfo(latitude: 38.7, longitude: -9.1, placeName: "Lisbon"),
                            weather: WeatherInfo(conditions: "Clear", temperature: 18, temperatureUnit: "C"))))
        case "video":
            return Memo(audioFilename: "v.m4a", duration: 125, title: "Standup",
                        transcript: "[[img_001]] Planning the week\nsecond line",
                        metadataData: meta(MemoMetadata(sourceType: MemoMetadata.Source.video)))
        case "book":
            return Memo(audioFilename: "b.m4a", duration: 40,
                        transcript: "> Focus is a skill.\n> Train it.\n\nMy take: yes",
                        metadataData: meta(MemoMetadata(bookTitle: "Deep Work", bookChapter: "4")))
        case "link":
            return Memo(sharedContentData: shared(SharedContent(
                type: .url, url: "https://www.example.com/post", urlTitle: "A Post")))
        case "text":
            return Memo(sharedContentData: shared(SharedContent(
                type: .text, text: "Remember to call the notary tomorrow morning")),
                        annotationText: "Do it first thing")
        case "image":
            return Memo(sharedContentData: shared(SharedContent(type: .image)),
                        annotationText: "Whiteboard from the meeting")
        case "pdf":
            return Memo(sharedContentData: shared(SharedContent(type: .file, fileName: "Report.pdf")))
        case "typed":
            return Memo(transcript: "Buy milk",
                        metadataData: try! JSONSerialization.data(withJSONObject: ["mediaSource": "typed"]))
        default:
            fatalError("unknown corpus note \(name)")
        }
    }

    private static let names = ["voice", "video", "book", "link", "text", "image", "pdf", "typed"]

    /// The Mac's rated row exactly as ingest builds it: the projection's field mapping, with a
    /// capture's annotation stored as its transcript (`UploadService.prepare`).
    private func ratedRow(for memo: Memo) -> PipelineFile {
        let pf = MemoNoteProjection.file(for: memo)
        if pf.sourceType == .capture { pf.transcript = memo.annotationText }
        return pf
    }

    // MARK: golden

    private typealias Chip = NoteCardModel.Chip

    private func golden(_ name: String) -> NoteCardContent {
        switch name {
        case "voice":
            return .init(title: nil, quote: nil, snippet: "Walked past the bakery.\nThen home.", chips: [
                Chip(text: "1:23"),
                Chip(text: "Lisbon", systemImage: "mappin.circle.fill"),
                Chip(text: "18°", systemImage: "cloud.sun.fill"),
                Chip(text: "#daily", isTag: true)])
        case "video":
            return .init(title: "Standup", quote: nil, snippet: "Planning the week", chips: [
                Chip(text: "Video", systemImage: "video.fill"),
                Chip(text: "2:05")])
        case "book":
            return .init(title: nil, quote: "Focus is a skill. Train it.", snippet: "My take: yes", chips: [
                Chip(text: "Deep Work · ch. 4", systemImage: "book.closed.fill"),
                Chip(text: "0:40")])
        case "link":
            return .init(title: "A Post", quote: nil, snippet: "example.com", chips: [
                Chip(text: "Link", systemImage: "link"),
                Chip(text: "example.com")])
        case "text":
            return .init(title: "Remember to call the notary tomorrow morning", quote: nil,
                         snippet: "Do it first thing", chips: [
                Chip(text: "Text", systemImage: "text.quote")])
        case "image":
            return .init(title: "Whiteboard from the meeting", quote: nil,
                         snippet: "Whiteboard from the meeting", chips: [
                Chip(text: "Image", systemImage: "photo")])
        case "pdf":
            return .init(title: "Report.pdf", quote: nil, snippet: nil, chips: [
                Chip(text: "File", systemImage: "doc")])
        case "typed":
            return .init(title: nil, quote: nil, snippet: "Buy milk", chips: [
                Chip(text: "Note", systemImage: "square.and.pencil")])
        default:
            fatalError("no golden for \(name)")
        }
    }

    // MARK: tests

    func testMacRatedRowYieldsTheGoldenContentForEveryKind() {
        for name in Self.names {
            let content = NoteCardBuilder.content(for: ratedRow(for: note(name)).cardFacts)
            XCTAssertEqual(content, golden(name), "Mac rated row, \(name)")
        }
    }

    func testMemoAdapterYieldsTheGoldenContentForEveryKind() {
        for name in Self.names {
            let content = NoteCardBuilder.content(for: note(name).cardFacts())
            XCTAssertEqual(content, golden(name), "Memo adapter (phone + Mac quiet row), \(name)")
        }
    }

    func testBothAdaptersAgreeOnTheFacts() {
        for name in Self.names {
            let memo = note(name)
            let fromMemo = memo.cardFacts()
            let fromRow = ratedRow(for: memo).cardFacts
            XCTAssertEqual(fromRow.kind, fromMemo.kind, "kind, \(name)")
            XCTAssertEqual(fromRow.book, fromMemo.book, "book, \(name)")
            XCTAssertEqual(fromRow.shared, fromMemo.shared, "shared, \(name)")
        }
    }

    /// The audit's two `.audio`-row blind spots: a book capture and a video import must carry
    /// their source on the Mac row (list-sidebar-64/68, capture-source-05, books-103).
    func testBookCaptureAndVideoKeepTheirSourceOnAnAudioRow() {
        let book = ratedRow(for: note("book"))
        XCTAssertEqual(book.sourceType, .audio)
        XCTAssertEqual(book.sourceKind, .audiobookQuote)
        let bookCard = NoteCardBuilder.content(for: book.cardFacts)
        XCTAssertEqual(bookCard.quote, "Focus is a skill. Train it.")
        XCTAssertTrue(bookCard.chips.contains { $0.text == "Deep Work · ch. 4" })

        let video = ratedRow(for: note("video"))
        XCTAssertEqual(video.sourceType, .audio)
        XCTAssertEqual(video.sourceKind, .video)
        XCTAssertEqual(NoteCardBuilder.content(for: video.cardFacts).chips.first?.text, "Video")
    }

    /// A titled row shows ONE clipped line of body (the phone rule), not the whole body.
    func testTitledRowSnippetIsOneLine() {
        let facts = NoteCardFacts(kind: .voiceMemo, title: "Plan", body: "First line.\nSecond line.\nThird.")
        let c = NoteCardBuilder.content(for: facts)
        XCTAssertEqual(c.title, "Plan")
        XCTAssertEqual(c.snippet, "First line.")
    }

    /// A title chosen on a capture (or the Mac's generated one) beats the capture-derived title
    /// (capture-source-13: the phone list used to ignore it).
    func testCaptureTitleHonoursAChosenTitle() {
        let sc = SharedContent(type: .url, url: "https://example.com", urlTitle: "Page")
        XCTAssertEqual(NoteCardBuilder.content(for: NoteCardFacts(kind: .captureURL, title: "Mine", shared: sc)).title, "Mine")
        XCTAssertEqual(NoteCardBuilder.content(for: NoteCardFacts(kind: .captureURL, generatedTitle: "Generated", shared: sc)).title, "Generated")
        XCTAssertEqual(NoteCardBuilder.content(for: NoteCardFacts(kind: .captureURL, shared: sc)).title, "Page")
    }

    /// An untitled note with nothing readable falls to the taxonomy word, in the snippet slot.
    func testEmptyUntitledRowFallsToTheTaxonomyWord() {
        XCTAssertEqual(NoteCardBuilder.content(for: NoteCardFacts(kind: .voiceMemo, body: "[[img_001]]")).snippet, "Voice note")
        XCTAssertEqual(NoteCardBuilder.content(for: NoteCardFacts(kind: .typedNote)).snippet, "Note")
    }
}
