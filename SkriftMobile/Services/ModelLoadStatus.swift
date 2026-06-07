import SwiftUI

/// Observable model-load state shared by the record screen + onboarding, so the
/// "on-device transcription" status and the 494 MB download progress bar update
/// LIVE (the previous one-shot check went stale — showed "not downloaded" even
/// after the download finished). `TranscriptionService` drives it.
@MainActor
final class ModelLoadStatus: ObservableObject {
    static let shared = ModelLoadStatus()
    /// True once the Parakeet model is loaded + ready to transcribe.
    @Published var ready = false
    /// 0...1 while actively downloading; nil otherwise (idle/compiling/ready).
    @Published var downloadProgress: Double?
    private init() {}
}
