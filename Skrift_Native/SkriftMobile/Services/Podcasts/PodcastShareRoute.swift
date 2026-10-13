import Combine
import Foundation

/// Q356 (D90 doors, Q353 carry-over): a podcast link shared from another app goes to Library, not
/// into a note. Main-app only (the share extension compiles `CaptureInbox.swift` but not the
/// podcast code), so the drain decides, not the sheet.
extension CaptureInboxEntry {
    /// True for an Apple Podcasts or Spotify show/episode link shared with no words and no rating.
    /// Any other link (an article, a video, Spotify music) stays a note; so does a podcast link he
    /// wrote something about or rated: the same rule as a shared PDF (`routesPDFToLibrary`).
    static func routesPodcastToLibrary(url: String?, thought: String?, significance: Double) -> Bool {
        guard let url, let link = PodcastLink.classify(url) else { return false }
        if case .feed = link { return false }   // every other web link classifies as a feed
        let hasThought = !(thought ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !hasThought && significance <= 0
    }
}

/// The "a podcast link was shared" signal from the drain to the Library tab, which opens the
/// podcast sheet with the link already looked up. One pending link; `clear()` once shown.
@MainActor
final class PodcastLinkArrival: ObservableObject {
    static let shared = PodcastLinkArrival()
    struct Arrival: Identifiable, Equatable {
        let id = UUID()
        let link: String
    }
    @Published private(set) var pending: Arrival?
    func post(_ link: String) { pending = Arrival(link: link) }
    func clear() { pending = nil }
}
