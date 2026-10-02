import Foundation

/// What an import did, said the same way on both apps (C199, C202, C77): how many notes it
/// made, which files it skipped (a type Skrift does not take, a file that was gone) and which
/// failed, each with the reason. Both apps show it as a list banner (`bannerLines`), so a drop
/// with nothing to show for it is never silent.
///
/// Pure (Foundation only): the phone's `AppURLHandler`, the Mac's `IngestService` and the
/// host-less test bundles all compile it directly.
struct ImportReport: Equatable, Sendable {
    /// One file that did not become a note, and why.
    struct Problem: Equatable, Sendable, Identifiable {
        var name: String
        var reason: String
        var id: String { name + "\u{1F}" + reason }
    }

    /// Notes made.
    var created: Int = 0
    /// Files Skrift did not take, or could not read. The user can fix these (convert the
    /// file, drop it elsewhere).
    var skipped: [Problem] = []
    /// Files that WERE taken but the import broke on (a video with no audio track): a failed
    /// note exists for each, so the list shows it.
    var failed: [Problem] = []

    init(created: Int = 0, skipped: [Problem] = [], failed: [Problem] = []) {
        self.created = created
        self.skipped = skipped
        self.failed = failed
    }

    var hasProblems: Bool { !skipped.isEmpty || !failed.isEmpty }
    var isEmpty: Bool { created == 0 && !hasProblems }

    mutating func merge(_ other: ImportReport) {
        created += other.created
        skipped += other.skipped
        failed += other.failed
    }

    mutating func addSkipped(_ name: String, _ reason: String) {
        skipped.append(Problem(name: name, reason: reason))
    }

    mutating func addFailed(_ name: String, _ reason: String) {
        failed.append(Problem(name: name, reason: reason))
    }

    // MARK: - Copy

    /// "Imported 2 notes · skipped 1 · failed 1". Never mentions a zero.
    var headline: String {
        var parts: [String] = []
        if created > 0 { parts.append("Imported \(created) \(created == 1 ? "note" : "notes")") }
        if !skipped.isEmpty { parts.append("skipped \(skipped.count)") }
        if !failed.isEmpty { parts.append("failed \(failed.count)") }
        guard let first = parts.first else { return "Nothing imported" }
        let rest = parts.dropFirst().joined(separator: " · ")
        return rest.isEmpty ? first : first + " · " + rest
    }

    /// One line per problem, failures first: `clip.mov: Video had no audio track`.
    /// At most `limit` lines, then "and N more".
    func bannerLines(limit: Int = 4) -> [String] {
        let all = (failed + skipped).map { "\($0.name): \($0.reason)" }
        guard all.count > limit else { return all }
        return Array(all.prefix(limit)) + ["and \(all.count - limit) more"]
    }

    /// The report to SHOW: nil when everything imported cleanly (the new notes are the
    /// confirmation) or nothing happened at all.
    var banner: ImportReport? { hasProblems ? self : nil }

    // MARK: - Reasons (the one wording both apps use)

    /// A video with no audio track becomes a failed note with exactly this title (C202).
    static let noAudioTrack = "Video had no audio track"
    static let formatNotSupported = "Video format not supported"
    static let unreadable = "The file could not be read"
    static let vanished = "The file was gone before it could be copied"
    static let pictureNotCopied = "The picture could not be read or converted"
    static let pictureInFolder = "Pictures inside a folder are not imported; drop them directly"
    static let textInFolder = "A .txt inside a folder is not a note; drop it directly"
    static let book = "Audiobooks and ePubs are added from the Books tab on the phone"
    static let pdfNotOnMac = "PDFs are not imported on the Mac yet"
    /// Q136: a dragged-in URL the Mac cannot make a link card of (mailto:, ftp:, ...).
    static let notAWebLink = "Skrift takes web links (http or https) only"

    /// Why `name` was skipped, from the kind it resolves to (`ImportKinds`) and the app that
    /// refused it. `onMac`: the Mac has no PDF door yet.
    static func skipReason(forName name: String, onMac: Bool) -> String {
        let ext = (name as NSString).pathExtension
        guard let kind = ImportKinds.kind(forExtension: ext) else {
            return ext.isEmpty ? "Skrift does not take files without an extension"
                               : "Skrift does not take .\(ext.lowercased()) files"
        }
        switch kind {
        case .book: return book
        case .document: return onMac ? pdfNotOnMac : unreadable
        case .image: return pictureNotCopied
        case .audio, .video, .text: return unreadable
        }
    }
}
