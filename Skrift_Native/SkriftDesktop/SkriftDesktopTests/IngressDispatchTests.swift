import XCTest

/// Q438: the ONE share / drop dispatcher (`Shared/Ingress/IngressDispatch.swift`) against the
/// ingress fixtures in `test-fixtures/corpus/ingress/<door>/` — `providers.json` (the extension
/// items and providers as the caller resolved them) in, `expect.json` (the plan or the refusal)
/// out. C238 C198 C67 C69 C75 C125 C141, R4 R22.
final class IngressDispatchTests: XCTestCase {

    private struct Manifest: Decodable {
        var door: String
        var items: [IngressDispatch.Item]
    }

    /// `expect.json`: either `{"refuse": …}` or the plan's fields, parts as one-key objects.
    private struct Expect: Decodable {
        var refuse: String?
        var kind: String?
        var parts: [[String: String]]?
        var file: String?
        var url: String?
        var title: String?
    }

    private static var ingressRoot: URL {
        CorpusSeed.fixtureRoot(file: #filePath).appendingPathComponent("ingress", isDirectory: true)
    }

    private static func doors() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: ingressRoot, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func part(_ dict: [String: String]) -> IngressDispatch.Part? {
        guard dict.count == 1, let first = dict.first else { return nil }
        let value = first.value
        switch first.key {
        case "clip": return .clip(value)
        case "picture": return .picture(value)
        case "text": return .text(value)
        default: return nil
        }
    }

    private func outcome(_ door: String) throws -> IngressDispatch.Outcome {
        let dir = Self.ingressRoot.appendingPathComponent(door, isDirectory: true)
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: dir.appendingPathComponent("providers.json")))
        return IngressDispatch.dispatch(manifest.items)
    }

    // MARK: Every fixture door

    func testEveryDoorMatchesItsExpectation() throws {
        let doors = try Self.doors()
        XCTAssertGreaterThanOrEqual(doors.count, 6, "ingress fixtures missing under \(Self.ingressRoot.path)")
        for dir in doors {
            let door = dir.lastPathComponent
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: dir.appendingPathComponent("providers.json")))
            XCTAssertEqual(manifest.door, door, "manifest door name")
            let expect = try JSONDecoder().decode(Expect.self, from: Data(contentsOf: dir.appendingPathComponent("expect.json")))
            let got = IngressDispatch.dispatch(manifest.items)

            if let refusal = expect.refuse {
                XCTAssertEqual(got, .refuse(refusal), door)
                continue
            }
            let parts = (expect.parts ?? []).map(Self.part)
            XCTAssertFalse(parts.contains { $0 == nil }, "\(door): bad part in expect.json")
            guard let kindRaw = expect.kind, let kind = IngressDispatch.Kind(rawValue: kindRaw) else {
                return XCTFail("\(door): expect.json has no valid kind")
            }
            let want = IngressDispatch.Plan(kind: kind, parts: parts.compactMap { $0 },
                                            file: expect.file, url: expect.url, title: expect.title)
            XCTAssertEqual(got, .plan(want), door)
        }
    }

    // MARK: The clauses, one by one

    /// C67 / R4: a 3-item WhatsApp share → 3 clips, in chat order.
    func testWhatsAppThreeItemsGiveThreeClips() throws {
        guard case .plan(let plan) = try outcome("whatsapp-3-items") else { return XCTFail("refused") }
        XCTAssertEqual(plan.kind, .audio)
        XCTAssertEqual(plan.clips, ["PTT-20241003-WA0007.opus", "PTT-20241003-WA0008.opus", "PTT-20241003-WA0009.m4a"])
        XCTAssertNil(plan.url, "audio outranks the URL representation (C69)")
    }

    /// C67 / C69: 4 Signal providers on an odd UTI → 4 clips, rerouted by `.aac`.
    func testSignalFourProvidersGiveFourClips() throws {
        guard case .plan(let plan) = try outcome("signal-4-providers") else { return XCTFail("refused") }
        XCTAssertEqual(plan.kind, .audio)
        XCTAssertEqual(plan.clips.count, 4)
    }

    /// C125 / R22: 2 texts among clips and a picture keep their order; none dropped.
    func testTwoTextsKeepTheirPlaceAmongClipsAndPicture() throws {
        guard case .plan(let plan) = try outcome("texts-among-clips") else { return XCTFail("refused") }
        XCTAssertEqual(plan.texts, ["Meet at the station at nine.", "Bring the blue folder."])
        XCTAssertEqual(plan.parts.map { if case .text = $0 { return "t" } else if case .clip = $0 { return "c" } else { return "p" } },
                       ["c", "t", "p", "c", "t"])
    }

    /// C69 / D16: a text that is only a web link is a link capture.
    func testURLAsTextIsALinkCapture() throws {
        XCTAssertEqual(try outcome("url-as-text"),
                       .plan(.init(kind: .url, parts: [], url: "https://example.com/article/42")))
        XCTAssertNil(IngressDispatch.webLink("see https://example.com later"), "a sentence with a link stays text")
        XCTAssertNil(IngressDispatch.webLink("file:///tmp/a.pdf"))
    }

    /// C141 / R22: a photo's caption is kept as the annotation.
    func testPhotoCaptionIsKept() throws {
        guard case .plan(let plan) = try outcome("photo-with-caption") else { return XCTFail("refused") }
        XCTAssertEqual(plan.kind, .image)
        XCTAssertEqual(plan.pictures, ["IMG-20241006-WA0011.jpg"])
        XCTAssertEqual(plan.texts, ["The view from the bridge"])
    }

    /// C75: an empty payload refuses honestly; no items at all refuses too.
    func testEmptyPayloadRefuses() throws {
        XCTAssertEqual(try outcome("empty-payload"), .refuse("Skrift can't import this"))
        XCTAssertEqual(IngressDispatch.dispatch([]), .refuse(IngressDispatch.refusal))
    }

    /// C198: text beats URL, the URL and page title ride along.
    func testSelectedTextBeatsURL() throws {
        guard case .plan(let plan) = try outcome("safari-selected-text") else { return XCTFail("refused") }
        XCTAssertEqual(plan.kind, .text)
        XCTAssertEqual(plan.url, "https://example.org/rivers")
        XCTAssertEqual(plan.title, "How rivers carve canyons")
    }

    /// C198 order: movie before image, a PDF is a document, a file URL is never a web link.
    func testDispatchOrderMovieImageDocument() {
        let movieAndPhoto = [IngressDispatch.Item(providers: [
            .init(uti: ["public.jpeg"], file: "poster.jpg"),
            .init(uti: ["com.apple.quicktime-movie"], file: "clip.mov"),
        ])]
        XCTAssertEqual(IngressDispatch.dispatch(movieAndPhoto), .plan(.init(kind: .movie, parts: [], file: "clip.mov")))

        let pdf = [IngressDispatch.Item(providers: [.init(uti: ["public.file-url", "com.adobe.pdf"], file: "paper.pdf",
                                                         url: "file:///tmp/paper.pdf")])]
        XCTAssertEqual(IngressDispatch.dispatch(pdf), .plan(.init(kind: .document, parts: [], file: "paper.pdf")))

        let telegram = [IngressDispatch.Item(providers: [.init(uti: ["public.data"], file: "voice_1.ogg")])]
        XCTAssertEqual(IngressDispatch.dispatch(telegram), .plan(.init(kind: .audio, parts: [.clip("voice_1.ogg")])))
    }
}
