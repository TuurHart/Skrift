import XCTest
@testable import SkriftMobile

/// The enroll wiring (embed a clip → store the voiceprint on the person). The audio
/// extraction + real wespeaker are device-only; this verifies the deterministic
/// embed→store step with a seeded embedder + a synthetic clip, incl. the alias-safety
/// that makes naming-a-speaker safe after the Mac has set up a person.
final class VoiceEnrollerTests: XCTestCase {
    private func tempStore() -> NamesStore {
        NamesStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("names_\(UUID().uuidString).json"))
    }
    private func clip(_ n: Int, phase: Double = 0) -> [Float] { (0..<n).map { Float(sin((Double($0) + phase) * 0.01)) } }

    func testEnrollStoresVoiceprintOnNewPerson() async {
        let store = tempStore()
        let ok = await VoiceEnroller.enroll(name: "Tiuri", clip: clip(40_000), using: SeededEmbedder(), into: store)
        XCTAssertTrue(ok)
        let tiuri = store.livePeople().first { $0.displayName == "Tiuri" }
        XCTAssertEqual(tiuri?.canonical, "[[Tiuri]]")
        XCTAssertEqual(tiuri?.voiceEmbeddings?.count, 1)
        XCTAssertEqual(tiuri?.voiceEmbeddings?.first?.condition, "conversation")
        XCTAssertEqual(tiuri?.voiceEmbeddings?.first?.vector.count, 256)
    }

    /// Too little audio (<2s) → no embedding stored (the transcript label still sticks).
    func testEnrollRejectsShortClip() async {
        let store = tempStore()
        let ok = await VoiceEnroller.enroll(name: "Tiuri", clip: clip(1_000), using: SeededEmbedder(), into: store)
        XCTAssertFalse(ok)
        XCTAssertTrue(store.livePeople().isEmpty)
    }

    /// Naming a speaker who already exists (e.g. set up + aliased on the Mac, then synced)
    /// must APPEND the voiceprint without wiping aliases/short — addVoiceEmbedding, not upsert.
    func testEnrollPreservesExistingAliases() async {
        let store = tempStore()
        _ = store.save(NamesData(lastModifiedAt: "2026-06-01T00:00:00.000Z", people: [
            Person(canonical: "[[Tiuri Hartog]]", aliases: ["Tuur"], short: "Tiuri",
                   lastModifiedAt: "2026-06-01T00:00:00.000Z")
        ]))
        let ok = await VoiceEnroller.enroll(name: "Tiuri Hartog", clip: clip(40_000), using: SeededEmbedder(), into: store)
        XCTAssertTrue(ok)
        let p = store.livePeople().first { $0.displayName == "Tiuri Hartog" }
        XCTAssertEqual(p?.aliases, ["Tuur"], "aliases must survive enrollment")
        XCTAssertEqual(p?.short, "Tiuri")
        XCTAssertEqual(p?.voiceEmbeddings?.count, 1)
    }

    /// A second enrollment of the same person adds a second voiceprint (multi-embedding,
    /// never averaged) — but an identical vector de-dups.
    func testSecondEnrollmentUnions() async {
        let store = tempStore()
        await VoiceEnroller.enroll(name: "Tiuri", clip: clip(40_000, phase: 0), using: SeededEmbedder(), into: store)
        await VoiceEnroller.enroll(name: "Tiuri", clip: clip(40_000, phase: 5000), using: SeededEmbedder(), into: store)
        let tiuri = store.livePeople().first { $0.displayName == "Tiuri" }
        // SeededEmbedder is deterministic from the clip's leading fingerprint; the
        // phase-shifted clip yields a different vector → two embeddings.
        XCTAssertEqual(tiuri?.voiceEmbeddings?.count, 2)
    }
}
