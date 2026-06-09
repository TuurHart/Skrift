import XCTest
import Foundation

/// Voice-identity sync contract (CONVERSATION_MODE_HANDOFF §4–§5.4): a voiceprint
/// enrolled on the PHONE and a voiceprint enrolled on the MAC for the *same* person
/// must BOTH survive the bidirectional last-write-wins sync — `voiceEmbeddings` are
/// ADDITIVE, never clobbered, even when the other side's scalar fields (aliases /
/// short) are newer. This drives the real contract types end-to-end:
///   phone sync flow (GET /meta → GET → `NamesMerge` LWW merge → PUT)
///     ⇄ Mac `SyncHandlers` (the actual server router + serialization)
///     ⇄ `NamesStore` (the Mac's source-of-truth file) + `NamesMerge` (union math).
///
/// If a future change averages/dedupes/overwrites embeddings or drops the union on
/// the winning side, this test fails — and the phone↔Mac voice sync silently regresses.
///
/// Host-less + MLX-free: no FluidAudio, no network, no UI — runs under the UnitTests
/// scheme. The "wire" is the Mac's own `SyncHandlers` called in-process, so the
/// PUT/GET bytes are exactly what the socket carries. The phone half is modelled by
/// `PhoneSyncClient` below, which replays the EXACT sequence of `NamesSync.run()` from
/// `SkriftMobile/Services/NamesSync.swift` (that type lives only in the mobile target;
/// `NamesData`/`NamesMerge` are duplicated verbatim across both apps, so the merge math
/// here is byte-identical to the phone's).
final class NamesSyncRoundTripTests: XCTestCase {

    // MARK: - Phone client (mirrors SkriftMobile NamesSync.run() verbatim)

    /// Outcome flag — mirrors the mobile `SyncResult` cases we assert on.
    private enum SyncOutcome: Equatable { case unchanged, merged, failed }

    /// Replays the phone's `NamesSync.run()` against a Mac `SyncHandlers`:
    ///   GET /meta → (skip if == local) → GET full → `NamesMerge.mergeByCanonical`
    ///   (LWW + voiceEmbeddings UNION) → save locally → PUT merged back.
    /// Using the real `SyncHandlers` means the GET/PUT serialization is the actual
    /// contract bytes, not a stub.
    private struct PhoneSyncClient {
        let store: NamesStore          // the phone's local source of truth
        let mac: SyncHandlers          // the Mac server (the "wire")

        @discardableResult
        func run() -> SyncOutcome {
            let local = store.load()

            // GET /api/names/meta
            let metaResp = mac.handle(req(.GET, "/api/names/meta"))
            guard metaResp.status == 200,
                  let metaObj = try? JSONSerialization.jsonObject(with: metaResp.body) as? [String: Any]
            else { return .failed }
            let remoteMeta = metaObj["lastModifiedAt"] as? String
            if let remoteMeta, remoteMeta == local.lastModifiedAt { return .unchanged }

            // GET /api/names
            let getResp = mac.handle(req(.GET, "/api/names"))
            guard getResp.status == 200,
                  let remote = try? JSONDecoder().decode(NamesData.self, from: getResp.body)
            else { return .failed }

            // LWW merge (+ voiceEmbeddings union) — identical to the phone.
            let merged = NamesMerge.mergeByCanonical(local: local.people, remote: remote.people)
            let saved = store.save(NamesData(lastModifiedAt: ISO8601.now(), people: merged))

            // PUT /api/names (merged back so the Mac converges too).
            guard let body = try? JSONEncoder().encode(saved),
                  mac.handle(req(.PUT, "/api/names", body: body)).status == 200
            else { return .failed }

            return .merged
        }

        private func req(_ m: HTTPMethod, _ path: String, body: Data = Data()) -> HTTPRequest {
            HTTPRequest(method: m, path: path, query: [:], headers: [:], body: body)
        }
    }

    // MARK: - Fixtures

    private func tempNamesURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("names_roundtrip_\(UUID().uuidString).json")
    }

    /// A distinct, non-empty embedding so union-by-vector keeps both.
    private func embedding(_ vector: [Double], condition: String) -> VoiceEmbedding {
        VoiceEmbedding(vector: vector, condition: condition, addedAt: ISO8601.now())
    }

    // MARK: - The contract

    /// THE acceptance test: phone-origin + Mac-origin voiceprints for one person both
    /// survive the LWW union — neither device clobbers the other's enrollment — driven
    /// through the genuine phone-sync flow ⇄ `SyncHandlers` ⇄ `NamesStore`/`NamesMerge`.
    func testPhoneAndMacVoiceprintsBothSurviveLWWUnion() throws {
        // ── Mac side: the source-of-truth store already knows this person and has a
        //    MAC-origin voiceprint (enrolled on the Mac via -voiceloop / NoteDisplay).
        //    Its scalar fields (aliases) are the NEWER write, so LWW picks the Mac's
        //    scalars — the phone's embedding must STILL survive via the additive union.
        let macStore = NamesStore(fileURL: tempNamesURL())
        let macVoice = embedding([0.11, 0.22, 0.33], condition: "voiceloop")  // Mac-origin
        _ = macStore.save(NamesData(lastModifiedAt: "2026-06-09T12:00:00.000Z", people: [
            Person(canonical: "[[Tiuri Hartog]]", aliases: ["Tuur", "Tiuri"], short: "Tiuri",
                   voiceEmbeddings: [macVoice],
                   lastModifiedAt: "2026-06-09T12:00:00.000Z")   // newer scalars
        ]))
        let mac = SyncHandlers(namesStore: macStore)

        // ── Phone side: its local store has the SAME person with an OLDER scalar write
        //    plus a freshly-enrolled PHONE-origin voiceprint (conversation naming).
        let phoneStore = NamesStore(fileURL: tempNamesURL())
        let phoneVoice = embedding([0.91, 0.92, 0.93], condition: "conversation")  // phone-origin
        _ = phoneStore.save(NamesData(lastModifiedAt: "2026-06-08T09:00:00.000Z", people: [
            Person(canonical: "[[Tiuri Hartog]]", aliases: ["Tuur"], short: "Tiuri",
                   voiceEmbeddings: [phoneVoice],
                   lastModifiedAt: "2026-06-08T09:00:00.000Z")   // older scalars
        ]))

        // ── Run the phone's real sync: GET /meta → GET → LWW merge → PUT back.
        let result = PhoneSyncClient(store: phoneStore, mac: mac).run()
        XCTAssertEqual(result, .merged)

        // ── PHONE local store now holds BOTH embeddings (union), with the Mac's newer
        //    scalars (aliases) having won LWW.
        let phonePerson = try XCTUnwrap(phoneStore.livePeople()
            .first { $0.displayName == "Tiuri Hartog" })
        XCTAssertEqual(phonePerson.aliases, ["Tuur", "Tiuri"], "Mac's newer scalars win LWW")
        let phoneVectors = Set((phonePerson.voiceEmbeddings ?? []).map(\.vector))
        XCTAssertEqual(phoneVectors, [macVoice.vector, phoneVoice.vector],
                       "phone keeps BOTH the Mac-origin and its own phone-origin voiceprint")

        // ── MAC store ALSO converged to both embeddings — the phone PUT the union back,
        //    so the Mac-origin voiceprint was not lost and the phone's was gained.
        let macPerson = try XCTUnwrap(macStore.livePeople()
            .first { $0.displayName == "Tiuri Hartog" })
        let macVectors = Set((macPerson.voiceEmbeddings ?? []).map(\.vector))
        XCTAssertEqual(macVectors, [macVoice.vector, phoneVoice.vector],
                       "Mac converges to BOTH voiceprints after the phone's PUT")

        // Condition metadata is preserved verbatim through the round-trip (opaque
        // pass-through — the contract carries condition/addedAt untouched).
        let conditions = Set((macPerson.voiceEmbeddings ?? []).compactMap(\.condition))
        XCTAssertEqual(conditions, ["voiceloop", "conversation"])
    }

    /// Symmetric direction: phone enrolls the FIRST voiceprint for a person the Mac
    /// already named (no voice yet). The Mac's scalars are newer; after sync the Mac
    /// gains the phone's voiceprint and keeps its aliases — i.e. a fresh phone
    /// enrollment is delivered to the Mac, not dropped on the floor by the LWW scalar win.
    func testFreshPhoneEnrollmentReachesMacAcrossNewerMacScalarEdit() throws {
        let macStore = NamesStore(fileURL: tempNamesURL())
        _ = macStore.save(NamesData(lastModifiedAt: "2026-06-09T12:00:00.000Z", people: [
            Person(canonical: "[[Roksana Gurova]]", aliases: ["Rox", "Roxy"], short: "Rox",
                   voiceEmbeddings: nil,
                   lastModifiedAt: "2026-06-09T12:00:00.000Z")   // Mac edited the name today; NO voice
        ]))
        let mac = SyncHandlers(namesStore: macStore)

        // Phone: older scalar write, but it just enrolled a voiceprint via conversation naming.
        let phoneStore = NamesStore(fileURL: tempNamesURL())
        let phoneVoice = embedding([0.5, 0.6, 0.7], condition: "conversation")
        _ = phoneStore.save(NamesData(lastModifiedAt: "2026-06-08T08:00:00.000Z", people: [
            Person(canonical: "[[Roksana Gurova]]", aliases: ["Rox"], short: "Rox",
                   voiceEmbeddings: [phoneVoice],
                   lastModifiedAt: "2026-06-08T08:00:00.000Z")
        ]))

        XCTAssertEqual(PhoneSyncClient(store: phoneStore, mac: mac).run(), .merged)

        // The Mac now has the phone's voiceprint AND kept its newer aliases.
        let macPerson = try XCTUnwrap(macStore.livePeople()
            .first { $0.displayName == "Roksana Gurova" })
        XCTAssertEqual(macPerson.aliases, ["Rox", "Roxy"], "Mac's newer aliases survive")
        XCTAssertEqual(macPerson.voiceEmbeddings?.map(\.vector), [phoneVoice.vector],
                       "the phone's fresh enrollment reaches the Mac despite the newer Mac scalar edit")
    }

    /// Idempotence guard: re-running the sync with the same data must NOT duplicate
    /// embeddings (union is de-duped by vector) and must report `.unchanged` once the
    /// top-level timestamps line up — so a manual re-tap of the sync button is a no-op,
    /// not slow embedding-bloat.
    func testReSyncIsIdempotentAndDoesNotDuplicateVoiceprints() throws {
        let macStore = NamesStore(fileURL: tempNamesURL())
        let macVoice = embedding([1, 2, 3], condition: "voiceloop")
        _ = macStore.save(NamesData(lastModifiedAt: "2026-06-09T12:00:00.000Z", people: [
            Person(canonical: "[[Nick]]", aliases: ["Nicky"], short: "Nick",
                   voiceEmbeddings: [macVoice], lastModifiedAt: "2026-06-09T12:00:00.000Z")
        ]))
        let mac = SyncHandlers(namesStore: macStore)

        let phoneStore = NamesStore(fileURL: tempNamesURL())
        let phoneVoice = embedding([4, 5, 6], condition: "conversation")
        _ = phoneStore.save(NamesData(lastModifiedAt: "2026-06-08T08:00:00.000Z", people: [
            Person(canonical: "[[Nick]]", aliases: ["Nicky"], short: "Nick",
                   voiceEmbeddings: [phoneVoice], lastModifiedAt: "2026-06-08T08:00:00.000Z")
        ]))
        let client = PhoneSyncClient(store: phoneStore, mac: mac)

        // First sync converges both sides to the 2-embedding union.
        XCTAssertEqual(client.run(), .merged, "first sync should merge")
        XCTAssertEqual(phoneStore.livePeople().first?.voiceEmbeddings?.count, 2)

        // Second sync: after PUT the Mac's top-level timestamp == the phone's local
        // (the phone PUT the merged data with `ISO8601.now()` and the Mac recomputes
        // top-level = max per-entry = that same value), so meta matches → no-op.
        let second = client.run()
        XCTAssertEqual(second, .unchanged, "re-sync with identical data is a no-op")
        XCTAssertEqual(phoneStore.livePeople().first?.voiceEmbeddings?.count, 2,
                       "union de-dupes by vector — no bloat on re-sync")
        XCTAssertEqual(macStore.livePeople().first?.voiceEmbeddings?.count, 2)
    }
}
