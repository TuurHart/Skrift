import XCTest
import SwiftData
import Foundation

/// Q400 (D203, ICLOUD_MERGE.md A4): the one-shot merge-from-dev alert's trigger, words and Yes
/// path, on temp folders and synthetic stores only. Never a real store, never CloudKit.
@MainActor
final class MergeAlertTests: XCTestCase {

    private let mac = "mac-device"
    private let phone = "phone-device"
    private let S = DevEraMerge.splitDate
    private var appSupport: URL!
    private var prodStoreURL: URL { appSupport.appendingPathComponent("memo_cloud.store") }
    private var stampURL: URL { appSupport.appendingPathComponent("memo_cloud.first-import.json") }
    private var source: URL { DevMergeTrigger.sourceDir(appSupport: appSupport) }

    override func setUpWithError() throws {
        appSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("q400_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: appSupport)
        super.tearDown()
    }

    // MARK: - Fixtures

    /// A stand-in live store file plus the Q397 stamp naming it.
    private func markFirstImportDone() throws {
        try Data("live".utf8).write(to: prodStoreURL)
        CloudFirstImport.markDone(storeURL: prodStoreURL, stampURL: stampURL)
        XCTAssertTrue(CloudFirstImport.isDone(storeURL: prodStoreURL, stampURL: stampURL))
    }

    /// `merge-from-dev/memo_cloud.store` as a placeholder file (the trigger checks presence only).
    private func dropPlaceholderFolder() throws {
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: source.appendingPathComponent(DevEraMerge.storeFileName))
    }

    private func memoryStore() throws -> ModelContext {
        ModelContext(try ModelContainer(for: DevEraMerge.storeSchema,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func day(_ offset: Double) -> Date { S.addingTimeInterval(offset * 86_400) }

    @discardableResult
    private func memo(_ ctx: ModelContext, id: UUID = UUID(), device: String?, recorded: Date,
                      title: String? = "t", editedAt: Date? = nil) -> Memo {
        let m = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: recorded, title: title,
                     transcript: "words", transcriptStatus: .done, createdAt: recorded, editedAt: editedAt,
                     recordingDeviceID: device)
        ctx.insert(m)
        return m
    }

    /// A real on-disk old store in `merge-from-dev/` (CloudKit off) holding one Mac-made note.
    private func dropRealOldStore(macNote id: UUID) throws {
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let config = ModelConfiguration("Q400Old", schema: DevEraMerge.storeSchema,
                                        url: source.appendingPathComponent(DevEraMerge.storeFileName),
                                        cloudKitDatabase: .none)
        let container = try ModelContainer(for: DevEraMerge.storeSchema, configurations: config)
        let ctx = ModelContext(container)
        memo(ctx, id: id, device: mac, recorded: day(3), title: "Mac note")
        try ctx.save()
    }

    // MARK: - Trigger

    /// Folder present + first import done: the alert is asked for exactly once per launch.
    func testFolderPresentAndImportDoneAsksOnce() throws {
        try markFirstImportDone()
        try dropPlaceholderFolder()
        let gate = MergeAlertGate()
        XCTAssertTrue(gate.shouldAsk(appSupport: appSupport, prodStoreURL: prodStoreURL, stampURL: stampURL))
        XCTAssertFalse(gate.shouldAsk(appSupport: appSupport, prodStoreURL: prodStoreURL, stampURL: stampURL),
                       "one alert per launch")
        XCTAssertTrue(gate.asked)
    }

    /// No folder: never asked, however often the app checks.
    func testFolderAbsentNeverAsks() throws {
        try markFirstImportDone()
        let gate = MergeAlertGate()
        for _ in 0..<3 {
            XCTAssertFalse(gate.shouldAsk(appSupport: appSupport, prodStoreURL: prodStoreURL, stampURL: stampURL))
        }
        XCTAssertFalse(gate.asked)
    }

    /// A folder without the store file in it is not a trigger.
    func testEmptyFolderNeverAsks() throws {
        try markFirstImportDone()
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        XCTAssertFalse(MergeAlertGate().shouldAsk(appSupport: appSupport, prodStoreURL: prodStoreURL, stampURL: stampURL))
    }

    /// Never before the first import is done; the same launch's gate still asks once it is.
    func testWaitsForFirstImport() throws {
        try dropPlaceholderFolder()
        try Data("live".utf8).write(to: prodStoreURL)
        let gate = MergeAlertGate()
        XCTAssertFalse(gate.shouldAsk(appSupport: appSupport, prodStoreURL: prodStoreURL, stampURL: stampURL))
        XCTAssertFalse(gate.asked, "a refused check does not use up the one alert")
        CloudFirstImport.markDone(storeURL: prodStoreURL, stampURL: stampURL)
        XCTAssertTrue(gate.shouldAsk(appSupport: appSupport, prodStoreURL: prodStoreURL, stampURL: stampURL))
    }

    /// A merged folder (renamed) is not a trigger.
    func testMergedFolderNeverAsks() throws {
        try markFirstImportDone()
        let merged = appSupport.appendingPathComponent("merged-2026-10-13", isDirectory: true)
        try FileManager.default.createDirectory(at: merged, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: merged.appendingPathComponent(DevEraMerge.storeFileName))
        XCTAssertFalse(MergeAlertGate().shouldAsk(appSupport: appSupport, prodStoreURL: prodStoreURL, stampURL: stampURL))
    }

    // MARK: - Words

    /// The alert shows the plan's counts, including conflicts and the stamp-less (diverged) rows.
    func testPromptShowsCountsConflictsAndDiverged() throws {
        let old = try memoryStore(), prod = try memoryStore()
        memo(old, device: mac, recorded: day(2))                       // Mac-made, old only → insert
        memo(old, device: phone, recorded: day(4))                     // phone after S, old only → insert
        let diverged = UUID()                                          // un-stamped title difference
        memo(old, id: diverged, device: phone, recorded: day(-20), title: "Mac setTitle")
        memo(prod, id: diverged, device: phone, recorded: day(-20), title: "Phone")
        let conflict = UUID()                                          // edited on both sides after S
        memo(old, id: conflict, device: phone, recorded: day(-10), title: "Mac", editedAt: day(2))
        memo(prod, id: conflict, device: phone, recorded: day(-10), title: "Phone", editedAt: day(3))
        try old.save(); try prod.save()

        let plan = try DevEraMerge.plan(old: old, prod: prod, macDeviceIDs: [mac])
        XCTAssertEqual(plan.conflicts, [conflict])
        XCTAssertEqual(plan.diverged.keys.sorted { $0.uuidString < $1.uuidString }, [diverged])

        let p = DevMergeTrigger.prompt(for: plan)
        XCTAssertTrue(p.canMerge)
        XCTAssertTrue(p.message.hasPrefix("Bring in 2 notes and 0 polishes from the old Mac store?"), p.message)
        XCTAssertTrue(p.message.contains("Notes to add: 2 (1 made on the Mac, 1 phone notes from after 25 Sep)"), p.message)
        XCTAssertTrue(p.message.contains("Conflicts, edited on both sides after 25 Sep (Production kept): 1"), p.message)
        XCTAssertTrue(p.message.contains("Differences with no timestamp (Production kept): 1"), p.message)
        XCTAssertFalse(p.message.contains("Mac setTitle"), "counts only, never a title")
    }

    /// A blocked plan (Production lacks the phone's history) offers no Yes.
    func testBlockedPlanOffersOnlyNotNow() throws {
        var plan = DevEraMerge.Plan()
        plan.blocked = .tooManyPhoneNotesBeforeSplit(count: 30, limit: DevEraMerge.maxPhoneNotesBeforeSplit)
        let p = DevMergeTrigger.prompt(for: plan)
        XCTAssertFalse(p.canMerge)
        XCTAssertTrue(p.message.contains("30 phone notes"), p.message)
    }

    // MARK: - Yes

    /// Yes: apply, write merge-report.txt into the folder, rename it to merged-<date>/.
    func testYesMergesWritesReportAndRenamesFolder() throws {
        let id = UUID()
        try dropRealOldStore(macNote: id)
        let scratch = appSupport.appendingPathComponent("scratch", isDirectory: true)
        let old = ModelContext(try DevEraMerge.openOldStoreCopy(sourceDir: source, scratchDir: scratch))
        let prod = try memoryStore()
        let plan = try DevEraMerge.plan(old: old, prod: prod, macDeviceIDs: [mac])
        XCTAssertEqual(plan.inserts, [id])

        let now = Date(timeIntervalSince1970: 1_791_900_000)   // 2026-10-13 Lisbon
        let merged = try DevMergeTrigger.perform(plan: plan, old: old, prod: prod, appSupport: appSupport,
                                                 firstImportDone: true, now: now)
        XCTAssertEqual(merged.lastPathComponent, "merged-2026-10-13")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path), "merge-from-dev/ renamed away")
        let report = try String(contentsOf: merged.appendingPathComponent(DevEraMerge.reportFileName), encoding: .utf8)
        XCTAssertTrue(report.contains("inserted note ids (1):\n\(id.uuidString)"), report)
        XCTAssertFalse(report.contains("Mac note"), "counts and ids only")
        XCTAssertTrue(FileManager.default.fileExists(atPath: merged.appendingPathComponent(DevEraMerge.undoFileName).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: merged.appendingPathComponent(DevEraMerge.storeFileName).path),
                      "the old store moves with the folder, untouched")
        XCTAssertEqual(try prod.fetch(FetchDescriptor<Memo>()).map(\.id), [id])
    }

    /// Yes before the first import is done writes nothing and leaves the folder.
    func testYesRefusesBeforeFirstImport() throws {
        let id = UUID()
        try dropRealOldStore(macNote: id)
        let old = ModelContext(try DevEraMerge.openOldStoreCopy(sourceDir: source,
                                                               scratchDir: appSupport.appendingPathComponent("scratch")))
        let prod = try memoryStore()
        let plan = try DevEraMerge.plan(old: old, prod: prod, macDeviceIDs: [mac])
        XCTAssertThrowsError(try DevMergeTrigger.perform(plan: plan, old: old, prod: prod, appSupport: appSupport,
                                                         firstImportDone: false)) { error in
            XCTAssertEqual(error as? DevEraMerge.MergeError, .firstImportNotDone)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.appendingPathComponent(DevEraMerge.reportFileName).path))
        XCTAssertTrue(try prod.fetch(FetchDescriptor<Memo>()).isEmpty)
    }

    /// A second merge on the same day gets merged-<date>-2, never overwriting the first.
    func testMergedDirNameAvoidsCollision() throws {
        let now = Date(timeIntervalSince1970: 1_791_900_000)
        let first = DevMergeTrigger.mergedDir(appSupport: appSupport, now: now)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        XCTAssertEqual(DevMergeTrigger.mergedDir(appSupport: appSupport, now: now).lastPathComponent, "merged-2026-10-13-2")
    }
}
