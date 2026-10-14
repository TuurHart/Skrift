import Foundation
import UniformTypeIdentifiers

/// The ONE share / drop dispatcher (C238, C198). Every extension item and every provider of
/// every item goes in (C67: WhatsApp ships a multi-select as several items, Signal as several
/// providers); one import plan or an honest refusal comes out. Pure: Foundation +
/// UniformTypeIdentifiers only, so the phone share extension, the phone app and the host-less
/// Mac test bundle compile the same file. The caller loads each provider's text / URL / file
/// name first; this decides what the share IS and what it keeps.
///
/// Order (C198), first match wins: audio → web URL → movie → image(s) → plain text → document.
/// - audio keeps every clip, every picture and every text, in selection order (C67, C125);
/// - web URL: a selected text beats the URL and the URL rides along (A3); a text that is only
///   a web link is itself a link capture (C69, D16);
/// - images keep their caption texts as the annotation (C141);
/// - no branch drops another provider's text (C141); an empty payload refuses (C75).
enum IngressDispatch {

    // MARK: Input

    /// One `NSItemProvider` as the caller resolved it.
    struct Provider: Codable, Equatable, Sendable {
        /// `registeredTypeIdentifiers`, in the provider's order.
        var uti: [String]
        /// The file representation's original name (or `suggestedName`); nil when not a file.
        var file: String?
        /// The loaded plain-text value, when the provider carries text inline.
        var text: String?
        /// The loaded URL value, when the provider carries a URL.
        var url: String?

        init(uti: [String], file: String? = nil, text: String? = nil, url: String? = nil) {
            self.uti = uti; self.file = file; self.text = text; self.url = url
        }
    }

    /// One `NSExtensionItem` (or one dropped file on the Mac: one item, one provider).
    struct Item: Codable, Equatable, Sendable {
        var providers: [Provider]
        /// `attributedContentText` / `attributedTitle` — Safari puts the page title here.
        var title: String?

        init(providers: [Provider], title: String? = nil) {
            self.providers = providers; self.title = title
        }
    }

    // MARK: Output

    enum Kind: String, Codable, Sendable {
        case audio, url, movie, image, text, document
    }

    /// One kept piece of the share, in selection order (item order, then provider order).
    enum Part: Equatable, Sendable {
        case clip(String)
        case picture(String)
        case text(String)
    }

    struct Plan: Equatable, Sendable {
        var kind: Kind
        /// Clips, pictures and texts interleaved exactly as the user selected them (C125).
        var parts: [Part]
        /// The movie (kind `.movie`) or the document (kind `.document`) file name.
        var file: String?
        /// The web link (kind `.url`, or riding along a selected text).
        var url: String?
        /// The page title, only beside a URL (no fetch).
        var title: String?

        var clips: [String] { parts.compactMap { if case .clip(let n) = $0 { return n } else { return nil } } }
        var pictures: [String] { parts.compactMap { if case .picture(let n) = $0 { return n } else { return nil } } }
        var texts: [String] { parts.compactMap { if case .text(let t) = $0 { return t } else { return nil } } }
    }

    enum Outcome: Equatable, Sendable {
        case plan(Plan)
        case refuse(String)
    }

    /// The refusal line (C75), same words as the share sheet's `.unsupported`.
    static let refusal = "Skrift can't import this"

    // MARK: Classification

    /// What one provider is. Audio is asked first so a WhatsApp voice note (audio + a URL
    /// representation) never becomes a link; an odd UTI (Signal `.aac`, Telegram `.ogg`) is
    /// rerouted by its file extension (C69).
    enum Role: Equatable, Sendable {
        case audio(String)
        case movie(String)
        case image(String)
        case webURL(String)
        case text(String)
        case document(String)
    }

    static func role(of p: Provider) -> Role? {
        let types = p.uti.compactMap { UTType($0) }
        func conforms(_ t: UTType) -> Bool { types.contains { $0.conforms(to: t) } }
        let ext = p.file.map { ($0 as NSString).pathExtension.lowercased() } ?? ""
        let fileKind = ImportKinds.kind(forExtension: ext)
        let name = p.file.flatMap { $0.isEmpty ? nil : $0 }

        if let name {
            if conforms(.audio) || fileKind == .audio { return .audio(name) }
            if conforms(.movie) || fileKind == .video { return .movie(name) }
            if conforms(.image) || fileKind == .image { return .image(name) }
        }
        if conforms(.url), !conforms(.fileURL), let link = webLink(p.url) { return .webURL(link) }
        if let t = p.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            if let link = webLink(t) { return .webURL(link) }          // a text that IS a link (D16)
            return .text(t)
        }
        // A text FILE (.txt / .md), a PDF, any other file: a document. What a text file becomes
        // is `ImportKinds.textRole`'s call downstream, the same as a Mac drop.
        if let name { return .document(name) }
        return nil
    }

    /// A lone http(s) link with a host, or nil. A sentence containing a link is text.
    static func webLink(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
              !t.contains(where: { $0.isWhitespace }),
              let u = URL(string: t), let scheme = u.scheme?.lowercased(),
              scheme == "http" || scheme == "https", u.host?.isEmpty == false
        else { return nil }
        return t
    }

    // MARK: Dispatch

    static func dispatch(_ items: [Item]) -> Outcome {
        let roles = items.flatMap { $0.providers.compactMap(role(of:)) }
        let title = items.lazy.compactMap { $0.title?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        var clips = 0, links: [String] = [], movies: [String] = [], pictures = 0,
            texts = 0, documents: [String] = []
        for r in roles {
            switch r {
            case .audio: clips += 1
            case .webURL(let l): links.append(l)
            case .movie(let n): movies.append(n)
            case .image: pictures += 1
            case .text: texts += 1
            case .document(let n): documents.append(n)
            }
        }
        let textParts: [Part] = roles.compactMap { if case .text(let t) = $0 { return .text(t) } else { return nil } }

        // 1. Audio: every clip, every picture, every text, in selection order.
        if clips > 0 {
            let parts: [Part] = roles.compactMap {
                switch $0 {
                case .audio(let n): return .clip(n)
                case .image(let n): return .picture(n)
                case .text(let t): return .text(t)
                default: return nil
                }
            }
            return .plan(Plan(kind: .audio, parts: parts))
        }
        // 2. Web URL: a selected text wins, the link rides along.
        if let link = links.first {
            return .plan(Plan(kind: texts > 0 ? .text : .url, parts: textParts, url: link, title: title))
        }
        // 3. Movie (before images, so a poster frame is not an image capture). Texts kept.
        if let movie = movies.first {
            return .plan(Plan(kind: .movie, parts: textParts, file: movie))
        }
        // 4. Image(s): one note; caption texts are the annotation above the pictures (C141).
        if pictures > 0 {
            let parts: [Part] = roles.compactMap {
                switch $0 {
                case .image(let n): return .picture(n)
                case .text(let t): return .text(t)
                default: return nil
                }
            }
            return .plan(Plan(kind: .image, parts: parts))
        }
        // 5. Plain text: every text, in order.
        if texts > 0 { return .plan(Plan(kind: .text, parts: textParts)) }
        // 6. Document.
        if let doc = documents.first { return .plan(Plan(kind: .document, parts: textParts, file: doc)) }
        // Nothing usable: never a husk (C75).
        return .refuse(refusal)
    }
}
