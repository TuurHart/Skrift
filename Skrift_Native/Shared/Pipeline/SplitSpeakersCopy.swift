import Foundation

/// The words of "Split speakers", ONE copy for both apps (signed mock
/// `SkriftDesktop/mocks/Q86-split-speakers.html`, Q87). Foundation-only so the MLX-free
/// desktop test bundle and the phone bundle both compile it.
enum SplitSpeakersCopy {
    /// Both apps, when the diarizer found fewer than two voices. Today's silence read as broken.
    static let oneVoice = "Only one voice found. Nothing was split."

    /// The Mac header row's resting line, when the note is not split.
    static let switchOffHint = "Off. Turn on to see who said what, when more than one person talks."
    /// The Mac switch on an unrated note: the Mac has no pipeline row for it (C187).
    static let rateFirst = "Rate the note first. The Mac only works on rated notes."
    static let rateFirstShort = "Rate the note first"
    /// The row while the note is split.
    static let splitHint = "Click a name to say who it is."

    // MARK: Mac confirm — turning on
    static let confirmTitle = "Split this note into speakers?"
    static let confirmSplit = "Split speakers"
    static func confirmBody(durationSeconds: Double) -> String {
        "The Mac listens to the recording again and writes the transcript as turns, one per voice. "
            + "Voices it knows get their names. \(estimate(durationSeconds: durationSeconds))"
    }

    /// "About 3 minutes for this 3:12 recording." A number, not "about as long as the recording".
    static func estimate(durationSeconds: Double) -> String {
        guard durationSeconds.isFinite, durationSeconds > 0 else { return "This can take a few minutes." }
        let minutes = Int((durationSeconds / 60).rounded())
        let length = clock(durationSeconds)
        if minutes < 1 { return "Under a minute for this \(length) recording." }
        return "About \(minutes) minute\(minutes == 1 ? "" : "s") for this \(length) recording."
    }

    /// The amber line. Only when the transcript was hand-edited; nil otherwise. The date is the
    /// note's last edit ("28 Sep"), fixed en_GB so a Portuguese-locale Mac reads the same.
    static func editWarning(editedAt: Date?) -> String? {
        guard let editedAt else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM"
        return "You edited this transcript on \(f.string(from: editedAt)). Those edits are replaced."
    }

    // MARK: progress
    static let listening = "Listening again for who speaks when"
    static let keepsGoing = "Keeps going if you open another note; if you quit Skrift it starts again at the next launch. The text is read-only until it finishes."
    static let queued = "Queued. Starts when the current run finishes."
    static let cancelled = "Cancelled. The note is as it was."

    // MARK: Flatten
    static let flattenTitle = "Flatten to monologue?"
    static let flattenKeep = "Keep speakers"
    static let flattenConfirm = "Flatten"

    /// The Mac's confirm: says what comes off and what stays. `person` is a name this note's
    /// turns carry (nil when every speaker is still "Speaker N").
    static func flattenBodyMac(person: String?) -> String {
        var s = "Speaker names come off and the turns join into plain text. "
            + "The title and summary are written again for one voice.\n\n"
            + "The words stay as they are, with your fixes. The recording is not transcribed again."
        if let person { s += " \(person) stays in Names." }
        return s
    }

    /// The phone's confirm: same promise, no re-polish (the Mac writes that).
    static let flattenBodyPhone = "Speaker names come off. The words stay as they are, with your fixes. Nothing is transcribed again."

    // MARK: naming
    /// The naming sheet's merge line, on both apps (the code moves ONE line, not the speaker).
    static let mergeHint = "Wrong split? Move just this line to another speaker."
    static func namesAllTurns(count: Int, speaker: String) -> String {
        "A person names all \(count) of \(speaker)\u{2019}s turns."
    }

    // MARK: phone "How many speakers?"
    static let howManyMessage = "Auto finds the number itself. Pick one if you know it. Edits you made to this transcript are replaced."

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
