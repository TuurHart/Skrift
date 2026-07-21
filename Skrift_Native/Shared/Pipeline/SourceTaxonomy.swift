import Foundation

/// The unified source taxonomy — ONE copy of every source kind's glyph + label
/// (CLAUDE.md "Unified source taxonomy"; single-sourced 2026-07-21 after a
/// third hardcoded copy appeared). The Mac's queue rows, its quiet rows, and
/// the phone's row/chip glyphs all read THESE — a symbol renamed here renames
/// everywhere, and nowhere else.
enum SourceKind: Equatable {
    case audiobookQuote, video, captureURL, captureImage, captureText,
         captureFile, captureOther, appleNote, voiceMemo

    /// SF Symbol.
    var glyph: String {
        switch self {
        case .audiobookQuote: return "book.closed.fill"
        case .video:          return "video.fill"
        case .captureURL:     return "link"
        case .captureImage:   return "photo"
        case .captureText:    return "text.quote"
        case .captureFile:    return "doc"
        case .captureOther:   return "square.and.arrow.down"
        case .appleNote:      return "note.text"
        case .voiceMemo:      return "mic.fill"
        }
    }

    /// Human label (detail "source" lines, chips).
    var label: String {
        switch self {
        case .audiobookQuote: return "Audiobook quote"
        case .video:          return "Video"
        case .captureURL:     return "Link"
        case .captureImage:   return "Image"
        case .captureText:    return "Text"
        case .captureFile:    return "File"
        case .captureOther:   return "Capture"
        case .appleNote:      return "Apple Note"
        case .voiceMemo:      return "Voice memo"
        }
    }

    /// Kind of a synced `Memo` — priority: audiobook quote → video → capture
    /// subtype → audio/no-audio (mirrors the Mac's `PipelineFile` descriptor;
    /// a book capture and a video both carry audio, so type alone can't tell).
    static func of(_ memo: Memo) -> SourceKind {
        if let book = memo.metadata?.bookTitle, !book.isEmpty { return .audiobookQuote }
        if let data = memo.metadataData,
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           obj["mediaSource"] as? String == "video" { return .video }
        if let shared = SharedContent.decode(from: memo.metadataData) {
            switch shared.type {
            case .url:   return .captureURL
            case .image: return .captureImage
            case .text:  return .captureText
            case .file:  return .captureFile
            }
        }
        return memo.audioFilename.isEmpty ? .appleNote : .voiceMemo
    }
}
