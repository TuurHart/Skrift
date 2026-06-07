import Foundation

/// Name-linking — the LAST deterministic pipeline step, non-blocking. Unambiguous
/// aliases auto-link (first mention → `[[Canonical]]`, rest → short name); an alias
/// that maps to 2+ people is left plain and recorded as an `AmbiguousOccurrence`
/// for the review-time resolver. Pure (text + people → text + ambiguities), so it
/// host-tests without a backend. Ported from `backend/services/sanitisation.py`.
/// Fixed settings match DEFAULT_SETTINGS.sanitisation (whole_word, mode=first,
/// avoid_inside_links, preserve_possessive, wiki style).
enum Sanitiser {
    struct Result: Equatable, Sendable {
        let sanitised: String
        let ambiguous: [AmbiguousOccurrence]
    }

    private static let wholeWord = true
    private static let avoidInside = true
    private static let preservePossessive = true
    private static let possPattern = "(?<poss>(?:'s|’s)?)"

    static func process(text inputText: String, people: [Person]) -> Result {
        var text = inputText
        let live = people.filter { !$0.isDeleted }

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

            // First eligible occurrence across the person's aliases → the link.
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
            for (i, m) in eligible.enumerated().reversed() {
                let replacement = (i == 0 ? linkText : short) + possText(m, in: text)
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
                let isFirst = !introduced.contains(core)
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
