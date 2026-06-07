import Foundation

/// Recovers notes stranded mid-run. A step left in `.processing` means a run was
/// interrupted (app quit / crash) — no run is actually active at launch, so the
/// note would otherwise sit forever showing "Transcribing"/"Enhancing" and be
/// excluded from the queue's re-processable set. Reset such steps to `.pending` so
/// the Process button picks the note up again. Pure (host-tested); the coordinator
/// fetches + saves around it.
enum RunReconciler {
    @discardableResult
    static func resetInterrupted(_ files: [PipelineFile]) -> Bool {
        var changed = false
        for pf in files {
            if pf.transcribeStatus == .processing { pf.transcribeStatus = .pending; changed = true }
            if pf.sanitiseStatus == .processing { pf.sanitiseStatus = .pending; changed = true }
            if pf.enhanceStatus == .processing { pf.enhanceStatus = .pending; changed = true }
            if pf.exportStatus == .processing { pf.exportStatus = .pending; changed = true }
        }
        return changed
    }
}
