import Foundation

/// Carries a pick of 2+ voice notes (Files importer, AirDrop / Open-in burst) from
/// `AppURLHandler` to the root, where the One-note / N-notes chooser is hosted (C68 / C145 —
/// the same question the share sheet asks, worded by the shared `AudioImportChoice`).
/// Nothing is imported until the user answers.
@MainActor
final class AudioPickBridge: ObservableObject {
    static let shared = AudioPickBridge()

    struct Pending: Identifiable, Equatable {
        let id = UUID()
        let urls: [URL]
        let clipCount: Int
    }

    @Published var pending: Pending?

    private init() {}

    func offer(_ urls: [URL]) {
        pending = Pending(urls: urls, clipCount: AppURLHandler.audioClips(in: urls).count)
    }
}
