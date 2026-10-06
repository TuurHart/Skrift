import Foundation

/// Settings + Names strings, rules and sizes that were typed twice (phone/iPad vs Mac) —
/// Q176 (parity audit §3.5, C239/C240). Picks: a signed mock or SPEC clause where one
/// names the row, otherwise the phone's wording and look. Platform words stay in the
/// callers' arguments (the device name, whether the device can process).
enum SettingsCopy {

    // ── Weather key (Q326) ──
    static let weatherKeyHelp = "Used to tag notes with weather + pressure. Get a free key at openweathermap.org."

    // ── Custom words (setexp-29, -30) ──
    static let customWordPlaceholder = "Add a word or name…"
    static let customWordsHelp = "The transcriber listens for these words and corrects near-misses (“skrift” → “Skrift”). Spelled exactly as you want them written. The first transcription after adding words downloads a \(ModelSizes.spotter) model."

    // ── Obsidian folder (setexp-58, -59) ──
    /// Signed mock `vault-folder-model.html` names this row "Obsidian folder"; the phone said "Folder".
    static let obsidianFolderLabel = "Obsidian folder"
    static let chooseVerb = "Choose…"

    /// What THIS device will actually do with the folder — never more. `folderName` = the
    /// picked folder's display name (nil = none picked); `canProcess` = the device writes
    /// notes (iPad, Mac) rather than only reading the vault (iPhone).
    static func obsidianHelp(folderName: String?, canProcess: Bool) -> String {
        guard let folderName else {
            return canProcess
                ? "Pick the folder inside your vault where Skrift should put its notes — audio and photos land in subfolders beside them. Skrift only ever touches its own files."
                : "Pick your Skrift folder so this iPhone can read your vault. Notes are written to it by your Mac (and iPad) once they've been processed."
        }
        return canProcess
            ? "Notes, audio and photos go into “\(folderName)”. A note you edit or move in Obsidian is left alone — Skrift never overwrites your version."
            : "This iPhone reads “\(folderName)”; it doesn't write to it. Your Mac and iPad put notes there once they've processed them."
    }

    // ── Destinations (setexp-67) ──
    static let destinationsToggleLabel = "Separate destinations"
    static let portfolioFolderLabel = "Portfolio folder"

    /// The footer under the Destinations switch: off / on with no folder on this device /
    /// on with a folder. The on-without-folder text names the per-device folder (phone's
    /// wording; the Mac showed only the bare notice).
    static func destinationsHelp(on: Bool, hasFolder: Bool) -> String {
        guard on else {
            return "Off, every note goes to your Obsidian vault. On, each note carries one of "
                 + "four destinations you pick on the note itself."
        }
        guard hasFolder else {
            return DestinationSettings.needsFolderNotice + ". This switch is on for all your "
                 + "devices; the folder is chosen per device. Skrift writes Project, Idea and "
                 + "Inspiration notes into folders inside it. Personal notes still go to your "
                 + "Obsidian vault and never here."
        }
        return "Personal notes go to your Obsidian vault. Project, Idea and Inspiration go to the "
             + "portfolio — a folder you have chosen to let an AI read, so nothing personal is "
             + "ever written there."
    }
}

/// The Names list + person editor strings (setexp-99, -109, -112, -113).
enum NamesCopy {
    // Empty state — C80/D77: the phone and iPad link names too, not only the Mac.
    static let emptyTitle = "No people yet"
    static let emptyBody = "Add people so their names link in your notes."

    /// The search/filter field on the names list, both apps.
    static let searchPlaceholder = "Search people"

    // Voice state words: one vocabulary on the list row, the detail card and both editors.
    static let voiceEnrolled = "Voice enrolled"
    static let voiceMissing = "Add voice"
    static func voiceEnrolledHelp(name: String) -> String {
        "Conversation mode can attribute speech to \(name)."
    }
    /// Under the missing state wherever the surface has no recorder of its own
    /// (the editors, the Mac row tooltip). Replaces the phone editor's stale
    /// "record in a note or on your Mac".
    static let voiceMissingHint = "Name them in a conversation (phone or Mac) to enroll their voice."
    /// The phone's detail card, which has the recorder button.
    static let voiceMissingRecordHelp = "Enroll a short voice sample so Conversation mode can tell who's speaking."

    // Person editor chrome.
    static let editorTitle = "Person"
    static let newPersonTitle = "New person"
    static let doneVerb = "Done"
    static let cancelVerb = "Cancel"
    static let fullNameLabel = "Full name"
    static let fullNamePlaceholder = "Full name"
    static func fullNameHelp(isNew: Bool) -> String {
        isNew ? "The Obsidian note title — becomes the [[link]] target."
              : "The Obsidian note title — the [[link]] target. Change it to rename this person."
    }
}

/// ONE names matcher for the phone's "Search people" and the Mac's names filter (setexp-101):
/// the display name OR any alias contains the query, case- and accent-insensitive. The phone
/// matched the name only, so searching a nickname found nobody.
enum NamesFilter {
    static func matches(_ person: Person, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if person.displayName.range(of: q, options: opts) != nil { return true }
        return person.aliases.contains { $0.range(of: q, options: opts) != nil }
    }

    static func apply(_ people: [Person], query: String) -> [Person] {
        people.filter { matches($0, query: query) }
    }
}

/// Names list row size — the phone's numbers (setexp-103); the Mac was 38 / 15 / 11.
enum NameRowLook {
    static let avatarSize: Double = 42
    static let nameSize: Double = 16
    static let statusSize: Double = 12
    static let chevronSize: Double = 14
    static let textSpacing: Double = 5
    static let rowSpacing: Double = 12
    static let verticalPadding: Double = 11
    static let horizontalPadding: Double = 6
}
