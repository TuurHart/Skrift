import Foundation

extension Notification.Name {
    /// Posted when an add folded a person into an existing row with the same full name
    /// (case-insensitive, C254/R62). `userInfo[RosterMergeNotice.canonicalKey]` = the surviving
    /// canonical. Both apps show `RosterMergeNotice.message` in their toast.
    static let namesMergedDuplicate = Notification.Name("skrift.namesMergedDuplicate")
}

/// Same full name = same person (C254). Every add path (Settings on both apps, the speaker
/// assign sheet, the CloudKit names merge) folds a same-name person into the existing row and
/// raises this notice, so the merge is never silent.
enum RosterMergeNotice {
    static let canonicalKey = "canonical"

    /// "Merged into John Smith".
    static func message(into canonical: String) -> String {
        "Merged into \(NamesMerge.bareName(canonical))"
    }

    /// The toast line for a posted notice, nil for any other notification.
    static func message(from note: Notification) -> String? {
        guard note.name == .namesMergedDuplicate,
              let c = note.userInfo?[canonicalKey] as? String else { return nil }
        return message(into: c)
    }

    /// Raise the notice. Call it OUTSIDE any `NamesStore` lock: observers re-read the roster.
    static func post(into canonical: String, center: NotificationCenter = .default) {
        center.post(name: .namesMergedDuplicate, object: nil, userInfo: [canonicalKey: canonical])
    }
}
