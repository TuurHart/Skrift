import Foundation

/// What the user sees when the SwiftData / CloudKit store would not open (C115 area:
/// one decision, pure, testable). The app shows a full-screen "couldn't open your notes"
/// state instead of crashing, and NEVER deletes or recreates the store on its own.
struct StoreStartFailure: Equatable {
    let title: String
    /// The underlying error, verbatim, so the user can read or report it.
    let errorText: String
    let hint: String
}

enum StoreStartPolicy {
    static let title = "Skrift couldn't open your notes"

    private static let generalHint =
        "Your notes were not touched. Close Skrift and open it again. If this keeps happening, "
        + "check that iCloud has free storage (Settings, your name, iCloud) and that this iPhone "
        + "has free space."
    private static let spaceHint =
        "Your notes were not touched. This iPhone looks out of storage space. Free some space, "
        + "then close Skrift and open it again."

    /// nil error = the store opened = no failure state. Pure: same input, same output.
    static func decide(_ error: Error?) -> StoreStartFailure? {
        guard let error else { return nil }
        let ns = error as NSError
        let text = "\(error)"
        let lower = text.lowercased()
        let outOfSpace = (ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError)
            || lower.contains("no space left") || lower.contains("out of space")
        return StoreStartFailure(title: title, errorText: text, hint: outOfSpace ? spaceHint : generalHint)
    }
}
