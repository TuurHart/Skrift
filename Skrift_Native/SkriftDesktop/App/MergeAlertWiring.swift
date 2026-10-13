import Foundation
import SwiftData
import AppKit

/// Q400 (ICLOUD_MERGE A4): shows the one-shot `DevEraMerge` alert at launch. Checked once per
/// launch, never on a later import event: the first import may finish mid-download (step 7), and
/// the plan wants Tuur to quit, run the dry run and open the app again (steps 8-9) before he sees
/// the numbers. The rules and words are in `DevMergeTrigger` (host-less, tested by
/// `MergeAlertTests`).
@MainActor
enum MergeAlertWiring {
    static let gate = MergeAlertGate()

    /// Call once from `applicationDidFinishLaunching`. Skipped under XCTest, headless modes and
    /// the perf library; a no-op unless the trigger is pending and Mac sync is on.
    static func checkAtLaunch() {
        if LaunchArgs.isXCTest { return }
        #if DEBUG
        if PerfLibrary.isActive || HeadlessIsolation.isRequested() { return }
        #endif
        // Let the window come up first, so the alert has something to sit over.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { askIfPending() }
    }

    private static func askIfPending() {
        let appSupport = AppPaths.appSupportDirectory
        let storeURL = AppPaths.memoCloudStoreFile
        let stampURL = AppPaths.memoCloudFirstImportStamp
        guard gate.shouldAsk(appSupport: appSupport, prodStoreURL: storeURL, stampURL: stampURL),
              let container = MemoCloudStore.syncContainer else { return }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("skrift-merge-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        do {
            let oldContainer = try DevEraMerge.openOldStoreCopy(sourceDir: DevMergeTrigger.sourceDir(appSupport: appSupport),
                                                                scratchDir: scratch)
            let old = ModelContext(oldContainer)
            let prod = ModelContext(container)
            let plan = try DevEraMerge.plan(old: old, prod: prod, macDeviceIDs: [DeviceID.current()])
            guard makeAlert(DevMergeTrigger.prompt(for: plan)).runModal() == .alertFirstButtonReturn,
                  DevMergeTrigger.prompt(for: plan).canMerge else { return }
            let done = CloudFirstImport.isDone(storeURL: storeURL, stampURL: stampURL)
            let merged = try DevMergeTrigger.perform(plan: plan, old: old, prod: prod,
                                                     appSupport: appSupport, firstImportDone: done)
            info("Merge done",
                 "The report is in \(merged.lastPathComponent)/\(DevEraMerge.reportFileName). "
                    + "Keep the Mac awake until the iCloud status is idle.")
        } catch {
            info("Merge did not run", "\(error)\n\nThe folder \(DevMergeTrigger.folderName) is left as it is.")
        }
    }

    /// The alert itself. Shared with the `-snapshot-merge-alert` render so the picture is the real one.
    static func makeAlert(_ prompt: DevMergeTrigger.Prompt) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = prompt.title
        alert.informativeText = prompt.message
        if prompt.canMerge {
            alert.addButton(withTitle: "Yes")
            alert.addButton(withTitle: "Not now")
        } else {
            alert.addButton(withTitle: "Not now")
        }
        return alert
    }

    private static func info(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
