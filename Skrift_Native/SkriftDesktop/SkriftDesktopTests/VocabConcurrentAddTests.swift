import XCTest
import SwiftData

/// C267 / R80 (`vocab-concurrent-offline-add`): two devices that each add a word while
/// offline both keep both words after the sync, and a removal on one device still removes.
///
/// Each simulated device owns its local list (what `CustomVocabularyStore` / `AppSettings`
/// hold) and its own in-memory store holding its copy of the `VocabularyRecord` carrier.
/// `deliver` plays CloudKit: the sender's carrier row overwrites the receiver's copy, the
/// way the server keeps one writer's record when both devices rewrote it.
@MainActor
final class VocabConcurrentAddTests: XCTestCase {

    @MainActor private final class Device {
        let container: ModelContainer
        var local = VocabularySyncCore.LocalVocab(words: [], modifiedAt: .distantPast, ledger: nil)
        var context: ModelContext { container.mainContext }

        init() throws {
            let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            container = try ModelContainer(for: VocabularyRecord.self, configurations: config)
        }

        func records() -> [VocabularyRecord] {
            (try? context.fetch(FetchDescriptor<VocabularyRecord>())) ?? []
        }

        /// What `VocabularyCloudSync.run` does on either app.
        @discardableResult
        func sync(now: Date) -> VocabularySyncCore.SyncResult {
            let result = VocabularySyncCore.sync(
                local: local, records: records(), now: now,
                insert: { self.context.insert($0) }, delete: { self.context.delete($0) })
            if result.localChanged { local = result.local }
            try? context.save()
            return result
        }

        /// A Settings edit: applied to the CURRENT local list, then pushed.
        func edit(_ edit: VocabularySyncCore.Edit, at now: Date) {
            if let next = VocabularySyncCore.applying(edit, to: local, now: now) { local = next }
            sync(now: now)
        }
    }

    private var t0: Date!
    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    override func setUp() {
        t0 = Date(timeIntervalSince1970: 1_800_000_000)
    }

    /// CloudKit delivers `from`'s carrier to `to`, replacing `to`'s copy.
    private func deliver(from: Device, to: Device) throws {
        for row in to.records() { to.context.delete(row) }
        for row in from.records() { to.context.insert(copy(row)) }
        try to.context.save()
    }

    /// CloudKit delivers `from`'s carrier rows next to `to`'s own (two devices each created one).
    private func deliverAlongside(from: Device, to: Device) throws {
        for row in from.records() { to.context.insert(copy(row)) }
        try to.context.save()
    }

    private func copy(_ row: VocabularyRecord) -> VocabularyRecord {
        let out = VocabularyRecord(words: row.words, modifiedAt: row.modifiedAt)
        out.wordLedger = row.wordLedger
        return out
    }

    private func set(_ words: [String]) -> Set<String> { Set(words.map { $0.lowercased() }) }

    /// Phone and Mac start in step with one word.
    private func pairInStep(_ words: [String]) throws -> (phone: Device, mac: Device) {
        let phone = try Device(), mac = try Device()
        for (i, word) in words.enumerated() { phone.edit(.add(word), at: at(Double(i))) }
        try deliver(from: phone, to: mac)
        mac.sync(now: at(5))
        XCTAssertEqual(mac.local.words, phone.local.words, "precondition: the pair starts in step")
        return (phone, mac)
    }

    // MARK: - The R80 case

    func testTwoDevicesEachAddAWordOfflineBothSurvive_macWritesLast() throws {
        let (phone, mac) = try pairInStep(["Skrift"])
        phone.edit(.add("Parakeet"), at: at(10))   // offline: only its own carrier copy
        mac.edit(.add("Gemma"), at: at(20))         // offline, later stamp

        // Back online: the server keeps the Mac's row (it wrote last) and hands it to the phone.
        try deliver(from: mac, to: phone)
        phone.sync(now: at(30))
        try deliver(from: phone, to: mac)
        mac.sync(now: at(31))

        let all: Set<String> = ["skrift", "parakeet", "gemma"]
        XCTAssertEqual(set(phone.local.words), all, "the phone's offline word survives the Mac's overwrite")
        XCTAssertEqual(set(mac.local.words), all, "the Mac receives the phone's offline word")
        XCTAssertEqual(set(mac.records().first?.words ?? []), all, "the carrier holds both words")
    }

    func testTwoDevicesEachAddAWordOfflineBothSurvive_phoneWritesLast() throws {
        let (phone, mac) = try pairInStep(["Skrift"])
        mac.edit(.add("Gemma"), at: at(10))
        phone.edit(.add("Parakeet"), at: at(20))

        try deliver(from: phone, to: mac)
        mac.sync(now: at(30))
        try deliver(from: mac, to: phone)
        phone.sync(now: at(31))

        let all: Set<String> = ["skrift", "parakeet", "gemma"]
        XCTAssertEqual(set(phone.local.words), all)
        XCTAssertEqual(set(mac.local.words), all)
    }

    func testBothDevicesCreateTheirFirstCarrierOfflineAndMerge() throws {
        let phone = try Device(), mac = try Device()
        phone.edit(.add("Parakeet"), at: at(1))   // each creates its own carrier row
        mac.edit(.add("Gemma"), at: at(2))

        try deliverAlongside(from: mac, to: phone)
        phone.sync(now: at(3))
        XCTAssertEqual(phone.records().count, 1, "duplicate carriers collapse into one")
        try deliver(from: phone, to: mac)
        mac.sync(now: at(4))

        XCTAssertEqual(set(phone.local.words), ["parakeet", "gemma"])
        XCTAssertEqual(set(mac.local.words), ["parakeet", "gemma"])
    }

    // MARK: - Removal still removes

    func testRemovalOnOneDeviceStillRemovesWhileTheOtherAdds() throws {
        let (phone, mac) = try pairInStep(["Skrift", "Gemma"])
        phone.edit(.remove("Gemma"), at: at(10))     // offline removal
        mac.edit(.add("Parakeet"), at: at(20))       // offline add, later stamp

        try deliver(from: mac, to: phone)
        phone.sync(now: at(30))
        try deliver(from: phone, to: mac)
        mac.sync(now: at(31))

        XCTAssertEqual(set(phone.local.words), ["skrift", "parakeet"])
        XCTAssertEqual(set(mac.local.words), ["skrift", "parakeet"], "the phone's removal reaches the Mac")
    }

    func testRemovalPropagatesWhenTheRemoverWritesLast() throws {
        let (phone, mac) = try pairInStep(["Skrift", "Gemma"])
        mac.edit(.remove("Skrift"), at: at(10))
        try deliver(from: mac, to: phone)
        phone.sync(now: at(11))
        XCTAssertEqual(phone.local.words, ["Gemma"])
    }

    func testAWordReAddedAfterARemovalStays() throws {
        let (phone, mac) = try pairInStep(["Skrift", "Gemma"])
        phone.edit(.remove("Gemma"), at: at(10))
        try deliver(from: phone, to: mac)
        mac.sync(now: at(11))
        XCTAssertFalse(set(mac.local.words).contains("gemma"))

        mac.edit(.add("Gemma"), at: at(20))          // added back later
        try deliver(from: mac, to: phone)
        phone.sync(now: at(21))
        XCTAssertTrue(set(phone.local.words).contains("gemma"), "a later re-add beats the older removal")
    }

    // MARK: - Write time uses the stored list

    func testAnEditAppliesToTheCurrentListNotALoadTimeCopy() throws {
        let (phone, mac) = try pairInStep(["Skrift"])
        let screenCopy = mac.local                   // what a Settings sheet loaded on open
        phone.edit(.add("Parakeet"), at: at(10))
        try deliver(from: phone, to: mac)
        mac.sync(now: at(11))                        // the word syncs in while the sheet is open

        mac.edit(.add("Gemma"), at: at(12))          // the edit re-reads the stored list
        XCTAssertEqual(set(mac.local.words), ["skrift", "parakeet", "gemma"])
        XCTAssertFalse(set(screenCopy.words).contains("parakeet"), "the stale copy never reaches the store")
    }

    // MARK: - Pre-ledger data

    func testALegacyCarrierStillWinsWholeListAndSeedsTheLedger() throws {
        let mac = try Device()
        mac.local = .init(words: ["old"], modifiedAt: at(0), ledger: nil)
        mac.context.insert(VocabularyRecord(words: ["alpha", "beta"], modifiedAt: at(10)))
        try mac.context.save()

        mac.sync(now: at(11))

        XCTAssertEqual(mac.local.words, ["alpha", "beta"], "pre-ledger data keeps whole-list LWW")
        XCTAssertNotNil(mac.local.ledger, "the device now holds a ledger")
        XCTAssertNotNil(VocabularyLedger.decode(mac.records().first?.wordLedger), "and so does the carrier")
    }
}
