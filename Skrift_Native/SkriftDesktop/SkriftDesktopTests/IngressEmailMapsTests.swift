import XCTest

/// Q441: the email, selected-text and Maps cases of `IngressDispatchTests` (C142 C144 C123),
/// against the fixtures `ingress/email`, `ingress/selected-text`, `ingress/maps-link`. The
/// every-door table in `IngressDispatchTests.swift` checks their plans; these check the rules.
extension IngressDispatchTests {

    private static var q441Root: URL {
        CorpusSeed.fixtureRoot(file: #filePath).appendingPathComponent("ingress", isDirectory: true)
    }

    private struct Q441Manifest: Decodable { var items: [IngressDispatch.Item] }

    private func q441Outcome(_ door: String) throws -> IngressDispatch.Outcome {
        let url = Self.q441Root.appendingPathComponent(door).appendingPathComponent("providers.json")
        return IngressDispatch.dispatch(try JSONDecoder().decode(Q441Manifest.self, from: Data(contentsOf: url)).items)
    }

    private func q441Eml() throws -> Data {
        try Data(contentsOf: Self.q441Root.appendingPathComponent("email/message.eml"))
    }

    private func iso(_ s: String) -> Date? { ISO8601DateFormatter().date(from: s) }

    // MARK: C142 - email

    /// A shared .eml is a document to the dispatcher (never a link or a picture), flagged as an email.
    func testEmailShareIsAnEmailDocument() throws {
        guard case .plan(let plan) = try q441Outcome("email") else { return XCTFail("refused") }
        XCTAssertEqual(plan.kind, .document)
        XCTAssertEqual(plan.emailFile, "Kiln firing schedule.eml")
        XCTAssertNil(plan.bookFile)
        // The Mac drop of the same file: named by file name only.
        let drop = IngestService.dispatchPlan(for: URL(fileURLWithPath: "/tmp/Kiln firing schedule.eml"))
        XCTAssertEqual(drop?.emailFile, "Kiln firing schedule.eml")
    }

    /// Subject = title, plain text = body (QP + soft breaks decoded, the HTML copy ignored),
    /// Date header = recordedAt, From = sender, attachment kept as a file.
    func testEmailBecomesATextCapture() throws {
        let mail = try XCTUnwrap(EmailShare.parse(try q441Eml()))
        XCTAssertEqual(mail.subject, "Kiln firing schedule \u{2014} this week")
        XCTAssertEqual(mail.senderName, "Ana Concei\u{00e7}\u{00e3}o")
        XCTAssertEqual(mail.senderAddress, "ana.conceicao@example.org")
        XCTAssertEqual(mail.date, iso("2024-10-08T08:15:30Z"))
        XCTAssertTrue(mail.body.hasPrefix("Hi Tuur,"), mail.body)
        XCTAssertTrue(mail.body.contains("Friday (glaze). Caf\u{00e9} after the unloading, my treat."), mail.body)
        XCTAssertTrue(mail.body.hasSuffix("Ana"), mail.body)
        XCTAssertFalse(mail.body.contains("HTML copy"))
        XCTAssertEqual(mail.attachments.count, 1)
        XCTAssertEqual(mail.attachments.first?.name, "schedule.txt")
        XCTAssertEqual(mail.attachments.first?.mimeType, "text/plain")
        XCTAssertEqual(mail.attachments.first.flatMap { String(data: $0.data, encoding: .utf8) },
                       "Kiln schedule for the week: Tuesday bisque, Friday glaze.\n")
    }

    /// Mail files from real clients use CRLF; the same message reads the same.
    func testEmailReadsTheSameWithCRLF() throws {
        let lf = try XCTUnwrap(String(data: try q441Eml(), encoding: .utf8))
        let crlf = Data(lf.replacingOccurrences(of: "\n", with: "\r\n").utf8)
        let a = try XCTUnwrap(EmailShare.parse(try q441Eml())), b = try XCTUnwrap(EmailShare.parse(crlf))
        XCTAssertEqual(a.subject, b.subject)
        XCTAssertEqual(a.date, b.date)
        XCTAssertEqual(a.body, b.body)
        XCTAssertEqual(a.attachments, b.attachments)
    }

    /// HTML-only mail reduces to its text; a missing Date leaves recordedAt to the share moment;
    /// a bare address is its own sender name; a latin-1 body is decoded.
    func testEmailEdgeCases() throws {
        let html = "From: ana@example.org\nSubject: Hello\nContent-Type: text/html; charset=iso-8859-1\n"
            + "Content-Transfer-Encoding: quoted-printable\n\n"
            + "<html><head><style>p{}</style></head><body><p>Caf=E9 at nine</p><p>Bring &amp; share</p></body></html>\n"
        let mail = try XCTUnwrap(EmailShare.parse(Data(html.utf8)))
        XCTAssertEqual(mail.body, "Caf\u{00e9} at nine\nBring & share")
        XCTAssertNil(mail.date)
        XCTAssertEqual(mail.senderName, "ana")
        XCTAssertEqual(mail.senderAddress, "ana@example.org")

        // Folded Subject, unknown-date format with a comment.
        let folded = "Subject: A long subject\n that wraps\nDate: Wed, 9 Oct 2024 18:00:00 +0000 (UTC)\n\nBody\n"
        let f = try XCTUnwrap(EmailShare.parse(Data(folded.utf8)))
        XCTAssertEqual(f.subject, "A long subject that wraps")
        XCTAssertEqual(f.date, iso("2024-10-09T18:00:00Z"))

        // A plain text file renamed .eml has no headers: nothing to read, not an empty note.
        XCTAssertNil(EmailShare.parse(Data("just some words, no headers at all".utf8)))
        XCTAssertNil(EmailShare.parse(Data()))
        XCTAssertTrue(EmailShare.isEmailFile("Mail.EML"))
        XCTAssertFalse(EmailShare.isEmailFile("notes.txt"))
    }

    // MARK: C144 - selected text and Maps

    /// A selected quote with its page: a text capture carrying the URL and the title. No fetch:
    /// the plan is pure data and holds a sentence with a link inside as text.
    func testSelectedTextCarriesItsPage() throws {
        guard case .plan(let plan) = try q441Outcome("selected-text") else { return XCTFail("refused") }
        XCTAssertEqual(plan.kind, .text)
        XCTAssertEqual(plan.url, "https://example.org/slow-ceramics/glaze-faults")
        XCTAssertEqual(plan.title, "Slow ceramics: why glaze fails")
        XCTAssertEqual(plan.texts.count, 1)
        XCTAssertNil(plan.place)
    }

    /// An Apple Maps share: a link capture; the place is its location and its title.
    func testMapsLinkIsAPlaceAnchoredLinkCapture() throws {
        guard case .plan(let plan) = try q441Outcome("maps-link") else { return XCTFail("refused") }
        XCTAssertEqual(plan.kind, .url)
        XCTAssertEqual(plan.title, "Pastelaria Aloma")
        let place = try XCTUnwrap(plan.place)
        XCTAssertEqual(place.name, "Pastelaria Aloma")
        XCTAssertEqual(place.latitude, 38.7107, accuracy: 0.00001)
        XCTAssertEqual(place.longitude, -9.1426, accuracy: 0.00001)
    }

    /// Google Maps works the same; a page title from the share beats the place name; a short link
    /// is opaque without a fetch and stays a plain link capture (no place, no title).
    func testGoogleAndShortMapsLinks() {
        func plan(_ url: String, title: String? = nil) -> IngressDispatch.Plan? {
            guard case .plan(let p) = IngressDispatch.dispatch(
                [.init(providers: [.init(uti: ["public.url"], url: url)], title: title)]) else { return nil }
            return p
        }
        let g = plan("https://www.google.com/maps/place/Time+Out+Market/@38.7071,-9.1458,17z")
        XCTAssertEqual(g?.kind, .url)
        XCTAssertEqual(g?.title, "Time Out Market")
        XCTAssertEqual(g?.place?.latitude ?? 0, 38.7071, accuracy: 0.00001)

        XCTAssertEqual(plan("https://maps.apple.com/?ll=38.7,-9.1&q=Aloma", title: "Aloma on Apple Maps")?.title,
                       "Aloma on Apple Maps")

        let short = plan("https://maps.app.goo.gl/AbCdEf123")
        XCTAssertEqual(short?.kind, .url)
        XCTAssertNil(short?.place)
        XCTAssertNil(short?.title)
    }
}
