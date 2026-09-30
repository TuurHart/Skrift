import Foundation

/// WHERE a note goes when it leaves Skrift — one of four, never two.
///
/// **The destination is a PRIVACY BOUNDARY, not a filing shelf.** That is Tuur's reason for
/// the whole feature (2026-08-26): his own thoughts must never be read by AI, while his ideas
/// and inspirations are the things he *wants* an AI to work out with him. Every rule in this
/// file falls out of that one fact, so read it before changing any of them:
///
/// - **One-of-four, never two.** The engine could write a memo to several destinations
///   (`ExportLedger` is keyed per destination folder, so N destinations are N independent
///   ledgers) — it is refused on purpose. Allow two and `personal` + `idea` becomes
///   expressible, which is a private thought sitting in a repo an AI reads: the exact
///   outcome the feature exists to prevent.
/// - **`idea` + `inspiration` is meaningless, not merely unsupported.** The line between them
///   is AUTHORSHIP — an inspiration is someone else's work, an idea is his own intent — and
///   nothing can be both. The photograph that *gave him an idea* is ONE note, filed `.idea`
///   ("that's actually how it always happens"); `.inspiration` is the narrower bucket, for a
///   thing he liked with no idea attached yet.
/// - **A stored field, NOT a tag string.** It is *rendered* as a chip beside the tags, which
///   is what he asked for, but a literal tag would mean typing `idea` in the free tag field
///   silently re-routes a note — a typo by another name. `reserved(_:)` is what refuses that.
///
/// `.personal` is the default and means exactly today's behaviour: the note goes to the
/// Obsidian vault picked in Settings, nothing else changes. The other three are inert until
/// the user turns destinations on and picks their folders.
enum NoteDestination: String, CaseIterable, Codable, Sendable {
    /// His own thoughts → the Obsidian vault. The default, and off-limits to the portfolio.
    case personal
    /// Someone ELSE's work that he liked → the portfolio's `_inspiration/`.
    case inspiration
    /// Something he wants to make — HIS intent → the portfolio's `_ideas/`.
    case idea
    /// A thing he is building or has finished — a project → the portfolio's `_projects/`, to be sorted
    /// into its item folder. Declared last: the order here IS the order the row shows.
    case project

    /// The chip's word.
    var label: String {
        switch self {
        case .personal:    "Personal"
        case .inspiration: "Inspiration"
        case .idea:        "Idea"
        case .project:     "Project"
        }
    }

    /// Does this destination leave Skrift's private side? Drives the chip's colour (one
    /// family is private, three are public) and the "AI reads this" line — the user should be
    /// able to see which side of the boundary a note is on without reading a word.
    var isPortfolio: Bool { self != .personal }

    /// The folder each portfolio destination writes into, relative to the picked portfolio root.
    /// `nil` for `.personal`, which uses the existing Obsidian vault bookmark instead.
    var portfolioFolder: String? {
        switch self {
        case .personal:    nil
        case .inspiration: "_inspiration"
        case .idea:        "_ideas"
        case .project:     "_projects"
        }
    }

    /// The word a user might type that means "this is a destination, not a tag". Matched
    /// case- and `#`-insensitively so `#Idea`, `idea` and `IDEA` all land here.
    static func reserved(_ word: String) -> NoteDestination? {
        let key = word.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
        return allCases.first { $0.rawValue == key }
    }
}

// MARK: - The feature switch

/// Destinations are OFF until turned on, on every device (Tuur, 2026-08-26: *"this might
/// actually be a toggle in settings because somebody might not care. This is very specific
/// for me"*). Off means the chip row does not appear and every note is `.personal` — i.e.
/// today's behaviour, unchanged, which is also what the App Store build ships as.
///
/// Per-device like the vault bookmark, and deliberately NOT synced: whether THIS device shows
/// the control is a local fact, the same way "is a folder picked here" is.
enum DestinationSettings {
    private static let key = "skrift.destinations.enabled"

    /// ONE portfolio root, not three pickers. The three portfolio destinations are SIBLINGS
    /// inside it (`_projects` / `_ideas` / `_inspiration` — `NoteDestination.portfolioFolder`),
    /// which is how the portfolio is laid out, so asking for three folders would be asking
    /// the same question three times and letting two of the answers be wrong.
    ///
    /// `.personal` is NOT here: it keeps the existing Obsidian vault setting on each app
    /// (the phone's security-scoped bookmark, the Mac's `AppSettings.noteFolder`), so
    /// turning destinations on moves nothing that already works.
    static let portfolioRootKey = "skrift.destinations.portfolioRoot"

    static var isEnabled: Bool {
        get { forcedOn || UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// `-destinationsOn` — the screenshot/UI rig's override. Read straight from the
    /// process arguments so this type stays app-agnostic (the Mac has no `LaunchFlags`).
    private static var forcedOn: Bool {
        ProcessInfo.processInfo.arguments.contains("-destinationsOn")
    }

    /// `-resetDestinations` — put this device back to the shipped default. A UI run must
    /// not inherit what a previous run left in UserDefaults: `-inMemoryStore` resets
    /// SwiftData and nothing else, which is how a "switch is off" test started finding the
    /// switch already on.
    static func resetIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-resetDestinations") else { return }
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: portfolioRootKey)
    }
}
