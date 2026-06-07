import XCTest
import Foundation

final class CompilerTests: XCTestCase {

    private func makeFile() -> PipelineFile {
        PipelineFile(id: "1", filename: "memo.m4a", path: "/tmp/x", size: 0, sourceType: .audio)
    }

    func testFrontmatterAndBodyPrecedence() {
        let pf = makeFile()
        pf.transcript = "raw transcript"
        pf.enhancedCopyedit = "clean copy"
        pf.sanitised = "linked [[Nick Jansen]] copy"
        pf.enhancedTitle = "My Title"
        pf.enhancedSummary = "A short summary."
        pf.tags = ["work", "ideas"]
        pf.significance = 0.7

        let md = Compiler.compile(file: pf, author: "Tiuri", date: "2026-06-06")
        XCTAssertTrue(md.contains("title: My Title"))
        XCTAssertTrue(md.contains("date: 2026-06-06"))
        XCTAssertTrue(md.contains("author: Tiuri"))
        XCTAssertTrue(md.contains("source: Voice-memo"))
        XCTAssertTrue(md.contains("significance: 0.7"))
        XCTAssertTrue(md.contains("summary: A short summary."))
        XCTAssertTrue(md.contains("- work"))
        XCTAssertTrue(md.contains("- ideas"))
        XCTAssertTrue(md.hasSuffix("linked [[Nick Jansen]] copy"))   // sanitised wins
    }

    func testBodyFallsBackToCopyedit() {
        let pf = makeFile()
        pf.transcript = "raw"
        pf.enhancedCopyedit = "edited body"
        let md = Compiler.compile(file: pf, author: "T", date: "2026-01-01")
        XCTAssertTrue(md.hasSuffix("edited body"))
    }

    func testPhoneMetadataFrontmatter() {
        let pf = makeFile()
        pf.transcript = "hi"
        pf.audioMetadataJSON = Data(#"{"location":{"placeName":"Amsterdam"},"weather":{"conditions":"Cloudy","temperature":12,"temperatureUnit":"°C"},"steps":4200,"recordedAt":"2026-06-05T08:00:00.000Z"}"#.utf8)
        let md = Compiler.compile(file: pf, author: "T")   // date from recordedAt
        XCTAssertTrue(md.contains("location: \"Amsterdam\""))
        XCTAssertTrue(md.contains("weather: \"Cloudy, 12°C\""))   // 12 not 12.0
        XCTAssertTrue(md.contains("steps: 4200"))
        XCTAssertTrue(md.contains("date: 2026-06-05"))
    }

    func testSignificanceRoundsToOneDecimal() {
        let pf = makeFile()
        pf.transcript = "body"
        pf.significance = 0.7000000000000001   // float noise the slider produced (E3)
        let md = Compiler.compile(file: pf, author: "T", date: "2026-01-01")
        XCTAssertTrue(md.contains("significance: 0.7"), "rounded to one decimal")
        XCTAssertFalse(md.contains("0.70000"), "no float-noise decimals in YAML")
    }

    func testEmptySignificanceAndSummaryAreBareKeys() {
        let pf = makeFile()
        pf.transcript = "body"
        let md = Compiler.compile(file: pf, author: "T", date: "2026-01-01")
        XCTAssertTrue(md.contains("\nsignificance:\n"))
        XCTAssertTrue(md.contains("\nsummary:\n"))
    }
}
