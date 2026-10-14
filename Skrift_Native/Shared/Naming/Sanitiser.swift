import Foundation

/// Name-linking — the LAST deterministic pipeline step, non-blocking. OPT-OUT
/// (NAMING_MODEL.md decision 4): every known person is a subject by default, so a
/// person's FIRST mention auto-links (`[[Canonical]]`, rest → short name) — but
/// RISK-TIERED, because opt-out auto-*writes* links to the exported file. Only a
/// SAFE match auto-commits (a full name, or a distinctive first name); an FP-prone
/// match (common-word / too-short single name — `NameStoplist`) or an ambiguous one
/// (an alias shared by 2+ roster people) is left plain and recorded as a *suggested*
/// `AmbiguousOccurrence` (carried in `Result.ambiguous`) so review can render it
/// dotted and commit it on click. Pure (text + people → text + suggestions), so it
/// host-tests without a backend. Ported from `backend/services/sanitisation.py`.
/// Fixed settings match DEFAULT_SETTINGS.sanitisation (whole_word, mode=first,
/// avoid_inside_links, preserve_possessive, wiki style).
///
/// Non-prose spans are skipped when scanning (NON-NEGOTIABLE build-guard): existing
/// `[[ ]]` links, a leading YAML block, fenced/inline code, and a verbatim
/// audiobook-quote span (a name inside a quoted book passage is NOT "about" that
/// roster person) — see `nonProseRanges`.
///
/// First-mention-only holds even when the INPUT already carries canonical links:
/// Mac-diarized conversations arrive with `**[[Person]]:**` on EVERY turn header
/// (the 2026-06-10 "brackets on every mention" bug) — the earliest existing link
/// counts as the first mention, every later copy is demoted to the short name, and
/// no new link is introduced for that person. Only links matching a known person's
/// canonical are touched (`[[img_NNN]]` markers / place links pass through).
enum Sanitiser {
    /// `ambiguous` is the *suggested* tier: recognised-but-not-auto-linked
    /// occurrences the review surface renders dotted (commit on click). It carries
    /// BOTH the ambiguous case (an alias shared by 2+ people → `candidates.count >= 2`)
    /// AND the common-word case (an FP-prone single name → `candidates.count == 1`).
    struct Result: Equatable, Sendable {
        let sanitised: String
        let ambiguous: [AmbiguousOccurrence]
    }

    /// The possessive tail of an alias match: `'s` / `’s`, the Dutch BARE `s` (`Wims`, `Lottes`,
    /// C255), or nothing. The empty alternative keeps the old `\b` after the alias. A bare `s`
    /// that spells another roster alias is NOT a possessive — see `matches(of:in:roster:)`.
    static let possPattern = "(?<poss>'s|’s|s\\b|\\b)"

    /// Pre-computed per-note naming overrides, shared by `process` + `processConversation`.
    /// LINKABLE = live people minus the pruned ones (these auto-link + are ambiguity
    /// candidates); a force-picked person always owns their picked alias (pick > prune).
    /// `aliasMap` is over the linkable set, dropping silenced aliases and resolving a forced
    /// alias to its single owner. `prunedAliasMap` holds pruned people's aliases that NO
    /// linkable person owns — so a pruned distinctive name still surfaces as a dotted
    /// (re-promotable) suggestion (mocks/naming-review.html state 3).
    struct Overrides {
        let live: [Person]
        let forced: [String: Person]        // alias(lower) → force-link person
        let aliasMap: [String: [Person]]    // linkable alias map (link + ambiguity)
        let ambiguousAliases: Set<String>
        let prunedAliasMap: [String: [Person]]
        /// Every live person's aliases, diacritic-folded + lowercased (`Sanitiser.fold`). A word
        /// in here is a name of its own, so `alias + "s"` spelling one is not a bare possessive.
        let rosterWords: Set<String>

        static func key(_ p: Person) -> String {
            NamesMerge.matchKey(p.canonical)
        }

        init(people: [Person], neverLink: Set<String>, namePicks: [String: String]) {
            let liveAll = people.filter { !$0.isDeleted }
            live = liveAll
            rosterWords = Set(liveAll.flatMap { $0.aliases }.map { Sanitiser.fold($0) }.filter { !$0.isEmpty })
            let pruned = Set(neverLink.map { NamesMerge.matchKey($0) })

            var f: [String: Person] = [:]
            var s = Set<String>()
            for (rawAlias, rawCanon) in namePicks {
                let a = NamesMerge.aliasKey(rawAlias)
                guard !a.isEmpty else { continue }
                let canonKey = NamesMerge.matchKey(rawCanon)
                if canonKey.isEmpty { s.insert(a); continue }
                if let p = liveAll.first(where: { Overrides.key($0) == canonKey }) { f[a] = p }
            }
            forced = f

            var map: [String: [Person]] = [:]
            for p in liveAll where !pruned.contains(Overrides.key(p)) {
                for a in p.aliases {
                    let al = NamesMerge.aliasKey(a)
                    guard !al.isEmpty, !s.contains(al) else { continue }
                    if let owner = f[al] { if Overrides.key(owner) == Overrides.key(p) { map[al, default: []].append(p) } }
                    else { map[al, default: []].append(p) }
                }
            }
            for (al, p) in f where map[al] == nil { map[al] = [p] }   // forced pruned person owns their alias
            aliasMap = map
            ambiguousAliases = Set(map.filter { $0.value.count >= 2 }.keys).subtracting(f.keys)

            var pmap: [String: [Person]] = [:]
            for p in liveAll where pruned.contains(Overrides.key(p))
                && f.values.allSatisfy({ Overrides.key($0) != Overrides.key(p) }) {
                for a in p.aliases {
                    let al = NamesMerge.aliasKey(a)
                    guard !al.isEmpty, !s.contains(al), map[al] == nil else { continue }
                    pmap[al, default: []].append(p)
                }
            }
            prunedAliasMap = pmap
        }

        /// People eligible for the auto-link pass — everyone with a linkable alias, sorted.
        var linkPeople: [Person] {
            var seen = Set<String>(); var out: [Person] = []
            for people in aliasMap.values { for p in people {
                if seen.insert(Overrides.key(p)).inserted { out.append(p) } } }
            return out.sorted { Overrides.key($0) < Overrides.key($1) }
        }

        /// The aliases of `p` that map to `p` in the linkable aliasMap (their own, owned,
        /// non-silenced aliases) PLUS any force-picked alias assigned to `p` — what the
        /// auto-link pass may use. The forced part is the "change person" case: a spoken
        /// "Hendri" force-linked to Will Smith must link even though "Hendri" isn't one of
        /// Will's declared aliases (without this it silently fell through to plain text).
        func ownedAliases(of p: Person) -> [String] {
            let k = Overrides.key(p)
            var out = p.aliases.map { $0.trimmingCharacters(in: .whitespaces) }.filter { alias in
                !alias.isEmpty && (aliasMap[alias.lowercased()]?.contains { Overrides.key($0) == k } ?? false)
            }
            for (al, owner) in forced where Overrides.key(owner) == k
                && !out.contains(where: { $0.lowercased() == al }) {
                out.append(al)
            }
            return out
        }

        /// What the auto-link pass may do with `p`'s aliases: `unambiguous` = the owned aliases
        /// no one else shares (every later mention of them demotes); `linkAliases` = the
        /// distinctive subset (plus any force-picked alias, which bypasses FP-prone) that may
        /// earn the one link.
        func linkable(_ p: Person) -> (unambiguous: [String], linkAliases: [String]) {
            let unambiguous = ownedAliases(of: p).filter { !ambiguousAliases.contains($0.lowercased()) }
            let linkAliases = unambiguous.filter { !NameStoplist.isFpProne($0) || forced[$0.lowercased()] != nil }
            return (unambiguous, linkAliases)
        }
    }

    /// `neverLink` carries the note's persisted PRUNE choices (`PipelineFile.unlinkedNames`,
    /// canonical keys — bare or `[[bracketed]]`, case-insensitive). A pruned person is NOT
    /// auto-linked, but their plain mentions ARE recorded as dotted SUGGESTIONS — the everyday
    /// opt-out "this note's mention is a side-mention" gesture (mocks/naming-review.html state 3:
    /// "the unlinked name stays a dotted suggestion — re-promotable"). A pruned person is also
    /// dropped as an ambiguity candidate, so pruning one of two same-name people lets the other
    /// auto-link.
    ///
    /// `namePicks` carries the note's per-alias "which person?" overrides (`PipelineFile.namePicks`,
    /// alias lowercased → chosen canonical `[[Name]]`). A pick FORCE-LINKS that alias to the
    /// chosen person for this note (bypassing the FP-prone + ambiguity guards AND a prune — the
    /// user confirmed). An EMPTY canonical SILENCES the alias (renders plain — neither linked nor
    /// suggested): the "leave as plain text" choice on a suggestion.
    static func process(text inputText: String, people: [Person],
                        neverLink: Set<String> = [], namePicks: [String: String] = [:]) -> Result {
        var text = inputText
        let ov = Overrides(people: people, neverLink: neverLink, namePicks: namePicks)

        // Auto-link pass over the linkable + force-picked people (sorted by canonical). A
        // person's FIRST mention via a link-eligible alias becomes the one `[[Canonical]]`
        // link; every later mention of their unambiguous aliases demotes to the short name.
        var linkedKeys = Set<String>()
        for p in ov.linkPeople {
            let canonKey = NamesMerge.bareName(p.canonical)
            let short = shortName(for: p)
            let (unambiguous, linkAliases) = ov.linkable(p)
            let linkText = "[[\(canonKey)]]"

            // The text may ALREADY carry this person's canonical link — bare `[[Name]]` OR the
            // alias-display `[[Name|short]]` form (a diarized turn header / a re-derived body):
            // that earliest link IS the first mention — demote the later copies to the short name.
            // Pipe-tolerant (`linkOccurrences`) so a `[[Name|short]]` can't slip past and earn a 2nd link.
            let existingLinks = linkOccurrences(of: canonKey, in: text)
            var isLinked = false
            if !existingLinks.isEmpty {
                isLinked = true
                if !short.isEmpty {
                    for link in existingLinks.dropFirst().reversed() { text = nsReplace(text, link.range, with: short) }
                }
            } else if let first = firstSafeMatch(of: linkAliases, in: text, roster: ov.rosterWords) {
                text = nsReplace(text, first.range, with: linkText + possText(first, in: text))
                isLinked = true
            }
            if isLinked { linkedKeys.insert(canonKey.lowercased()) }

            guard isLinked, !short.isEmpty else { continue }
            text = demoteMentions(of: unambiguous, to: short, in: text, roster: ov.rosterWords)
        }

        let suggested = suggestedOccurrences(in: text, overrides: ov, linkedKeys: linkedKeys)
        return Result(sanitised: text, ambiguous: suggested)
    }

    // MARK: - Helpers

    /// The earliest ELIGIBLE match across `aliases`: each alias's first match that is neither
    /// inside a link nor a non-prose span (e.g. a leading audiobook quote), then the earliest of
    /// those. `prot` = `nonProseRanges(in: text)` when the caller already has it.
    static func firstSafeMatch(of aliases: [String], in text: String,
                               prot: [NSRange]? = nil, roster: Set<String>) -> NSTextCheckingResult? {
        guard !aliases.isEmpty else { return nil }
        let prot = prot ?? nonProseRanges(in: text)
        var earliest: NSTextCheckingResult?
        for alias in aliases {
            for m in matches(of: alias, in: text, roster: roster) where eligible(text, m.range.location, prot) {
                if earliest == nil || m.range.location < earliest!.range.location { earliest = m }
                break
            }
        }
        return earliest
    }

    /// Every eligible mention of `aliases` in `text` becomes `replacement` (the possessive stays
    /// outside it). The caller picks the string: `process` the short name, `linkInline` the short
    /// or, with none defined, the canonical.
    static func demoteMentions(of aliases: [String], to replacement: String, in text: String,
                               roster: Set<String>) -> String {
        var text = text
        let prot = nonProseRanges(in: text)
        for alias in aliases {
            for m in matches(of: alias, in: text, roster: roster).reversed() {
                if !eligible(text, m.range.location, prot) { continue }
                text = nsReplace(text, m.range, with: replacement + possText(m, in: text))
            }
        }
        return text
    }

    /// A match location is eligible for linking/suggesting when it's neither inside an
    /// existing `[[ ]]` link nor inside a non-prose span. The single gate both `process`
    /// paths + `suggestedOccurrences` use.
    static func eligible(_ text: String, _ loc: Int, _ protectedRanges: [NSRange]) -> Bool {
        guard notInsideLink(text, loc) else { return false }
        return !protectedRanges.contains { NSLocationInRange(loc, $0) }
    }

    /// Non-prose spans a name scan must SKIP (NON-NEGOTIABLE build-guard): a leading YAML
    /// frontmatter block, fenced ```` ``` ```` code blocks, inline `code`, and a leading
    /// audiobook-quote block (a name inside a quoted book passage is NOT "about" that roster
    /// person — matters for the quote-capture feature). Existing `[[ ]]` links are handled
    /// separately (`notInsideLink`). Ranges are over `text` AS GIVEN — recompute after the
    /// text mutates (linking shifts later offsets). Almost always empty for ordinary memos.
    static func nonProseRanges(in text: String) -> [NSRange] {
        let ns = text as NSString
        var ranges: [NSRange] = []
        // Leading YAML frontmatter: "---\n … \n---" anchored at offset 0. (The pipeline body
        // never carries frontmatter — the Compiler adds it later — but an Apple-Note import
        // might; cheap belt-and-suspenders.)
        if text.hasPrefix("---\n") {
            let close = ns.range(of: "\n---", options: [], range: NSRange(location: 3, length: ns.length - 3)).location
            if close != NSNotFound {
                // Extend to the end of the closing delimiter line.
                let after = close + 4
                let lineEnd = ns.range(of: "\n", options: [], range: NSRange(location: after, length: max(0, ns.length - after))).location
                let end = lineEnd == NSNotFound ? ns.length : lineEnd
                ranges.append(NSRange(location: 0, length: end))
            }
        }
        // Leading audiobook-quote block (consecutive ">"-prefixed lines from offset 0).
        if let split = QuoteProtection.splitLeadingQuote(text) {
            ranges.append(NSRange(location: 0, length: (split.quote as NSString).length))
        }
        // Fenced code blocks, then inline code.
        for pattern in ["```[\\s\\S]*?```", "`[^`\\n]+`"] {
            guard let rx = try? NSRegularExpression(pattern: pattern) else { continue }
            for m in rx.matches(in: text, range: fullRange(text)) { ranges.append(m.range) }
        }
        // Inline `#tags` (C260): a tag is one token, so a name inside it (`#Wim`, `#work/wim`) is
        // never linked, demoted or suggested — that would split the tag into `#[[Name]]`.
        for m in tagRegex.matches(in: text, range: fullRange(text)) { ranges.append(m.range) }
        // Memo↔memo links: an alias inside a link TITLE must never be
        // name-linked (nested [[…]] would corrupt the syntax).
        for occ in MemoLinkSyntax.occurrences(in: text) { ranges.append(occ.range) }
        return ranges
    }

    /// True when the character at `loc` starts with an uppercase letter — the secondary
    /// capitalization FP-guard for common-word suggestions ("Will" the name vs "will" the verb).
    static func startsUppercase(_ text: String, at loc: Int) -> Bool {
        let ns = text as NSString
        guard loc >= 0, loc < ns.length else { return false }
        return ns.substring(with: NSRange(location: loc, length: 1)).first?.isUppercase ?? false
    }

    static func shortName(for p: Person) -> String {
        let override = (p.short ?? "").trimmingCharacters(in: .whitespaces)
        if !override.isEmpty { return override }
        let core = NamesMerge.keyName(p.canonical)
        return core.split(separator: " ").first.map(String.init) ?? ""
    }

    /// Compiled-pattern cache — every process()/nameSpans() call used to build a
    /// fresh NSRegularExpression per alias. NSCache = thread-safe.
    static let wordRegexCache = NSCache<NSString, NSRegularExpression>()

    /// An Obsidian inline tag: `#` not glued to a preceding word character, then tag characters.
    /// A `# heading` (space after the hash) is not a tag.
    static let tagRegex = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_&])#[\p{L}\p{N}_\-/]+"#)

    /// The alias with diacritics and case dropped — the one fold every "same name?" comparison
    /// uses (Ines/Inés, Månsson/Mansson). Both sides fold, so the match works both ways.
    static func fold(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// base letter (lowercase) → every Latin letter that folds to it (À…ɏ, Ḁ…ỿ), built once.
    static let diacriticVariants: [Character: String] = {
        var out: [Character: String] = [:]
        for range in [0x00C0...0x024F, 0x1E00...0x1EFF] {
            for v in range {
                guard let u = Unicode.Scalar(v) else { continue }
                let ch = String(Character(u))
                let f = ch.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                guard f.count == 1, let base = f.first, base != Character(ch.lowercased()) else { continue }
                out[base, default: ""] += ch.lowercased()
            }
        }
        return out
    }()

    /// Regex source for `alias`: every letter also matches its accented variants (composed, or
    /// followed by a combining mark), so an accented alias matches plain text and the reverse.
    static func foldedPattern(_ alias: String) -> String {
        let plain = alias.folding(options: [.diacriticInsensitive], locale: nil)
        var out = ""
        for ch in plain {
            let lower = Character(String(ch).lowercased())
            if ch.isLetter, let extra = diacriticVariants[lower] {
                out += "(?:[" + NSRegularExpression.escapedPattern(for: String(lower) + extra) + "]\\p{M}*)"
            } else {
                out += NSRegularExpression.escapedPattern(for: String(ch))
            }
        }
        return out
    }

    static func wordRegex(_ alias: String) -> NSRegularExpression? {
        let key = alias as NSString
        if let hit = wordRegexCache.object(forKey: key) { return hit }
        let pat = "\\b\(foldedPattern(alias))\(possPattern)"
        guard let rx = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) else { return nil }
        wordRegexCache.setObject(rx, forKey: key)
        return rx
    }

    /// Every match of `alias` in `text`, minus the Dutch bare-`s` ones that spell another roster
    /// alias ("Wims" is its own person when Wims is on the roster, not Wim's). `roster` =
    /// `Overrides.rosterWords`.
    static func matches(of alias: String, in text: String, roster: Set<String>) -> [NSTextCheckingResult] {
        guard let rx = wordRegex(alias) else { return [] }
        return rx.matches(in: text, range: fullRange(text)).filter { m in
            let poss = m.range(withName: "poss")
            guard poss.location != NSNotFound, poss.length == 1,
                  nsSub(text, poss.location, poss.location + 1).lowercased() == "s" else { return true }
            return !roster.contains(fold(nsSub(text, m.range.location, m.range.location + m.range.length)))
        }
    }

    static func possText(_ m: NSTextCheckingResult, in text: String) -> String {
        let r = m.range(withName: "poss")
        guard r.location != NSNotFound, r.length > 0 else { return "" }
        return nsSub(text, r.location, r.location + r.length)
    }

    static func notInsideLink(_ s: String, _ start: Int) -> Bool {
        let ns = s as NSString
        let open = ns.range(of: "[[", options: .backwards, range: NSRange(location: 0, length: start))
        if open.location == NSNotFound { return true }
        let close = ns.range(of: "]]", options: [], range: NSRange(location: open.location, length: ns.length - open.location))
        return close.location != NSNotFound && close.location < start
    }

    static func nsLen(_ s: String) -> Int { (s as NSString).length }
    static func nsSub(_ s: String, _ from: Int, _ to: Int) -> String {
        (s as NSString).substring(with: NSRange(location: from, length: max(0, to - from)))
    }
    static func nsReplace(_ s: String, _ range: NSRange, with repl: String) -> String {
        (s as NSString).replacingCharacters(in: range, with: repl)
    }
    /// Apply several `(range, replacement)` edits to `s` in one pass. Ranges are all in the
    /// ORIGINAL string's coordinates, in any order (applied right-to-left so earlier ranges
    /// stay valid) — the one place the replace-by-ranges loop lives.
    static func nsReplace(_ s: String, edits: [(NSRange, String)]) -> String {
        var out = s
        for (range, repl) in edits.sorted(by: { $0.0.location > $1.0.location }) {
            out = nsReplace(out, range, with: repl)
        }
        return out
    }
    static func fullRange(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }
}
