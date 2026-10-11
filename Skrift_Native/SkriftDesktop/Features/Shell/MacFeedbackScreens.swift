import Foundation

/// Q342: the names the Mac sends as the feedback `screen` (FeedbackKit `.feedbackScreen`).
/// Foundation-only so a host-less test can pin the vocabulary.
enum MacFeedbackScreens {
    static let notes = "Notes"
    static let note = "Note"
    static let review = "Review"
    static let settings = "Settings"
    static let names = "Names"

    /// The main window: the Review surface is its own screen; on the Notes surface the pane
    /// beside the list is "Note" when one is open, otherwise the list itself is the screen.
    static func main(isReview: Bool, hasOpenNote: Bool) -> String {
        if isReview { return review }
        return hasOpenNote ? note : notes
    }
}
