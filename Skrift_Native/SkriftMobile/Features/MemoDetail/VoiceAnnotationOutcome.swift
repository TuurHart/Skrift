import Foundation

/// C274 / R87: what happens to a voice annotation's clip once its transcription is back.
/// Text appends to the note and the clip is consumed (the dictation model). An empty
/// transcript keeps the clip and says "No words heard" until the user discards it
/// or tries again; the success haptic fires only when words landed.
enum VoiceAnnotationOutcome: Equatable {
    case append(String)
    case keepNoWordsHeard

    /// The line shown for a kept clip, in the secondary-text style.
    static let noWordsHeardLine = "No words heard"

    /// `live` is the live caption, `full` the full-quality pass (nil when it threw).
    /// The full pass wins when it has words; the live caption is the fallback.
    static func resolve(live: String, full: String?) -> VoiceAnnotationOutcome {
        let l = live.trimmingCharacters(in: .whitespacesAndNewlines)
        let f = (full ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = f.isEmpty ? l : f
        return text.isEmpty ? .keepNoWordsHeard : .append(text)
    }

    /// Only a transcript with words may delete its clip.
    var deletesClip: Bool {
        if case .append = self { return true }
        return false
    }

    /// The success haptic is for words that landed, never for an empty transcript.
    var firesSuccessHaptic: Bool { deletesClip }
}
