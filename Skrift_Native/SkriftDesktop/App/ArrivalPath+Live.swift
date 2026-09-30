import Foundation
import SwiftData

/// The real hooks for `ArrivalPath` — the one place the pipeline's arrival path is joined to
/// the app's engines and CloudKit wiring. Kept out of `Pipeline/` for the same reason
/// `MemoCloudReconciler+Wiring` is: the host-less test bundle has neither an audio engine nor
/// a container, and the arrival path itself must stay testable without them.
extension ArrivalPath.Hooks {
    /// - Parameters:
    ///   - coordinator: owns the ASR run — `transcribe` is the transcribe-only entry point,
    ///     NOT `process()`, because a capture is unrated and `process()` skips unrated notes.
    ///   - context: the pipeline store the new rows were written to.
    @MainActor
    static func live(coordinator: ProcessingCoordinator, context: ModelContext) -> Self {
        ArrivalPath.Hooks(
            recordingDate: { await AudioMetadata.recordingDate(of: $0) },
            reconcileSoon: { MemoCloudReconciler.reconcileSoon() },
            transcribe: { ids in await coordinator.transcribe(fileIDs: ids, context: context) },
            transcribeImport: { ids in await coordinator.transcribe(fileIDs: ids, context: context) }
        )
    }
}
