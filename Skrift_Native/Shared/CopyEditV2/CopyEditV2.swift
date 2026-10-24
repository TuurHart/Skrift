import Foundation
import os

/// Copy-edit v2 (Q424): the ONE copy-edit both polishers run — the Mac's `EnhancementService`
/// and the iPad's `PolishV2` (Q426); v1 was deleted after the `v1-copyedit` tag (Q427, C2).
/// Pure: the model is a closure, so the corpus harness replays recorded outputs MLX-free.
///
/// One call: quote held back (C29) → links escrowed to their shown text and pictures held by
/// paragraph index (C29, C30) → the model, with the input-sized budget (C32) → guards: truncation
/// (C32), shrink (C33), post-conditions (C177, C35) → the spoken-wall break and the paragraph
/// ledger (C34) → links back (C31) → pictures back after the same-index paragraph (C30) → the
/// quote byte-asserted (C31). Every failed guard ships the ORIGINAL body, unedited.
enum CopyEditV2 {
    /// One model call: prompt, text, token cap → the model's raw output.
    typealias Generate = @Sendable (_ prompt: String, _ text: String, _ maxTokens: Int) async throws -> String

    static let log = Logger(subsystem: "com.skrift.copyedit", category: "copyedit-v2")

    /// Why a copy-edit shipped the unedited body.
    enum Fallback: String, Sendable, Equatable {
        case empty = "the model returned nothing"
        case truncated = "output at >= 95% of the token cap (C32)"
        case shrank = "output under 55% of the input words (C33)"
        case newProperNoun = "a proper noun absent from the input (C177)"
        case languageFlip = "the language flipped (C177, C35)"
        case nameOrNumberLost = "a name or a number was lost (C35, D209)"
        case paragraphsLost = "fewer paragraphs than the input (C34)"
        case typedReparagraphed = "a typed note was re-paragraphed (C34)"
        case linkLost = "a link did not survive (C31)"
        case quoteChanged = "the quote block changed (C31)"
        case respelled = "a word was respelled: his spelling stays (D215)"
        case sentenceLost = "a short note lost a whole sentence (D215)"
        case formattingLost = "a bold or italic span did not survive (D215)"
    }

    /// The paragraph ledger (C34): text paragraphs in → from the model → shipped.
    struct Ledger: Equatable, Sendable {
        var input: Int, model: Int, shipped: Int
        var line: String { "in \(input) → model \(model) → shipped \(shipped)" }
    }

    struct Result: Equatable, Sendable {
        /// The body to ship: edited, or byte-identical to the input when `fallback` is set.
        let text: String
        let fallback: Fallback?
        let ledger: Ledger?
        let calledModel: Bool
    }

    // MARK: - the call

    /// Copy-edit `body` (the RAW body: links, picture markers, a leading quote). `spoken` = the
    /// words were spoken; a typed note is never re-paragraphed (C34, D7).
    static func copyEdit(_ body: String, spoken: Bool, prompt: String, generate: Generate) async throws -> Result {
        guard let split = QuoteProtection.splitLeadingQuote(body) else {
            return try await editProse(body, spoken: spoken, prompt: prompt, generate: generate)
        }
        // A quote capture: the quote never reaches the model; only the ramble is edited (C29).
        guard !split.ramble.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Result(text: body, fallback: nil, ledger: nil, calledModel: false)
        }
        let ramble = try await editProse(split.ramble, spoken: spoken, prompt: prompt, generate: generate)
        if let why = ramble.fallback, [.truncated, .shrank, .linkLost].contains(why) {   // C31-C33: the whole body
            return Result(text: body, fallback: ramble.fallback, ledger: ramble.ledger, calledModel: ramble.calledModel)
        }
        let joined = QuoteProtection.reassemble(quote: split.quote, ramble: ramble.text)
        guard QuoteProtection.leadingQuoteIntact(original: body, edited: joined) else {
            log.warning("copy-edit v2: \(Fallback.quoteChanged.rawValue, privacy: .public) — unedited")
            return Result(text: body, fallback: .quoteChanged, ledger: ramble.ledger, calledModel: true)
        }
        return Result(text: joined, fallback: ramble.fallback, ledger: ramble.ledger, calledModel: ramble.calledModel)
    }

    private static func editProse(_ text: String, spoken: Bool, prompt: String,
                                  generate: Generate) async throws -> Result {
        let held = Held(text)
        // D215: checkbox and heading lines, and a typed note's list lines, never reach the model;
        // nor does bold/italic markup (Q501) — only the words inside it.
        let lines = HeldLines(held.prose, typed: !spoken)
        let emphasis = HeldEmphasis(lines.prose)
        let input = emphasis.prose
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Result(text: text, fallback: nil, ledger: nil, calledModel: false)   // pictures / held lines only
        }
        let cap = PolishPrompts.copyEditTokenBudget(forInput: input)
        let out = try await generate(PolishPrompts.keepingSpelling(prompt), input, cap)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let inParas = paragraphs(input).count, modelParas = paragraphs(out).count
        /// C31 / C32 / C33: the ORIGINAL body, byte for byte.
        func unedited(_ why: Fallback) -> Result {
            log.warning("copy-edit v2: \(why.rawValue, privacy: .public) — unedited (\(input.count) → \(out.count) chars)")
            return Result(text: text, fallback: why,
                          ledger: Ledger(input: inParas, model: modelParas, shipped: inParas), calledModel: true)
        }
        /// A failed post-condition (C177, C35, C34): the author's words unedited, still shaped by
        /// the deterministic rules that edit no word — a spoken wall broken (C34), each picture its
        /// own paragraph by index (C30).
        func uneditedWords(_ why: Fallback) -> Result {
            let shaped = spoken ? PolishPrompts.ensureParagraphs(input) : input
            guard let marked = emphasis.putBack(shaped),
                  let linked = held.reattachLinks(lines.putBack(marked)) else { return unedited(why) }
            log.warning("copy-edit v2: \(why.rawValue, privacy: .public) — the words ship unedited")
            return Result(text: held.placePictures(linked), fallback: why,
                          ledger: Ledger(input: inParas, model: modelParas, shipped: paragraphs(shaped).count),
                          calledModel: true)
        }
        if out.isEmpty { return uneditedWords(.empty) }
        if PolishPrompts.looksTruncated(output: out, cap: cap) { return unedited(.truncated) }
        if PolishPrompts.lostTooMuch(input: input, output: out) { return unedited(.shrank) }
        if let why = Gate.check(input: input, output: out) { return uneditedWords(why) }
        // C34: the deterministic wall break is for SPOKEN text only; a typed note keeps its own.
        let shaped = spoken ? PolishPrompts.ensureParagraphs(out) : out
        let shipped = paragraphs(shaped).count
        if spoken, shipped < inParas { return uneditedWords(.paragraphsLost) }
        if !spoken, shipped != inParas { return uneditedWords(.typedReparagraphed) }
        guard let marked = emphasis.putBack(shaped) else { return uneditedWords(.formattingLost) }
        guard let linked = held.reattachLinks(lines.putBack(marked)) else { return unedited(.linkLost) }
        let ledger = Ledger(input: inParas, model: modelParas, shipped: shipped)
        log.log("copy-edit v2 paragraphs: \(ledger.line, privacy: .public) (pictures: \(held.pictures.count), held line blocks: \(lines.blocks.count))")
        return Result(text: held.placePictures(linked), fallback: nil, ledger: ledger, calledModel: true)
    }

    /// Blank-line-separated blocks, trimmed, the empty ones dropped.
    static func paragraphs(_ s: String) -> [String] {
        s.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - what the model sees (C29, C178)

    /// The prose a model call reads: every `[[…]]` link escrowed to the text it shows, every
    /// picture marker out. Title and summary read this too — no `[[ ]]` reaches the model (C178).
    static func prose(_ text: String) -> String { Held(text).prose }

    /// A body with its links escrowed and its pictures held by paragraph index.
    struct Held {
        struct Link { let token: String; let shown: String; let rewrap: (String) -> String }
        /// A picture marker and the number of text paragraphs before it (C30). A marker inline
        /// in text paragraph i belongs to that paragraph and returns after it.
        struct Picture: Equatable { let marker: String; let after: Int }

        let prose: String
        let links: [Link]
        let pictures: [Picture]

        static let linkRegex = try! NSRegularExpression(pattern: #"\[\[([^\]\n]+)\]\]"#)
        static let memoRegex = try! NSRegularExpression(pattern: #"^memo:([0-9A-Fa-f\-]{36})\|([^\]\n|]*)$"#)
        /// Pictures and `[[vid_/file_NNN]]` attachments: held alike, by paragraph index (C30, Q469).
        static let pictureRegex = AttachmentMarkerEscrow.anyMarkerRegex

        init(_ text: String) {
            // 1. Links → the text they show. A memo-link shows its title snapshot (v1's escrow,
            //    byte for byte); a wikilink `[[Target|shown]]` / `[[Target]]` shows `shown` / `Target`.
            let ns = NSMutableString(string: text)
            var links: [Link] = []
            for m in Self.linkRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
                let inner = (text as NSString).substring(with: m.range(at: 1))
                if inner.range(of: #"^(?:img|vid|file)_\d+$"#, options: .regularExpression) != nil { continue }   // a picture or attachment
                let link: Link
                let n = inner as NSString
                if let mm = Self.memoRegex.firstMatch(in: inner, range: NSRange(location: 0, length: n.length)) {
                    let id = n.substring(with: mm.range(at: 1)), title = n.substring(with: mm.range(at: 2))
                    link = Link(token: "[[\(inner)]]", shown: title.isEmpty ? "Untitled" : title,
                                rewrap: { "[[memo:\(id)|\($0)]]" })
                } else if let bar = inner.firstIndex(of: "|") {
                    let target = String(inner[..<bar]), shown = String(inner[inner.index(after: bar)...])
                    link = Link(token: "[[\(inner)]]", shown: shown, rewrap: { "[[\(target)|\($0)]]" })
                } else {
                    link = Link(token: "[[\(inner)]]", shown: inner,
                                rewrap: { $0 == inner ? "[[\(inner)]]" : "[[\(inner)|\($0)]]" })
                }
                ns.replaceCharacters(in: m.range, with: link.shown)
                links.insert(link, at: 0)
            }
            let escrowed = ns as String
            self.links = links

            // 2. Pictures by paragraph index (C30) — the 6-word anchors are gone.
            var pictures: [Picture] = []
            var textParas = 0
            for block in escrowed.components(separatedBy: "\n\n") {
                let r = NSRange(location: 0, length: (block as NSString).length)
                let markers = Self.pictureRegex.matches(in: block, range: r).map { (block as NSString).substring(with: $0.range) }
                let rest = Self.pictureRegex.stringByReplacingMatches(in: block, range: r, withTemplate: "")
                if rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    pictures += markers.map { Picture(marker: $0, after: textParas) }
                } else {
                    textParas += 1
                    pictures += markers.map { Picture(marker: $0, after: textParas) }
                }
            }
            self.pictures = pictures
            // The model input: a marker leaves a space and the seam is tidied, newlines kept
            // (the input v1 recorded, so the replayed outputs still match).
            self.prose = pictures.isEmpty ? escrowed : Self.tidy(Self.pictureRegex.stringByReplacingMatches(
                in: escrowed, range: NSRange(location: 0, length: (escrowed as NSString).length), withTemplate: " "))
        }

        /// Horizontal runs → one space, no space hugging a break, ≥3 breaks → one blank line.
        static func tidy(_ s: String) -> String {
            s.replacingOccurrences(of: #"[^\S\n]+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #" ?\n ?"#, with: "\n", options: .regularExpression)
                .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// Each link back around the first case-insensitive match of its shown text, in order;
        /// the edited casing is kept. nil = a link's text did not survive (C31).
        func reattachLinks(_ edited: String) -> String? {
            let ns = NSMutableString(string: edited)
            var from = 0
            for link in links {
                let r = ns.range(of: link.shown, options: .caseInsensitive,
                                 range: NSRange(location: from, length: ns.length - from))
                guard r.location != NSNotFound else { return nil }
                let wrapped = link.rewrap(ns.substring(with: r))
                ns.replaceCharacters(in: r, with: wrapped)
                from = r.location + (wrapped as NSString).length
            }
            return ns as String
        }

        /// Each picture as its own paragraph after the same-index text paragraph of `edited`,
        /// clamped to the end (C30, C10).
        func placePictures(_ edited: String) -> String {
            guard !pictures.isEmpty else { return edited }
            let paras = CopyEditV2.paragraphs(edited)
            var out: [String] = []
            for k in 0...paras.count {
                if k > 0 { out.append(paras[k - 1]) }
                out += pictures.filter { Swift.min($0.after, paras.count) == k }.map(\.marker)
            }
            return out.joined(separator: "\n\n")
        }
    }
}
