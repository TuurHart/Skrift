import Foundation

/// What `ProcessingCoordinator` is doing RIGHT NOW, as plain values (Q118, C194/C182).
/// The coordinator publishes it from its own `RunState`; keeping the shape here lets
/// `MacNoteRunStateTests` pin the per-note mapping without compiling the coordinator (MLX).
struct MacRunSnapshot: Equatable {
    /// The note the run is on right now; nil before the first note starts (models loading) and
    /// between notes.
    var currentID: String?
    /// How many steps THIS note's pass has: 2 when it needs transcription first, otherwise 1.
    var currentSteps: Int = 1
    /// Every note of the live run that has not finished (the current one included).
    var pendingIDs: Set<String> = []
    /// Non-nil while a model is loading/downloading (before the first note starts).
    var loadingLabel: String?
    var loadingFraction: Double?
}

/// ONE note's run state on the Mac note bar — the iPad's `PolishCenter.Phase`, for the Mac.
///
/// The iPad draws a progress bar + step line and replaces the verb while its pass runs; the Mac
/// note had only the sidebar's global run bar, its primary button stayed pressable mid-run, and a
/// failure printed the GLOBAL `lastError` banner with no way to retry. The note bar now takes THIS
/// note's state from here and draws the same bar + step line (`SharedCopy.processingStep`).
enum MacNoteRunState: Equatable {
    case idle
    /// In the live run, not its turn yet.
    case queued
    /// A model is loading/downloading before this note's turn: "Getting the model — 45%".
    case loading(line: String, fraction: Double?)
    /// This note's pass: "Transcribe · 1 of 2", "Polish · 2 of 2".
    case running(line: String, fraction: Double)
    /// The last pass on this note failed and the note still owes processing: "Couldn't process — Retry".
    case failed(reason: String)

    /// The verb is replaced and cannot be pressed while any of these shows.
    var isBusy: Bool {
        switch self {
        case .queued, .loading, .running: return true
        case .idle, .failed: return false
        }
    }

    /// The step labels, one vocabulary with the iPad's "Copy-edit · 2 of 3".
    static let transcribeStep = "Transcribe"
    static let polishStep = "Polish"
    static let queuedLine = "Queued"
    /// `Couldn't process — Retry`: the failed state's words (the Retry half is the button).
    static let failedLine = "Couldn't process"

    /// - Parameters:
    ///   - run: the coordinator's live run, nil when none.
    ///   - transcribe / enhance: THIS note's own step statuses.
    ///   - error: THIS note's recorded failure (`PipelineFile.error`).
    ///   - needsProcessing: Retry means "Process", so a failure only shows while the note still
    ///     owes a polish (`NoteWorkState.wantsProcessing`); a failed re-transcribe of an already
    ///     polished note has nothing for Retry to do and keeps the global banner.
    static func of(noteID: String, run: MacRunSnapshot?, transcribe: StepStatus, enhance: StepStatus,
                   error: String?, needsProcessing: Bool) -> MacNoteRunState {
        if let run, run.pendingIDs.contains(noteID) || run.currentID == noteID {
            if run.currentID == noteID {
                let steps = max(1, run.currentSteps)
                // The transcribe step ends when its status leaves .processing/.pending; from
                // then on the note is on its last step.
                let step = (steps == 2 && transcribe != .done) ? 1 : steps
                let label = step == 1 && steps == 2 ? transcribeStep : polishStep
                // No sub-progress exists on the Mac, so the bar sits at the middle of the step
                // (honest about "step n of m", never a fake percentage).
                let fraction = (Double(step - 1) + 0.5) / Double(steps)
                return .running(line: SharedCopy.processingStep(label, step, of: steps), fraction: fraction)
            }
            if let label = run.loadingLabel {
                let line = run.loadingFraction.map(SharedCopy.processingDownload) ?? SharedCopy.processingLoading(label)
                return .loading(line: line, fraction: run.loadingFraction)
            }
            return .queued
        }
        if needsProcessing, transcribe == .error || enhance == .error || error != nil {
            return .failed(reason: error ?? "")
        }
        return .idle
    }
}
