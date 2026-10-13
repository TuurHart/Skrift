import Foundation
import SwiftData

/// Q400 (D203, `plan/release/ICLOUD_MERGE.md` A4): the one-shot trigger for `DevEraMerge` in the
/// Release Mac app. Release builds take no DEBUG launch arguments, so Tuur hands the old store to
/// the app by moving it into `<app support>/merge-from-dev/` (ICLOUD_MERGE step 6). At launch, when
/// that folder holds `memo_cloud.store` AND the live store has finished its first CloudKit import
/// (`CloudFirstImport`, Q397), the app shows ONE alert with the plan's counts, conflicts and
/// diverged rows included. Yes runs `apply`, writes `merge-report.txt` (+ `merge-undo.json`) into
/// the folder and renames it to `merged-<date>/`. Not now leaves the folder for the next launch.
/// Never automatic: nothing writes without the Yes.
///
/// Pure + host-less (Foundation + SwiftData): every entry point takes its URLs and contexts, so
/// `MergeAlertTests` runs it on temp folders and synthetic stores. The AppKit alert lives in
/// `App/MergeAlertWiring.swift`.
enum DevMergeTrigger {

    static let folderName = "merge-from-dev"
    static let mergedPrefix = "merged-"

    static func sourceDir(appSupport: URL) -> URL {
        appSupport.appendingPathComponent(folderName, isDirectory: true)
    }

    /// The folder is there with a store in it, and the live store's first import is done.
    static func isPending(appSupport: URL, prodStoreURL: URL, stampURL: URL) -> Bool {
        let store = sourceDir(appSupport: appSupport).appendingPathComponent(DevEraMerge.storeFileName)
        guard FileManager.default.fileExists(atPath: store.path) else { return false }
        return CloudFirstImport.isDone(storeURL: prodStoreURL, stampURL: stampURL)
    }

    // MARK: - The alert's words

    /// Title, message and whether Yes is offered (a blocked plan offers only Not now).
    struct Prompt: Equatable {
        var title: String
        var message: String
        var canMerge: Bool
    }

    static func prompt(for plan: DevEraMerge.Plan) -> Prompt {
        let c = plan.counts
        let notes = plan.inserts.count
        let polishes = c.enhancementsInserted + plan.enhancementUpdates.count
        if let blocked = plan.blocked {
            return Prompt(title: "The old Mac store can't be merged yet",
                          message: blocked.description + "\n\nNothing was changed. The folder "
                            + "\(folderName) stays where it is.",
                          canMerge: false)
        }
        let lines = [
            "Bring in \(notes) \(noun(notes, "note")) and \(polishes) \(noun(polishes, "polish", "polishes")) "
                + "from the old Mac store?",
            "",
            "Notes to add: \(notes) (\(c.oldOnlyMacMade) made on the Mac, "
                + "\(c.oldOnlyPhoneAfterSplit) phone notes from after 25 Sep)",
            "Polishes: \(c.enhancementsInserted) new, \(plan.enhancementUpdates.count) updated",
            "Shared notes getting the Mac's changes: \(plan.fieldCopies.count)",
            "Conflicts, edited on both sides after 25 Sep (Production kept): \(plan.conflicts.count)",
            "Differences with no timestamp (Production kept): \(plan.diverged.count)",
            "Skipped: \(c.oldOnlyTrashed) trashed, \(c.oldOnlyPhoneBeforeSplit) phone notes from before 25 Sep",
            "",
            "Yes writes merge-report.txt with these counts and the note ids, "
                + "and renames the folder to \(mergedPrefix)<date>.",
        ]
        return Prompt(title: "Merge the old Mac store?", message: lines.joined(separator: "\n"), canMerge: true)
    }

    private static func noun(_ n: Int, _ one: String, _ many: String? = nil) -> String {
        n == 1 ? one : (many ?? one + "s")
    }

    // MARK: - Yes

    /// `merged-yyyy-MM-dd` (Europe/Lisbon), with `-2`, `-3`… when that name is taken.
    static func mergedDir(appSupport: URL, now: Date) -> URL {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        let d = cal.dateComponents([.year, .month, .day], from: now)
        let base = mergedPrefix + String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
        var candidate = appSupport.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = appSupport.appendingPathComponent("\(base)-\(n)", isDirectory: true)
            n += 1
        }
        return candidate
    }

    /// Yes: apply the plan into Production, write the report + undo journal into the folder, then
    /// rename the folder to `merged-<date>/`. Returns the renamed folder. `apply` throws before
    /// writing anything when the first import is not done or the plan is blocked; then the folder
    /// is left as it is.
    @discardableResult
    static func perform(plan: DevEraMerge.Plan, old: ModelContext, prod: ModelContext,
                        appSupport: URL, firstImportDone: Bool, now: Date = Date()) throws -> URL {
        let journal = try DevEraMerge.apply(plan, from: old, into: prod, firstImportDone: firstImportDone, now: now)
        let source = sourceDir(appSupport: appSupport)
        try DevEraMerge.writeReport(plan: plan, journal: journal, to: source)
        let target = mergedDir(appSupport: appSupport, now: now)
        try FileManager.default.moveItem(at: source, to: target)
        return target
    }
}

/// Q400: at most one merge alert per app launch. `shouldAsk` answers true once, and only while
/// the trigger is pending; Not now therefore waits for the next launch.
@MainActor
final class MergeAlertGate {
    private(set) var asked = false

    func shouldAsk(appSupport: URL, prodStoreURL: URL, stampURL: URL) -> Bool {
        guard !asked,
              DevMergeTrigger.isPending(appSupport: appSupport, prodStoreURL: prodStoreURL, stampURL: stampURL)
        else { return false }
        asked = true
        return true
    }
}
