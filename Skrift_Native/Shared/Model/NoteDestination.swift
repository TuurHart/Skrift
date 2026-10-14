import Foundation

/// WHERE a note goes when it leaves Skrift — one of TWO (D189, Tuur 2026-10-08: "perhaps
/// personal and portfolio is enough and we just sort via tags?").
///
/// **The destination is a PRIVACY BOUNDARY, not a filing shelf.** His own thoughts must never be
/// read by AI; his ideas and inspirations are the things he *wants* an AI to work out with him.
/// Only that line has to be decided at capture and has to be hard: a wrong Personal/Portfolio
/// pick puts a private thought in a repo an AI reads. Which kind of portfolio note it is
/// (idea / inspiration / project) costs one file move if wrong, so it is an ordinary TAG,
/// offered as one-tap presets when Portfolio is picked (`PortfolioTagPresets`), any combination.
///
/// The privacy choice stays a stored FIELD rather than a tag: a typo in the free tag field must
/// never re-route a note across the boundary. The presets are plain tags and route nothing.
///
/// `.personal` is the default and means exactly today's behaviour: the note goes to the Obsidian
/// vault picked in Settings. `.portfolio` is inert until the user turns destinations on and
/// picks the portfolio folder.
enum NoteDestination: String, CaseIterable, Codable, Sendable {
    /// His own thoughts → the Obsidian vault. The default, and off-limits to the portfolio.
    case personal
    /// The portfolio → `<portfolio root>/_inbox/`, sorted there by tag by the portfolio session.
    case portfolio

    /// The chip's word.
    var label: String {
        switch self {
        case .personal:  "Personal"
        case .portfolio: "Portfolio"
        }
    }

    /// Does this destination leave Skrift's private side? Drives the chip's colour and the
    /// export profile, so a glance answers which side of the line a note is on.
    var isPortfolio: Bool { self == .portfolio }

    /// D204: the other side of the line. The destination pill is a tap toggle, and this is its
    /// whole step (two destinations since D189).
    var toggled: NoteDestination { isPortfolio ? .personal : .portfolio }

    /// One tap on the pill: flip `current` in place and report the new value once. The shared
    /// `DestinationRowView` calls this; the Mac test drives it without a view.
    @discardableResult
    static func tapped(_ current: inout NoteDestination, onPick: (NoteDestination) -> Void) -> NoteDestination {
        let next = current.toggled
        current = next
        onPick(next)
        return next
    }

    /// The folder the portfolio destination writes into, relative to the picked portfolio root.
    /// `nil` for `.personal`, which uses the existing Obsidian vault bookmark instead.
    var portfolioFolder: String? {
        switch self {
        case .personal:  nil
        case .portfolio: "_inbox"
        }
    }

    // MARK: Stored values from before D189

    /// The four-destination era stored `idea`, `inspiration` and `project`. A note carrying one
    /// reads as Portfolio and the old word becomes a tag (`decode`, `exportTags`). No other
    /// unknown value may guess its way to Portfolio: it reads as Personal, the private side.
    static let legacyPortfolioWords: [String] = ["idea", "inspiration", "project"]

    /// Stored raw value → (destination, the tag an old value implies). Total: never fails.
    static func decode(_ raw: String) -> (destination: NoteDestination, legacyTag: String?) {
        if let d = NoteDestination(rawValue: raw) { return (d, nil) }
        if legacyPortfolioWords.contains(raw) { return (.portfolio, raw) }
        return (.personal, nil)
    }

    /// `tags` plus the tag a legacy stored value implies (case-insensitive, never duplicated).
    /// The exporters use this so an old value still lands as `idea` in `tags:` before the note
    /// has been opened (and so rewritten) on any device.
    static func exportTags(_ tags: [String], raw: String) -> [String] {
        guard let tag = decode(raw).legacyTag else { return tags }
        return withTag(tag, in: tags)
    }

    /// Append `tag` unless a case-insensitive match is already there.
    static func withTag(_ tag: String, in tags: [String]) -> [String] {
        tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } ? tags : tags + [tag]
    }
}

/// The tag SUGGESTIONS offered beside `+ tag` while a note is Portfolio (D205). Choosing Portfolio
/// adds NO tag by itself: these are quiet chips he taps to add one, or ignores. Plain tags:
/// typing `idea` in the tag field is the same thing and routes nothing. Any combination is
/// allowed: an idea sparked by someone else's lamp is `idea` + `inspiration`.
enum PortfolioTagPresets {
    static let all: [String] = NoteDestination.legacyPortfolioWords

    /// THE rule, read by the phone, iPad, Mac and quick note alike. The three show only while
    /// destinations are on, the note is Portfolio, and it carries none of them yet: once he has
    /// picked one the suggestion has done its job, and flipping back to Personal removes nothing
    /// (the tags are his), the chips just leave.
    static func suggestions(destination: NoteDestination, tags: [String], enabled: Bool) -> [String] {
        guard enabled, destination.isPortfolio else { return [] }
        let hasOne = all.contains { p in tags.contains { $0.caseInsensitiveCompare(p) == .orderedSame } }
        return hasOne ? [] : all
    }

    /// A tap on one suggestion: add just that tag (case-insensitive, never duplicated). Anything
    /// that is not one of the three is ignored.
    static func picked(_ tag: String, into tags: [String]) -> [String] {
        guard let preset = all.first(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return tags }
        return NoteDestination.withTag(preset, in: tags)
    }

    /// The tag that raises `needs: - credit` in the portfolio profile (someone else's work).
    static let inspiration = "inspiration"
}

// MARK: - The feature switch

/// Destinations are OFF until turned on (Tuur, 2026-08-26: *"this might actually be a toggle
/// in settings because somebody might not care. This is very specific for me"*). Off means the
/// chip row does not appear and every note is `.personal` — i.e. today's behaviour, unchanged,
/// which is also what the App Store build ships as.
///
/// The ON/OFF switch SYNCS across devices (Tuur 2026-10-02, D162, Q98: "if I turn it on
/// somewhere, it turns on everywhere"): a Bool plus its own LWW stamp in UserDefaults, mirrored
/// to the `VocabularyRecord` carrier by `DestinationsSyncCore`. The portfolio FOLDER stays per
/// device (a security-scoped bookmark / path means nothing on another machine): a device with
/// the switch on and no folder shows the chips and cannot export yet.
enum DestinationSettings {
    private static let key = "skrift.destinations.enabled"
    static let stampKey = "skrift.destinations.enabledModifiedAt"

    /// ONE portfolio root. Every Portfolio note lands in `<root>/_inbox/`
    /// (`NoteDestination.portfolioFolder`).
    ///
    /// `.personal` is NOT here: it keeps the existing Obsidian vault setting on each app
    /// (the phone's security-scoped bookmark, the Mac's `AppSettings.noteFolder`), so
    /// turning destinations on moves nothing that already works.
    static let portfolioRootKey = "skrift.destinations.portfolioRoot"

    static var isEnabled: Bool {
        get { forcedOn || storedEnabled() }
        set { set(newValue) }
    }

    /// The persisted switch, ignoring the `-destinationsOn` rig override — what sync reads.
    static func storedEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    /// `.distantPast` until a real flip (or the one-time seed below) — a device that never
    /// chose must not push its default over another device's choice.
    static func modifiedAt(defaults: UserDefaults = .standard) -> Date {
        (defaults.object(forKey: stampKey) as? Date) ?? .distantPast
    }

    /// The user flipped the switch here → store it and bump the stamp so it wins LWW.
    /// Writing the value already stored is ignored, so re-applying a synced value can
    /// never re-stamp it as a new edit.
    static func set(_ on: Bool, defaults: UserDefaults = .standard, now: Date = Date()) {
        guard on != storedEnabled(defaults: defaults) else { return }
        defaults.set(on, forKey: key)
        defaults.set(now, forKey: stampKey)
    }

    /// A value arrived from another device — keep the REMOTE stamp (never bumped to now).
    static func adoptSynced(_ on: Bool, modifiedAt: Date, defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: key)
        defaults.set(modifiedAt, forKey: stampKey)
    }

    /// One-time migration: a device that already had the switch ON before this synced carries
    /// no stamp. The default is OFF, so "on" can only be a deliberate choice — date it now so
    /// it propagates instead of waiting for a flip.
    static func seedStampIfNeeded(defaults: UserDefaults = .standard, now: Date = Date()) {
        guard storedEnabled(defaults: defaults), defaults.object(forKey: stampKey) == nil else { return }
        defaults.set(now, forKey: stampKey)
    }

    /// Settings copy for a device that has the switch on but no folder picked here.
    static let needsFolderNotice = "Pick a portfolio folder on this device to export"

    /// `-destinationsOn` — the screenshot/UI rig's override. Read straight from the
    /// process arguments so this type stays app-agnostic (the Mac has no `LaunchFlags`).
    private static var forcedOn: Bool {
        LaunchArgs.has("-destinationsOn")
    }

    /// `-resetDestinations` — put this device back to the shipped default. A UI run must
    /// not inherit what a previous run left in UserDefaults: `-inMemoryStore` resets
    /// SwiftData and nothing else, which is how a "switch is off" test started finding the
    /// switch already on.
    #if DEBUG
    static func resetIfRequested() {
        guard LaunchArgs.has("-resetDestinations") else { return }
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: stampKey)
        UserDefaults.standard.removeObject(forKey: portfolioRootKey)
    }
    #endif
}
