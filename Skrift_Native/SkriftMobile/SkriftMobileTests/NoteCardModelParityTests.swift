import XCTest
import Foundation
@testable import SkriftMobile

/// Q106 (C115/C240/C172/C78): the phone half of the card-model parity pair. The SAME class
/// name and the SAME golden table live in the desktop suite, which proves the Mac's rated
/// (`PipelineFile.cardFacts`) and quiet (`Memo.cardFacts`) adapters against it. Here the real
/// `MemoCard.cardModel` (what the phone list draws) must produce that golden content for one
/// synthetic note of each kind: phone == golden == Mac.
@MainActor
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

    private func content(of model: NoteCardModel) -> NoteCardContent {
        NoteCardContent(title: model.title, quote: model.quote, snippet: model.snippet, chips: model.chips)
    }

    /// The phone's real list card (`MemoCard.cardModel`) for every kind equals the golden.
    func testPhoneCardModelYieldsTheGoldenContentForEveryKind() {
        for name in Self.names {
            let model = MemoCard(memo: note(name)).cardModel
            XCTAssertEqual(content(of: model), golden(name), "phone MemoCard, \(name)")
        }
    }

    /// The Memo adapter the Mac's quiet rows share is the phone's builder input.
    func testMemoAdapterMatchesTheGoldenToo() {
        for name in Self.names {
            XCTAssertEqual(NoteCardBuilder.content(for: note(name).cardFacts()), golden(name), name)
        }
    }

    /// The phone's detail-side helpers delegate to the shared builder (no twin of the rule).
    func testPhoneDisplayHelpersAgreeWithTheBuilder() {
        let book = note("book")
        XCTAssertEqual(book.quoteSnippet, "Focus is a skill. Train it.")
        XCTAssertEqual(book.bookCaptionLabel, "Deep Work · ch. 4")
        XCTAssertEqual(note("link").shareCaptureTitle, "A Post")
        XCTAssertEqual(note("link").shareCaptureURLDomain, "example.com")
    }

    /// Chrome stays the adapter's: a locked row shows the placeholder title and nothing else.
    func testLockedPhoneRowShowsOnlyTheTitle() {
        let memo = note("voice")
        memo.locked = true
        let model = MemoCard(memo: memo).cardModel
        XCTAssertTrue(model.locked)
        XCTAssertTrue(model.chips.isEmpty)
        XCTAssertNil(model.snippet)
    }
}

