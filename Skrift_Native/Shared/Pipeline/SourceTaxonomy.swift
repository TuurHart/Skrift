import Foundation

/// The unified source taxonomy — ONE copy of every source kind's glyph + label
/// (CLAUDE.md "Unified source taxonomy"; single-sourced 2026-07-21 after a
/// third hardcoded copy appeared). The Mac's queue rows, its quiet rows, and
/// the phone's row/chip glyphs all read THESE — a symbol renamed here renames
/// everywhere, and nowhere else.
enum SourceKind: Equatable {
    case audiobookQuote, video, captureURL, captureImage, captureText,
         captureFile, captureOther, appleNote, voiceMemo, typedNote

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
        case .typedNote:      return "square.and.pencil"
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
        case .typedNote:      return "Note"
        }
    }

    /// The Mac capture strip's line: the kind label, plus the domain when a link has one
    /// ("Link · swiftwithmajid.com"). The strip used to hardcode its own "Shared link", and the
    /// phone chip another: three spellings of one fact. Both now read `label`.
    func stripLabel(domain: String?) -> String {
        guard let domain, !domain.isEmpty else { return label }
        return "\(label) · \(domain)"
    }

    /// Row-title fallback for a note with no title and no words yet. A typed
    /// note says "Note" — "Voice note" on something you wrote reads as a bug
    /// (mocks/mac-new-note.html m3); everything else keeps the historic copy.
    var emptyTitleFallback: String {
        self == .typedNote ? "Note" : "Voice note"
    }

    /// The media marker inside a metadata JSON object. Two spellings exist for one fact:
    /// the phone's `MemoMetadata` encodes `sourceType` (no CodingKeys; `Source.video`),
    /// the Mac author and `Memo.newTyped` write `mediaSource` ("video" / "typed"). Both are
    /// read, `mediaSource` first (C71 glyph key drift).
    static func mediaMarker(in json: [String: Any]?) -> String? {
        guard let json else { return nil }
        for key in ["mediaSource", "sourceType"] {
            if let v = (json[key] as? String)?.trimmingCharacters(in: .whitespaces), !v.isEmpty { return v }
        }
        return nil
    }

    /// THE classifier: every surface (phone row/pane/chips, iPad Journal, the Mac projection
    /// and the Mac's `PipelineFile` rows) reduces its own storage to these facts and calls
    /// this. Priority: audiobook quote, video, typed, capture subtype, audio/no-audio.
    /// - `sharedType`: the capture's `type` string (nil / unknown means not a typed capture)
    /// - `isCaptureRow`: the row is already known to be a capture (Mac `.capture` rows), so
    ///   an unknown subtype reads as `.captureOther` rather than falling through.
    static func classify(hasBook: Bool, media: String?, sharedType: String?,
                         isCaptureRow: Bool = false, hasAudio: Bool) -> SourceKind {
        if hasBook { return .audiobookQuote }
        if media == "video" { return .video }
        // A note born typed (the Mac's pencil/Cmd-N verb, `MacMemoAuthor.typedNote`).
        // Without the marker a no-audio memo reads as an Apple Note import below.
        if media == "typed" { return .typedNote }
        // A Mac picture-only import carries no `sharedContent`; its marker says what it is.
        if media == "image" { return .captureImage }
        switch sharedType {
        case "url":   return .captureURL
        case "image": return .captureImage
        case "text":  return .captureText
        case "file":  return .captureFile
        default:      break
        }
        if isCaptureRow { return .captureOther }
        return hasAudio ? .voiceMemo : .appleNote
    }

    /// Kind of a synced `Memo`. A capture is the phone's bare `Memo.sharedContentData`
    /// (`CaptureInboxDrainer`); a video is `sourceType` OR `mediaSource` in `metadataData`.
    /// The `{"sharedContent":...}` wrapper inside `metadataData` is still tolerated (the shape
    /// the pre-Q138 `SourceTaxonomyTests` seeds); the bare blob wins.
    static func of(_ memo: Memo) -> SourceKind {
        let meta = memo.metadataData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let shared = memo.sharedContent ?? SharedContent.decode(from: memo.metadataData)
        return classify(hasBook: memo.metadata?.bookTitle.map { !$0.isEmpty } ?? false,
                        media: mediaMarker(in: meta),
                        sharedType: shared?.type.rawValue,
                        hasAudio: !memo.audioFilename.isEmpty)
    }
}
