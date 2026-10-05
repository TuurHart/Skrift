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
    static func of(_ memo: Memo) -> SourceKind {
        of(metadataData: memo.metadataData, sharedContentData: memo.sharedContentData,
           hasAudio: !memo.audioFilename.isEmpty)
    }

    /// The classifier over a memo's raw facts (Q320). Content-keyed cache: the three inputs are the
    /// whole answer, so any edit (local or CloudKit merge) is a new key and nothing goes stale.
    /// Building a list of titles used to JSON-parse two blobs per note per call. Callable off the
    /// main actor (NSCache is thread-safe).
    static func of(metadataData: Data?, sharedContentData: Data?, hasAudio: Bool) -> SourceKind {
        let key = KindKey(metadataData, sharedContentData, hasAudio)
        if let hit = kindCache.object(forKey: key) { return hit.kind }
        kindMisses.add()
        let meta = metadataData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let shared: SharedContent? = Memo.decodeJSON(sharedContentData)
        let kind = classify(hasBook: Memo.metadata(from: metadataData)?.bookTitle.map { !$0.isEmpty } ?? false,
                            media: mediaMarker(in: meta),
                            sharedType: shared?.type.rawValue,
                            hasAudio: hasAudio)
        kindCache.setObject(KindBox(kind), forKey: key)
        return kind
    }

    /// How many times the classifier actually ran (tests read this; harmless in production).
    static var classifyRuns: Int { kindMisses.value }

    private final class KindBox { let kind: SourceKind; init(_ k: SourceKind) { kind = k } }
    private final class KindKey: NSObject {
        let metadata: Data?, shared: Data?, hasAudio: Bool
        init(_ m: Data?, _ s: Data?, _ a: Bool) { metadata = m; shared = s; hasAudio = a }
        override var hash: Int {
            var h = Hasher()
            h.combine(metadata); h.combine(shared); h.combine(hasAudio)
            return h.finalize()
        }
        override func isEqual(_ object: Any?) -> Bool {
            guard let o = object as? KindKey else { return false }
            return metadata == o.metadata && shared == o.shared && hasAudio == o.hasAudio
        }
    }
    private static let kindCache: NSCache<KindKey, KindBox> = {
        let c = NSCache<KindKey, KindBox>()
        c.countLimit = 4096
        return c
    }()
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func add() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }
    private static let kindMisses = Counter()
}
