import Foundation

/// Name-linking — the LAST deterministic pipeline step, non-blocking. Unambiguous
/// aliases auto-link (first mention → `[[Canonical]]`, rest → short name); an alias
/// that maps to 2+ people is left plain and recorded as an `AmbiguousOccurrence`
/// for the review-time resolver. Pure (text + people → text + ambiguities), so it
/// host-tests without a backend. Ported from `backend/services/sanitisation.py`.
/// Fixed settings match DEFAULT_SETTINGS.sanitisation (whole_word, mode=first,
/// avoid_inside_links, preserve_possessive, wiki style).
///
/// First-mention-only holds even when the INPUT already carries canonical links:
/// Mac-diarized conversations arrive with `**[[Person]]:**` on EVERY turn header
/// (the 2026-06-10 "brackets on every mention" bug) — the earliest existing link
/// counts as the first mention, every later copy is demoted to the short name, and
/// no new link is introduced for that person. Only links matching a known person's
/// canonical are touched (`[[img_NNN]]` markers / place links pass through).
enum Sanitiser {
    struct Result: Equatable, Sendable {
        let sanitised: String
        let ambiguous: [AmbiguousOccurrence]
    }

    private static let wholeWord = true
    private static let avoidInside = true
    private static let preservePossessive = true
    private static let possPattern = "(?<poss>(?:'s|’s)?)"

    /// `neverLink` carries the note's persisted "Unlink all mentions in this note"
    /// choices (`PipelineFile.unlinkedNames`, canonical keys — bare or `[[bracketed]]`,
    /// matched case-insensitively). Such a person is treated as absent from the names
    /// DB for THIS note: never linked, never demoted to the short name, and never
    /// offered as an ambiguity candidate — so re-processing can't re-link them here.
    static func process(text inputText: String, people: [Person], neverLink: Set<String> = []) -> Result {
        var text = inputText
        let skip = Set(neverLink.map { NamesMerge.keyName($0).trimmingCharacters(in: .whitespaces).lowercased() })
        let live = people.filter {
            !$0.isDeleted && !skip.contains(NamesMerge.keyName($0.canonical).trimmingCharacters(in: .whitespaces).lowercased())
        }

        var aliasMap: [String: [Person]] = [:]
        for p in live {
            for a in p.aliases {
                let al = a.trimmingCharacters(in: .whitespaces).lowercased()
                if !al.isEmpty { aliasMap[al, default: []].append(p) }
            }
        }
        let ambiguousAliases = Set(aliasMap.filter { $0.value.count >= 2 }.keys)

        // Record ambiguous occurrences (left unlinked, resolved at review).
        var ambiguous: [AmbiguousOccurrence] = []
        for alias in ambiguousAliases.sorted() {
            let candidates = aliasMap[alias] ?? []
            guard let rx = wordRegex(alias) else { continue }
            for m in rx.matches(in: text, range: fullRange(text)) {
                let loc = m.range.location
                if avoidInside && !notInsideLink(text, loc) { continue }
                ambiguous.append(AmbiguousOccurrence(
                    alias: alias,
                    offset: loc,
                    length: m.range.length,
                    contextBefore: nsSub(text, max(0, loc - 40), loc),
                    contextAfter: nsSub(text, loc + m.range.length, min(nsLen(text), loc + m.range.length + 40)),
                    candidates: candidates.map {
                        NameCandidate(id: $0.canonical, canonical: $0.canonical, short: shortName(for: $0))
                    }
                ))
            }
        }

        // Link unambiguous aliases, person by person (sorted by canonical).
        for p in live.sorted(by: { NamesMerge.keyName($0.canonical).lowercased() < NamesMerge.keyName($1.canonical).lowercased() }) {
            let aliases = p.aliases
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !ambiguousAliases.contains($0.lowercased()) }
            guard !aliases.isEmpty else { continue }

            let linkText = "[[\(NamesMerge.keyName(p.canonical))]]"
            let short = shortName(for: p)
            let patterns = aliases.compactMap { wordRegex($0) }

            // When the text ALREADY carries this person's canonical link (e.g. every
            // diarized turn header), that earliest link IS the first mention: demote
            // the later copies to the short name and add no new link. Otherwise the
            // first eligible occurrence across the person's aliases becomes the link.
            let existingLinks = occurrences(of: linkText, in: text)
            if existingLinks.isEmpty {
                var earliest: (range: NSRange, poss: String)?
                for rx in patterns {
                    guard let m = rx.firstMatch(in: text, range: fullRange(text)) else { continue }
                    if avoidInside && !notInsideLink(text, m.range.location) { continue }
                    if earliest == nil || m.range.location < earliest!.range.location {
                        earliest = (m.range, possText(m, in: text))
                    }
                }
                guard let first = earliest else { continue }
                text = nsReplace(text, first.range, with: linkText + first.poss)
            } else if !short.isEmpty {
                for r in existingLinks.dropFirst().reversed() {
                    text = nsReplace(text, r, with: short)
                }
            }

            // Remaining mentions of any alias → the short name (skip inside links).
            guard !short.isEmpty else { continue }
            for rx in patterns {
                let matches = rx.matches(in: text, range: fullRange(text))
                for m in matches.reversed() {
                    if avoidInside && !notInsideLink(text, m.range.location) { continue }
                    text = nsReplace(text, m.range, with: short + possText(m, in: text))
                }
            }
        }

        return Result(sanitised: text, ambiguous: ambiguous)
    }

    /// Apply review-time choices for ambiguous aliases to the (already sanitised)
    /// body. Each decision: alias + canonical (+ optional short). First remaining
    /// plain occurrence → `[[Canonical]]`, rest → short. Ported from
    /// `apply_resolved_names`.
    static func applyResolvedNames(text inputText: String, decisions: [(alias: String, canonical: String, short: String?)]) -> String {
        var text = inputText
        for d in decisions {
            let alias = d.alias.trimmingCharacters(in: .whitespaces)
            let canon = d.canonical.trimmingCharacters(in: .whitespaces)
            guard !alias.isEmpty, !canon.isEmpty, let rx = wordRegex(alias) else { continue }
            let linkText = (canon.hasPrefix("[[") && canon.hasSuffix("]]")) ? canon : "[[\(canon)]]"
            let core = NamesMerge.keyName(linkText)
            let short = (d.short?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 }
                ?? (core.split(separator: " ").first.map(String.init) ?? alias)

            let eligible = rx.matches(in: text, range: fullRange(text))
                .filter { !avoidInside || notInsideLink(text, $0.range.location) }
            guard !eligible.isEmpty else { continue }
            // The body may already carry the canonical link (turn headers / a
            // pre-linked mention) — then every plain occurrence is a LATER mention.
            let alreadyLinked = !occurrences(of: linkText, in: text).isEmpty
            for (i, m) in eligible.enumerated().reversed() {
                let replacement = ((i == 0 && !alreadyLinked) ? linkText : short) + possText(m, in: text)
                text = nsReplace(text, m.range, with: replacement)
            }
        }
        return text
    }

    /// Apply per-occurrence review choices — distinct people for distinct mentions of
    /// the SAME alias (the "two Jacks" case). `byAlias[alias]` is the ordered list of
    /// choices, one per plain occurrence (canonical nil = leave plain). For each alias
    /// the first mention of a given canonical becomes `[[Canonical]]`, later mentions of
    /// that same canonical become its short name. Order-based against the current body,
    /// so it's robust to earlier offset shifts.
    static func applyResolvedOccurrences(text inputText: String,
                                         byAlias: [String: [(canonical: String?, short: String?)]]) -> String {
        var text = inputText
        for (alias, choices) in byAlias {
            let a = alias.trimmingCharacters(in: .whitespaces)
            guard !a.isEmpty, let rx = wordRegex(a) else { continue }
            let eligible = rx.matches(in: text, range: fullRange(text))
                .filter { !avoidInside || notInsideLink(text, $0.range.location) }
            guard !eligible.isEmpty else { continue }

            // Forward pass: decide each occurrence's replacement (first-link per canonical).
            var introduced = Set<String>()
            var replacements: [(range: NSRange, repl: String)] = []
            for (i, m) in eligible.enumerated() {
                guard i < choices.count, let canonRaw = choices[i].canonical else { continue }  // plain → skip
                let canon = canonRaw.trimmingCharacters(in: .whitespaces)
                guard !canon.isEmpty else { continue }
                let linkText = (canon.hasPrefix("[[") && canon.hasSuffix("]]")) ? canon : "[[\(canon)]]"
                let core = NamesMerge.keyName(linkText)
                let short = (choices[i].short?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (core.split(separator: " ").first.map(String.init) ?? a)
                // A canonical the body already links (e.g. a turn header) counts as
                // introduced — its plain mentions all get the short name.
                let isFirst = !introduced.contains(core) && occurrences(of: linkText, in: text).isEmpty
                introduced.insert(core)
                replacements.append((m.range, (isFirst ? linkText : short) + possText(m, in: text)))
            }
            // Apply in reverse so earlier ranges stay valid.
            for r in replacements.sorted(by: { $0.range.location > $1.range.location }) {
                text = nsReplace(text, r.range, with: r.repl)
            }
        }
        return text
    }

    /// Plain (not-inside-`[[ ]]`) whole-word occurrences of `alias` in `text`, in
    /// reading order — the clickable ambiguous mentions for the inline resolver UI.
    /// Uses the SAME matching as `process`/`applyResolvedOccurrences` (whole-word,
    /// possessive-aware, link-skipping), so the i-th occurrence here is the i-th
    /// `eligible` match there → the UI's per-occurrence choices line up exactly with
    /// the order-based apply. Each range covers the alias (+ any trailing `'s`).
    static func plainOccurrences(of alias: String, in text: String) -> [NSRange] {
        let a = alias.trimmingCharacters(in: .whitespaces)
        guard !a.isEmpty, let rx = wordRegex(a) else { return [] }
        return rx.matches(in: text, range: fullRange(text))
            .map { $0.range }
            .filter { !avoidInside || notInsideLink(text, $0.location) }
    }

    // MARK: - Partial (in-flight) per-occurrence apply — the instant-apply resolver

    /// One occurrence's in-flight choice while the user is still clicking mentions
    /// (the "different people" flow). `.undecided` keeps the mention verbatim (it
    /// stays plain + highlighted); `.plain` keeps it verbatim too (deliberately left
    /// as text); `.person` links/shortens it like `applyResolvedOccurrences` would.
    enum PartialChoice: Equatable, Sendable {
        case undecided
        case plain
        case person(canonical: String, short: String?)
    }

    /// `applyPartialOccurrences` output: the rendered text + where every input
    /// occurrence landed in it. `ranges[alias][i]` is the rendered NSRange of the
    /// i-th plain occurrence of that alias in the INPUT text (the same enumeration
    /// as `plainOccurrences`), covering whatever it became — verbatim alias,
    /// `[[Canonical]]`, or the short name (possessive included).
    struct PartialApplyResult: Equatable {
        var text: String
        var ranges: [String: [NSRange]]
    }

    /// Render an IN-FLIGHT per-occurrence resolution: like
    /// `applyResolvedOccurrences`, but undecided occurrences stay verbatim, and the
    /// result maps every occurrence to its rendered position. The whole document is
    /// recomputed from the pristine input on every call, so first-mention-gets-
    /// `[[Canonical]]` is decided by DOCUMENT order over the choices made SO FAR —
    /// assigning a later mention first links it immediately, and assigning an
    /// earlier mention to the same person afterwards moves the link there and
    /// demotes the later one to the short name in the same pass.
    ///
    /// All aliases are processed in ONE document-order walk (a global
    /// first-link-per-canonical set), with the same emit rules as
    /// `applyResolvedOccurrences`: a canonical the input already links anywhere
    /// counts as introduced; missing/extra choices beyond an alias's occurrence
    /// count are treated as `.undecided`/ignored. Overlapping matches across
    /// aliases (one alias inside another) keep the earlier match; the loser gets a
    /// zero-length range so the per-alias arrays stay parallel.
    static func applyPartialOccurrences(text inputText: String,
                                        byAlias: [String: [PartialChoice]]) -> PartialApplyResult {
        let ns = inputText as NSString

        struct Occ {
            let alias: String
            let index: Int
            let match: NSTextCheckingResult
            let choice: PartialChoice
        }
        var all: [Occ] = []
        var rangesByAlias: [String: [NSRange]] = [:]
        for (alias, choices) in byAlias {
            let a = alias.trimmingCharacters(in: .whitespaces)
            guard !a.isEmpty, let rx = wordRegex(a) else { rangesByAlias[alias] = []; continue }
            let eligible = rx.matches(in: inputText, range: fullRange(inputText))
                .filter { !avoidInside || notInsideLink(inputText, $0.range.location) }
            rangesByAlias[alias] = Array(repeating: NSRange(location: NSNotFound, length: 0), count: eligible.count)
            for (i, m) in eligible.enumerated() {
                all.append(Occ(alias: alias, index: i, match: m,
                               choice: i < choices.count ? choices[i] : .undecided))
            }
        }
        all.sort { $0.match.range.location < $1.match.range.location }

        var introduced = Set<String>()
        var out = ""
        var outLen = 0   // utf16 length of `out`, tracked incrementally
        var cursor = 0
        for occ in all {
            let r = occ.match.range
            guard r.location >= cursor else {
                // Overlap (e.g. alias "Jack" inside alias "Jack Hutton") — the
                // earlier match consumed this span; keep the arrays parallel.
                rangesByAlias[occ.alias]?[occ.index] = NSRange(location: outLen, length: 0)
                continue
            }
            out += ns.substring(with: NSRange(location: cursor, length: r.location - cursor))
            outLen += r.location - cursor
            let emitted: String
            switch occ.choice {
            case .undecided, .plain:
                emitted = ns.substring(with: r)   // verbatim, possessive included
            case let .person(canonRaw, shortRaw):
                let canon = canonRaw.trimmingCharacters(in: .whitespaces)
                if canon.isEmpty {
                    emitted = ns.substring(with: r)
                } else {
                    let linkText = (canon.hasPrefix("[[") && canon.hasSuffix("]]")) ? canon : "[[\(canon)]]"
                    let core = NamesMerge.keyName(linkText)
                    let short = (shortRaw?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 }
                        ?? (core.split(separator: " ").first.map(String.init) ?? occ.alias)
                    let isFirst = !introduced.contains(core) && occurrences(of: linkText, in: inputText).isEmpty
                    introduced.insert(core)
                    emitted = (isFirst ? linkText : short) + possText(occ.match, in: inputText)
                }
            }
            let emittedLen = (emitted as NSString).length
            rangesByAlias[occ.alias]?[occ.index] = NSRange(location: outLen, length: emittedLen)
            out += emitted
            outLen += emittedLen
            cursor = NSMaxRange(r)
        }
        out += ns.substring(from: cursor)
        return PartialApplyResult(text: out, ranges: rangesByAlias)
    }

    /// Map the RENDERED text's plain alias occurrences back to their pristine
    /// occurrence indices: entry k = the index (into `occurrenceRanges`, i.e. the
    /// pristine enumeration) of the occurrence whose rendered range overlaps the
    /// k-th plain occurrence of `alias` in `rendered`; -1 = foreign text no
    /// occurrence produced. This is how a DEMOTED short name that still reads as
    /// the alias (the two-Jacks case: short "Jack" == alias "Jack") stays
    /// attributable to the right choice after the body re-renders around it.
    static func plainSlotMap(alias: String, rendered: String, occurrenceRanges: [NSRange]) -> [Int] {
        plainOccurrences(of: alias, in: rendered).map { r in
            occurrenceRanges.firstIndex {
                $0.location != NSNotFound && NSIntersectionRange($0, r).length > 0
            } ?? -1
        }
    }

    // MARK: - Unlinking (review-time "unlink a [[Name]]" — mocks/name-unlink.html)

    /// A wiki link in the body: the full `[[…]]` range (brackets included) + the
    /// core text inside the brackets.
    struct BodyLink: Equatable {
        var range: NSRange
        var core: String
    }

    private static let bodyLinkRegex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#)

    /// Every `[[Name]]` wiki link in `text`, in reading order. `[[img_NNN]]` image
    /// markers are markers, not links — skipped. Drives the clickable linked-mention
    /// detection in the review body.
    static func linkOccurrences(in text: String) -> [BodyLink] {
        guard let rx = bodyLinkRegex else { return [] }
        let ns = text as NSString
        return rx.matches(in: text, range: fullRange(text)).compactMap { m in
            let core = ns.substring(with: m.range(at: 1))
            guard core.range(of: #"^img_\d+$"#, options: .regularExpression) == nil else { return nil }
            return BodyLink(range: m.range, core: core)
        }
    }

    /// One person's `[[canonical]]` links in `text` (core match is case-insensitive,
    /// brackets/whitespace tolerated on `canonical`), in reading order. The i-th
    /// entry here is what `unlinkOccurrence(index: i)` replaces — the same
    /// order-based contract as `plainOccurrences`/`applyResolvedOccurrences`.
    static func linkOccurrences(of canonical: String, in text: String) -> [BodyLink] {
        let key = NamesMerge.keyName(canonical).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return [] }
        return linkOccurrences(in: text).filter {
            $0.core.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(key) == .orderedSame
        }
    }

    /// "Unlink this mention": the `index`-th `[[canonical]]` link (reading order)
    /// becomes the plain `alias` as spoken. Order-based, so the UI's storage offsets
    /// (image attachments collapse `[[img_NNN]]` markers to one character) can't
    /// misapply. A possessive sits OUTSIDE the brackets (`[[Nick Jansen]]'s`) and is
    /// left in place → `Nick's`. An out-of-range index returns the text unchanged.
    static func unlinkOccurrence(text: String, canonical: String, index: Int, alias: String) -> String {
        let links = linkOccurrences(of: canonical, in: text)
        guard index >= 0, index < links.count else { return text }
        return nsReplace(text, links[index].range, with: alias)
    }

    /// "Unlink all mentions in this note": EVERY `[[canonical]]` link becomes the
    /// plain `alias`. Plain mentions are already plain and other links (other
    /// people, image markers, place links) are untouched. The caller persists the
    /// choice (`PipelineFile.unlinkedNames`) and feeds it back via
    /// `process(neverLink:)` so re-processing doesn't re-link.
    static func unlinkAll(text: String, canonical: String, alias: String) -> String {
        var out = text
        for link in linkOccurrences(of: canonical, in: text).reversed() {
            out = nsReplace(out, link.range, with: alias)
        }
        return out
    }

    /// The plain text a mention reads as once unlinked — the SAME short-name rule
    /// `process` uses when demoting later mentions (short override → first word of
    /// the canonical), falling back to the bare canonical.
    static func spokenAlias(for p: Person) -> String {
        let short = shortName(for: p)
        if !short.isEmpty { return short }
        return NamesMerge.keyName(p.canonical).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Helpers

    private static func shortName(for p: Person) -> String {
        let override = (p.short ?? "").trimmingCharacters(in: .whitespaces)
        if !override.isEmpty { return override }
        let core = NamesMerge.keyName(p.canonical)
        return core.split(separator: " ").first.map(String.init) ?? ""
    }

    private static func wordRegex(_ alias: String) -> NSRegularExpression? {
        let wb = wholeWord ? "\\b" : ""
        let pat = "\(wb)\(NSRegularExpression.escapedPattern(for: alias))\(wb)\(preservePossessive ? possPattern : "")"
        return try? NSRegularExpression(pattern: pat, options: [.caseInsensitive])
    }

    private static func possText(_ m: NSTextCheckingResult, in text: String) -> String {
        guard preservePossessive else { return "" }
        let r = m.range(withName: "poss")
        guard r.location != NSNotFound, r.length > 0 else { return "" }
        return nsSub(text, r.location, r.location + r.length)
    }

    /// Literal occurrences of `needle` in `text` (ascending NSRanges) — used to spot
    /// canonical links the text already carries.
    private static func occurrences(of needle: String, in text: String) -> [NSRange] {
        guard !needle.isEmpty else { return [] }
        let ns = text as NSString
        var out: [NSRange] = []
        var from = 0
        while from < ns.length {
            let r = ns.range(of: needle, options: [], range: NSRange(location: from, length: ns.length - from))
            if r.location == NSNotFound { break }
            out.append(r)
            from = r.location + r.length
        }
        return out
    }

    private static func notInsideLink(_ s: String, _ start: Int) -> Bool {
        let ns = s as NSString
        let open = ns.range(of: "[[", options: .backwards, range: NSRange(location: 0, length: start))
        if open.location == NSNotFound { return true }
        let close = ns.range(of: "]]", options: [], range: NSRange(location: open.location, length: ns.length - open.location))
        return close.location != NSNotFound && close.location < start
    }

    private static func nsLen(_ s: String) -> Int { (s as NSString).length }
    private static func nsSub(_ s: String, _ from: Int, _ to: Int) -> String {
        (s as NSString).substring(with: NSRange(location: from, length: max(0, to - from)))
    }
    private static func nsReplace(_ s: String, _ range: NSRange, with repl: String) -> String {
        (s as NSString).replacingCharacters(in: range, with: repl)
    }
    private static func fullRange(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }
}
