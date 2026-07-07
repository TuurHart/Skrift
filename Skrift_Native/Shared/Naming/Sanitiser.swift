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

    private static let wholeWord = true
    private static let avoidInside = true
    private static let preservePossessive = true
    private static let possPattern = "(?<poss>(?:'s|’s)?)"

    /// Pre-computed per-note naming overrides, shared by `process` + `processConversation`.
    /// LINKABLE = live people minus the pruned ones (these auto-link + are ambiguity
    /// candidates); a force-picked person always owns their picked alias (pick > prune).
    /// `aliasMap` is over the linkable set, dropping silenced aliases and resolving a forced
    /// alias to its single owner. `prunedAliasMap` holds pruned people's aliases that NO
    /// linkable person owns — so a pruned distinctive name still surfaces as a dotted
    /// (re-promotable) suggestion (mocks/naming-review.html state 3).
    struct Overrides {
        let live: [Person]
        let prunedKeys: Set<String>
        let forced: [String: Person]        // alias(lower) → force-link person
        let silenced: Set<String>           // alias(lower) → plain (no link, no suggest)
        let aliasMap: [String: [Person]]    // linkable alias map (link + ambiguity)
        let ambiguousAliases: Set<String>
        let prunedAliasMap: [String: [Person]]

        static func key(_ p: Person) -> String {
            NamesMerge.keyName(p.canonical).trimmingCharacters(in: .whitespaces).lowercased()
        }

        init(people: [Person], neverLink: Set<String>, namePicks: [String: String]) {
            let liveAll = people.filter { !$0.isDeleted }
            live = liveAll
            let pruned = Set(neverLink.map { NamesMerge.keyName($0).trimmingCharacters(in: .whitespaces).lowercased() })
            prunedKeys = pruned

            var f: [String: Person] = [:]
            var s = Set<String>()
            for (rawAlias, rawCanon) in namePicks {
                let a = rawAlias.trimmingCharacters(in: .whitespaces).lowercased()
                guard !a.isEmpty else { continue }
                let canonKey = NamesMerge.keyName(rawCanon).trimmingCharacters(in: .whitespaces).lowercased()
                if canonKey.isEmpty { s.insert(a); continue }
                if let p = liveAll.first(where: { Overrides.key($0) == canonKey }) { f[a] = p }
            }
            forced = f
            silenced = s

            var map: [String: [Person]] = [:]
            for p in liveAll where !pruned.contains(Overrides.key(p)) {
                for a in p.aliases {
                    let al = a.trimmingCharacters(in: .whitespaces).lowercased()
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
                    let al = a.trimmingCharacters(in: .whitespaces).lowercased()
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
            let canonKey = NamesMerge.keyName(p.canonical).trimmingCharacters(in: .whitespaces)
            let short = shortName(for: p)
            let unambiguous = ov.ownedAliases(of: p).filter { !ov.ambiguousAliases.contains($0.lowercased()) }
            // Link-eligible: distinctive aliases, plus any force-picked alias (bypass FP-prone).
            let linkAliases = unambiguous.filter { !NameStoplist.isFpProne($0) || ov.forced[$0.lowercased()] != nil }
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
            } else if !linkAliases.isEmpty {
                let prot = nonProseRanges(in: text)
                var earliest: (range: NSRange, poss: String)?
                for rx in linkAliases.compactMap({ wordRegex($0) }) {
                    // First ELIGIBLE match of this alias (skipping any inside a link / non-prose
                    // span — e.g. a leading audiobook quote), then take the earliest across aliases.
                    for m in rx.matches(in: text, range: fullRange(text)) where eligible(text, m.range.location, prot) {
                        if earliest == nil || m.range.location < earliest!.range.location {
                            earliest = (m.range, possText(m, in: text))
                        }
                        break
                    }
                }
                if let first = earliest {
                    text = nsReplace(text, first.range, with: linkText + first.poss)
                    isLinked = true
                }
            }
            if isLinked { linkedKeys.insert(canonKey.lowercased()) }

            guard isLinked, !short.isEmpty else { continue }
            let prot = nonProseRanges(in: text)
            for rx in unambiguous.compactMap({ wordRegex($0) }) {
                for m in rx.matches(in: text, range: fullRange(text)).reversed() {
                    if !eligible(text, m.range.location, prot) { continue }
                    text = nsReplace(text, m.range, with: short + possText(m, in: text))
                }
            }
        }

        let suggested = suggestedOccurrences(in: text, overrides: ov, linkedKeys: linkedKeys)
        return Result(sanitised: text, ambiguous: suggested)
    }

    // MARK: - Tiered name spans over the RAW transcript (phone in-place linking)

    /// Tiered name occurrences over the RAW transcript — the phone's in-place
    /// name-linking touch surface (`mocks/phone-name-linking.html`). Makes the SAME
    /// linking decisions as `process` (identical `Overrides`, identical earliest-
    /// eligible-safe first mention, identical `suggestedOccurrences`) but RECORDS spans
    /// at their RAW offsets instead of mutating the text — so the phone styles the
    /// spoken word in place and the transcript stays RAW (the contract spine). One
    /// LINKED span per linked person (first mention only); later mentions + pronouns are
    /// plain. Monologue only — diarized conversations render through `SpeakerTurnsView`,
    /// which does its own alias-display linking. Deterministic, LLM-free.
    ///
    /// A linked span's `candidates` carry EVERY live person who shares the matched alias,
    /// so the UI can offer "Change person…" only when 2+ exist (a force-picked ambiguous
    /// "Jack"), and just Unlink/Open for a uniquely-owned name ("Hendri").
    static func nameSpans(inRaw raw: String, people: [Person],
                          neverLink: Set<String> = [], namePicks: [String: String] = [:]) -> [NameSpan] {
        guard !raw.isEmpty else { return [] }
        let ov = Overrides(people: people, neverLink: neverLink, namePicks: namePicks)
        let prot = nonProseRanges(in: raw)
        var spans: [NameSpan] = []
        var linkedKeys = Set<String>()

        func candidate(_ p: Person) -> NameCandidate {
            NameCandidate(id: p.canonical, canonical: p.canonical, short: shortName(for: p))
        }
        // Every live person who declares `alias` (case-insensitive) — drives the
        // ambiguity of a LINKED span (≥2 ⇒ offer "Change person…").
        func sharers(of alias: String) -> [Person] {
            let a = alias.trimmingCharacters(in: .whitespaces).lowercased()
            guard !a.isEmpty else { return [] }
            return ov.live.filter { p in
                p.aliases.contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == a }
            }
        }
        // The match range minus any trailing possessive (`Jack's` → `Jack`), so the
        // linked token is the bare name and the `'s` stays plain — matching `process`,
        // which writes the possessive OUTSIDE the brackets.
        func nameOnly(_ m: NSTextCheckingResult) -> NSRange {
            let poss = m.range(withName: "poss")
            guard poss.location != NSNotFound, poss.length > 0 else { return m.range }
            return NSRange(location: m.range.location, length: m.range.length - poss.length)
        }
        // Drop a trailing possessive from a recorded occurrence's range (the
        // `suggestedOccurrences` length INCLUDES the `'s`), so the span text is the bare
        // spoken word and the resolution key is clean.
        func stripPoss(offset: Int, length: Int) -> NSRange {
            let s = nsSub(raw, offset, offset + length) as NSString
            for suffix in ["'s", "\u{2019}s"] where s.hasSuffix(suffix) {
                return NSRange(location: offset, length: length - (suffix as NSString).length)
            }
            return NSRange(location: offset, length: length)
        }

        // First-mention LINKED span per linkable / force-picked person (sorted by
        // canonical) — the SAME person `process` would link first, recorded at its RAW
        // offset (no bracket written).
        for p in ov.linkPeople {
            let canonKey = NamesMerge.keyName(p.canonical).trimmingCharacters(in: .whitespaces)
            let unambiguous = ov.ownedAliases(of: p).filter { !ov.ambiguousAliases.contains($0.lowercased()) }
            let linkAliases = unambiguous.filter { !NameStoplist.isFpProne($0) || ov.forced[$0.lowercased()] != nil }

            // A raw transcript may already carry this person's canonical link (a diarized
            // fragment passing through) — that earliest link is the first mention.
            if let first = linkOccurrences(of: canonKey, in: raw).first {
                let shown = first.core.contains("|") ? (first.core.split(separator: "|").last.map(String.init) ?? canonKey) : canonKey
                spans.append(NameSpan(offset: first.range.location, length: first.range.length,
                                      alias: shown, tier: .linked, canonical: p.canonical,
                                      candidates: { let s = sharers(of: shown); return s.isEmpty ? [candidate(p)] : s.map(candidate) }()))
                linkedKeys.insert(canonKey.lowercased())
                continue
            }
            guard !linkAliases.isEmpty else { continue }
            var earliest: NSTextCheckingResult?
            for rx in linkAliases.compactMap({ wordRegex($0) }) {
                for m in rx.matches(in: raw, range: fullRange(raw)) where eligible(raw, m.range.location, prot) {
                    if earliest == nil || m.range.location < earliest!.range.location { earliest = m }
                    break
                }
            }
            guard let m = earliest else { continue }
            let r = nameOnly(m)
            let shownAlias = nsSub(raw, r.location, r.location + r.length)
            let cands = sharers(of: shownAlias)
            spans.append(NameSpan(offset: r.location, length: r.length, alias: shownAlias,
                                  tier: .linked, canonical: p.canonical,
                                  candidates: cands.isEmpty ? [candidate(p)] : cands.map(candidate)))
            linkedKeys.insert(canonKey.lowercased())
        }

        // SUGGESTED + AMBIGUOUS tiers — reuse the EXACT `process` machinery over RAW.
        // `AmbiguousOccurrence.alias` is the lowercased roster KEY; the displayed token
        // is the SURFACE form (`Jack`, not `jack`), so read it back from the raw text
        // (possessive stripped).
        for occ in suggestedOccurrences(in: raw, overrides: ov, linkedKeys: linkedKeys) {
            let r = stripPoss(offset: occ.offset, length: occ.length)
            spans.append(NameSpan(offset: r.location, length: r.length,
                                  alias: nsSub(raw, r.location, r.location + r.length),
                                  tier: occ.candidates.count >= 2 ? .ambiguous : .suggested,
                                  canonical: occ.candidates.count == 1 ? occ.candidates[0].canonical : nil,
                                  candidates: occ.candidates))
        }

        // PLAIN (leftplain) tier — a SILENCED alias (`namePicks[alias] == ""`, the
        // reversible "keep as plain text" / unlink gesture) that still belongs to ≥1 live
        // person stays a faint dotted, re-tappable token so it can be re-linked inline.
        // The silence already suppressed any link/suggestion above, so these never overlap.
        for (rawAlias, canon) in namePicks where canon.trimmingCharacters(in: .whitespaces).isEmpty {
            let alias = rawAlias.trimmingCharacters(in: .whitespaces)
            let cands = sharers(of: alias)
            guard !cands.isEmpty, let rx = wordRegex(alias) else { continue }
            for m in rx.matches(in: raw, range: fullRange(raw)) where eligible(raw, m.range.location, prot) {
                let r = stripPoss(offset: m.range.location, length: m.range.length)
                spans.append(NameSpan(offset: r.location, length: r.length,
                                      alias: nsSub(raw, r.location, r.location + r.length),
                                      tier: .plain, canonical: nil, candidates: cands.map(candidate)))
            }
        }

        return spans.sorted { $0.offset < $1.offset }
    }

    // MARK: - Conversation-aware name-linking (speaker-attributed transcripts)

    /// Name-linking for a `**Name:**`-turn conversation — distinct from `process`
    /// (monologue) because turn HEADERS and INLINE speech want different treatment:
    ///
    /// - **Same-speaker merge** (#3): consecutive turns by the same resolved speaker are
    ///   merged into one, repairing diarization fragmentation.
    /// - **Headers** (#2): a speaker's FIRST turn header becomes a full `[[Canonical]]`
    ///   link; later headers become the plain short name (`**Tuur:**`). Unmatched
    ///   ("Speaker N") / unknown / ambiguous headers stay plain.
    /// - **Inline mentions** (#1): FIRST-ONLY per person ("one note, one link"). A person's
    ///   first not-yet-linked mention becomes the Obsidian alias-display `[[Canonical|short]]`
    ///   (or bare `[[Canonical]]` when the short equals the canonical); every later mention —
    ///   and every mention of a speaker already linked in their header — demotes to the plain
    ///   short name. Ambiguous aliases stay plain and are recorded for the resolver.
    ///
    /// OPT-OUT (decision 4): matched SPEAKERS auto-link in their header (a speaker is
    /// definitionally a subject) and every known person's first inline mention auto-links
    /// too — risk-tiered, so only a SAFE alias commits; FP-prone / ambiguous ones stay
    /// plain and are recorded as suggestions. Falls back to `process` (monologue) when the
    /// text isn't actually attributed.
    static func processConversation(text inputText: String, people: [Person],
                                    neverLink: Set<String> = [], namePicks: [String: String] = [:]) -> Result {
        guard let parsedWP = SpeakerTranscript.parseWithPreamble(inputText) else {
            return process(text: inputText, people: people, neverLink: neverLink, namePicks: namePicks)
        }
        let parsed = parsedWP.turns
        let preamble = parsedWP.preamble
        let ov = Overrides(people: people, neverLink: neverLink, namePicks: namePicks)
        let live = ov.live

        // Header-resolution alias map over ALL live people — a matched speaker is a subject,
        // resolved regardless of prune/silence (those overrides shape INLINE + suggestions).
        var resolveMap: [String: [Person]] = [:]
        for p in live {
            for a in p.aliases {
                let al = a.trimmingCharacters(in: .whitespaces).lowercased()
                if !al.isEmpty { resolveMap[al, default: []].append(p) }
            }
        }
        let resolveAmbiguous = Set(resolveMap.filter { $0.value.count >= 2 }.keys)

        // Resolve a header label to a UNIQUE live person — by canonical key (the phone
        // sends a matched speaker's full canonical, e.g. "Tiuri Hartog") OR an
        // unambiguous alias. nil = "Speaker N" / unknown / ambiguous → header left plain.
        func resolveHeader(_ rawName: String) -> Person? {
            let key = rawName.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty else { return nil }
            if let p = live.first(where: {
                NamesMerge.keyName($0.canonical).trimmingCharacters(in: .whitespaces).lowercased() == key
            }) { return p }
            if !resolveAmbiguous.contains(key), let cands = resolveMap[key], cands.count == 1 { return cands[0] }
            return nil
        }
        func identity(person: Person?, rawName: String) -> String {
            person.map { NamesMerge.keyName($0.canonical).lowercased() } ?? "raw:" + rawName.lowercased()
        }

        // Merge consecutive turns by the same resolved speaker (#3).
        struct MTurn { let person: Person?; let rawName: String; var text: String }
        var merged: [MTurn] = []
        for turn in parsed {
            let person = resolveHeader(turn.name)
            let id = identity(person: person, rawName: turn.name)
            if let last = merged.last, identity(person: last.person, rawName: last.rawName) == id {
                let sep = (merged[merged.count - 1].text.isEmpty || turn.text.isEmpty) ? "" : " "
                merged[merged.count - 1].text += sep + turn.text
            } else {
                merged.append(MTurn(person: person, rawName: turn.name, text: turn.text))
            }
        }

        // PASS 1 — headers claim their speaker first: a speaker's FIRST turn header carries
        // the canonical `[[Name]]` link, later headers (and every inline mention) demote to
        // the short name. This makes the labelled attribution the one link per speaker, so
        // it can't be lost to an earlier inline name-drop ("one note, one link").
        var seen = Set<String>()
        var headers: [String] = []
        for m in merged {
            if let p = m.person {
                let canonKey = NamesMerge.keyName(p.canonical).trimmingCharacters(in: .whitespaces)
                if seen.insert(canonKey.lowercased()).inserted {
                    headers.append("[[\(canonKey)]]")               // first mention → full link
                } else {
                    let short = shortName(for: p)
                    headers.append(short.isEmpty ? canonKey : short) // later → plain short name
                }
            } else {
                headers.append(m.rawName)                            // Speaker N / unknown → plain
            }
        }

        // PASS 2 — bodies in document order (the leading preamble first, then each turn),
        // sharing `seen`: each person's FIRST not-yet-linked SAFE inline mention → the
        // alias-display link, the rest → the short name. The preamble (e.g. an early image
        // marker) is preserved as its own block, never dropped.
        var blocks: [String] = []
        if !preamble.isEmpty {
            blocks.append(linkInline(preamble, overrides: ov, seen: &seen))
        }
        for (i, m) in merged.enumerated() {
            let body = linkInline(m.text, overrides: ov, seen: &seen)
            blocks.append("**\(headers[i]):** \(body)")
        }
        let finalText = blocks.joined(separator: "\n\n")
        // Suggested occurrences over the FINAL body. `seen` = everyone linked (matched
        // speakers + first-mention inline links) so they're never re-suggested.
        let suggested = suggestedOccurrences(in: finalText, overrides: ov, linkedKeys: seen)
        return Result(sanitised: finalText, ambiguous: suggested)
    }

    /// Link inline alias mentions, FIRST-ONLY per person ("one note, one link"), OPT-OUT +
    /// risk-tiered. For each person not yet linked anywhere in the conversation (`seen`),
    /// their FIRST eligible SAFE mention (a distinctive, unambiguous alias) becomes the
    /// Obsidian alias-display link `[[Canonical|short]]` (or bare `[[Canonical]]` when the
    /// short equals the canonical); every LATER mention — plus every mention of an
    /// already-linked person (a matched speaker linked in their header, or a person linked
    /// in an earlier turn) — demotes to the plain short name. A person reachable here only
    /// via an FP-prone alias (common word / too short) or an ambiguous one is NOT linked and
    /// NOT demoted — left as spoken so the suggestion pass can offer them. The display is the
    /// short, NOT the transcribed surface, so a misheard name ("cherry"/"thierry" for "Tuur")
    /// normalises to the correct short. The whole match (alias + trailing possessive) is
    /// replaced and the possessive re-appended OUTSIDE the brackets.
    ///
    /// `seen` is shared across the whole document (headers + every body) and updated in
    /// place, so each person links exactly once. Ambiguous aliases, FP-prone first mentions,
    /// non-prose spans, and matches already inside a link are left untouched.
    private static func linkInline(_ inputText: String, overrides ov: Overrides,
                                   seen: inout Set<String>) -> String {
        var text = inputText
        for p in ov.linkPeople {
            let canonKey = NamesMerge.keyName(p.canonical).trimmingCharacters(in: .whitespaces)
            let keyLower = canonKey.lowercased()
            let unambiguous = ov.ownedAliases(of: p).filter { !ov.ambiguousAliases.contains($0.lowercased()) }
            guard !unambiguous.isEmpty else { continue }
            // The display is the person's short name — fixed per person, independent of
            // what was transcribed — so every matched form normalises to it.
            let short = shortName(for: p)
            let display = (short.isEmpty || short.caseInsensitiveCompare(canonKey) == .orderedSame)
                ? "[[\(canonKey)]]"
                : "[[\(canonKey)|\(short)]]"

            if !seen.contains(keyLower) {
                // Not linked yet. Only a distinctive (non-FP-prone) alias — or a force-picked
                // one — may auto-commit a NEW inline link; a common-word/too-short-only,
                // unpicked person stays plain (suggested).
                let linkAliases = unambiguous.filter { !NameStoplist.isFpProne($0) || ov.forced[$0.lowercased()] != nil }
                guard !linkAliases.isEmpty else { continue }
                let prot = nonProseRanges(in: text)
                var earliest: (range: NSRange, poss: String)?
                for rx in linkAliases.compactMap({ wordRegex($0) }) {
                    // First ELIGIBLE match of this alias (skipping any inside a link / non-prose
                    // span — e.g. a leading audiobook quote), then take the earliest across aliases.
                    for m in rx.matches(in: text, range: fullRange(text)) where eligible(text, m.range.location, prot) {
                        if earliest == nil || m.range.location < earliest!.range.location {
                            earliest = (m.range, possText(m, in: text))
                        }
                        break
                    }
                }
                guard let first = earliest else { continue }    // no SAFE mention in this block
                text = nsReplace(text, first.range, with: display + first.poss)
                seen.insert(keyLower)
            }
            // Remaining mentions (and EVERY mention of an already-linked person) → the short
            // name, falling back to the canonical when no short is defined (so the contract
            // "every later mention demotes" holds even for a single-token name).
            let demotion = short.isEmpty ? canonKey : short
            guard !demotion.isEmpty else { continue }
            let prot = nonProseRanges(in: text)
            for rx in unambiguous.compactMap({ wordRegex($0) }) {
                for m in rx.matches(in: text, range: fullRange(text)).reversed() {
                    if !eligible(text, m.range.location, prot) { continue }
                    text = nsReplace(text, m.range, with: demotion + possText(m, in: text))
                }
            }
        }
        return text
    }

    /// The *suggested* tier (NAMING_MODEL.md): recognised-but-not-auto-linked occurrences the
    /// review surface renders dotted (commit on click), recorded over the FINAL text so
    /// offsets/contexts match what renders. Two kinds, both skipping existing links +
    /// non-prose spans:
    ///   (a) AMBIGUOUS aliases (shared by 2+ roster people) — every plain occurrence, any case;
    ///   (b) FP-PRONE single-candidate aliases (common word / too short — `NameStoplist`) whose
    ///       person did NOT auto-link — only CAPITALIZED occurrences (the capitalization
    ///       FP-guard keeps "I will call" plain while surfacing "Will came over").
    private static func suggestedOccurrences(in text: String, overrides ov: Overrides,
                                             linkedKeys: Set<String>) -> [AmbiguousOccurrence] {
        let prot = nonProseRanges(in: text)
        var out: [AmbiguousOccurrence] = []
        func record(alias: String, candidates: [Person], capitalizedOnly: Bool) {
            guard let rx = wordRegex(alias) else { return }
            for m in rx.matches(in: text, range: fullRange(text)) {
                let loc = m.range.location
                if !eligible(text, loc, prot) { continue }
                if capitalizedOnly, !startsUppercase(text, at: loc) { continue }
                out.append(AmbiguousOccurrence(
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
        // (a) ambiguous linkable aliases — every occurrence, any case.
        for alias in ov.ambiguousAliases.sorted() {
            record(alias: alias, candidates: ov.aliasMap[alias] ?? [], capitalizedOnly: false)
        }
        // (b) common-word / too-short single linkable names whose person didn't auto-link.
        for alias in ov.aliasMap.keys.sorted() where !ov.ambiguousAliases.contains(alias) {
            guard NameStoplist.isFpProne(alias), let people = ov.aliasMap[alias], people.count == 1,
                  !linkedKeys.contains(Overrides.key(people[0])) else { continue }
            record(alias: alias, candidates: people, capitalizedOnly: true)
        }
        // (c) PRUNED people whose alias no linkable person owns → dotted (re-promotable) suggestion.
        for alias in ov.prunedAliasMap.keys.sorted() {
            record(alias: alias, candidates: ov.prunedAliasMap[alias] ?? [],
                   capitalizedOnly: NameStoplist.isFpProne(alias))
        }
        return out
    }

    /// Plain (not-inside-`[[ ]]`) whole-word occurrences of `alias` in `text`, in
    /// reading order. Used by the unlink popover to count a person's plain mentions
    /// (the short-name forms the Sanitiser already left/demoted). Each range covers
    /// the alias (+ any trailing `'s`); skips matches inside an existing link.
    static func plainOccurrences(of alias: String, in text: String) -> [NSRange] {
        let a = alias.trimmingCharacters(in: .whitespaces)
        guard !a.isEmpty, let rx = wordRegex(a) else { return [] }
        return rx.matches(in: text, range: fullRange(text))
            .map { $0.range }
            .filter { !avoidInside || notInsideLink(text, $0.location) }
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
    /// entry here is what `unlinkOccurrence(index: i)` / `relinkOccurrence(index: i)`
    /// replaces — order-based, so storage-offset drift can't misapply.
    static func linkOccurrences(of canonical: String, in text: String) -> [BodyLink] {
        let key = NamesMerge.keyName(canonical).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return [] }
        return linkOccurrences(in: text).filter {
            linkTarget($0.core).caseInsensitiveCompare(key) == .orderedSame
        }
    }

    /// The canonical TARGET of a link's inner text — the part before an Obsidian
    /// alias-display pipe (`Tiuri Hartog|Tuur` → `Tiuri Hartog`), trimmed. So a
    /// `[[Canonical|spoken]]` alias-display link still resolves to its person for
    /// unlink/relink/highlight (the spoken word is display-only).
    static func linkTarget(_ core: String) -> String {
        (core.split(separator: "|", maxSplits: 1).first.map(String.init) ?? core)
            .trimmingCharacters(in: .whitespaces)
    }

    /// True when `text` already carries a `[[canonKey]]` OR `[[canonKey|display]]` link
    /// (case-insensitive) — the pipe-tolerant replacement for a literal `[[Canonical]]`
    /// substring search, so the alias-display form is recognised as an existing mention.
    private static func hasCanonicalLink(_ canonKey: String, in text: String) -> Bool {
        let key = NamesMerge.keyName(canonKey).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty,
              let rx = try? NSRegularExpression(
                pattern: "\\[\\[\(NSRegularExpression.escapedPattern(for: key))(\\|[^\\]]*)?\\]\\]",
                options: [.caseInsensitive]) else { return false }
        return rx.firstMatch(in: text, range: fullRange(text)) != nil
    }

    /// "Unlink this mention": the `index`-th `[[canonical]]` link (reading order)
    /// becomes the plain `alias` as spoken. Order-based, so the UI's storage offsets
    /// (image attachments collapse `[[img_NNN]]` markers to one character) can't
    /// misapply. A possessive sits OUTSIDE the brackets (`[[Nick Jansen]]'s`) and is
    /// left in place → `Nick's`. An out-of-range index returns the text unchanged.
    static func unlinkOccurrence(text: String, canonical: String, index: Int, alias: String) -> String {
        let links = linkOccurrences(of: canonical, in: text)
        guard index >= 0, index < links.count else { return text }
        return nsReplace(text, links[index].range, with: linkDisplay(links[index].core) ?? alias)
    }

    /// The display half of an alias-display link's core (`Tiuri Hartog|Tuur` → `Tuur`),
    /// i.e. the actual SPOKEN word — what an unlink should restore. nil for a bare
    /// `[[Canonical]]` link (no pipe), where the caller's `alias` fallback applies.
    private static func linkDisplay(_ core: String) -> String? {
        let parts = core.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let display = parts[1].trimmingCharacters(in: .whitespaces)
        return display.isEmpty ? nil : display
    }

    /// "Change to → <other person>": the `index`-th `[[canonical]]` link becomes
    /// `[[newCanonical]]` — the one-tap fix when the deterministic alias match
    /// picked the WRONG person (a spoken "Jack" auto-linked to Timmons but meant
    /// Hutton). Order-based like `unlinkOccurrence`; out-of-range = unchanged.
    static func relinkOccurrence(text: String, canonical: String, index: Int, newCanonical: String) -> String {
        let links = linkOccurrences(of: canonical, in: text)
        guard index >= 0, index < links.count else { return text }
        // Preserve an alias-display spoken word across the re-link (`[[Wrong|Tuur]]` →
        // `[[Right|Tuur]]`); a bare link stays bare.
        let repl = linkDisplay(links[index].core).map { "[[\(newCanonical)|\($0)]]" } ?? "[[\(newCanonical)]]"
        return nsReplace(text, links[index].range, with: repl)
    }

    /// "Unlink all mentions in this note": EVERY `[[canonical]]` link becomes the
    /// plain `alias`. Plain mentions are already plain and other links (other
    /// people, image markers, place links) are untouched. The caller persists the
    /// choice (`PipelineFile.unlinkedNames`) and feeds it back via
    /// `process(neverLink:)` so re-processing doesn't re-link.
    static func unlinkAll(text: String, canonical: String, alias: String) -> String {
        var out = text
        for link in linkOccurrences(of: canonical, in: text).reversed() {
            out = nsReplace(out, link.range, with: linkDisplay(link.core) ?? alias)
        }
        return out
    }

    /// Un-link EVERY known person's `[[wiki link]]` back to their SPOKEN form (the alias-display
    /// word for a `[[Canonical|spoken]]` link, else the person's short name) — the inverse of
    /// `process`, so `unlinkToSpoken` → `process` round-trips. Used by the Mac→phone live-edit
    /// write-back: the phone stores a RAW copy-edit (bracket-free editor) and re-links itself,
    /// so a manual Mac body edit must be sent un-linked to the spoken word — NOT the bare
    /// canonical, which would re-link as `[[Nick Jansen]] Jansen` (the linker re-matches the
    /// "Nick" alias inside "Nick Jansen"). Image markers (`[[img_NNN]]`) and links to people not
    /// in `people` are left untouched.
    static func unlinkToSpoken(_ text: String, people: [Person]) -> String {
        var out = text
        for p in people {
            out = unlinkAll(text: out, canonical: p.canonical, alias: spokenAlias(for: p))
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

    /// A match location is eligible for linking/suggesting when it's neither inside an
    /// existing `[[ ]]` link nor inside a non-prose span. The single gate both `process`
    /// paths + `suggestedOccurrences` use.
    private static func eligible(_ text: String, _ loc: Int, _ protectedRanges: [NSRange]) -> Bool {
        guard !avoidInside || notInsideLink(text, loc) else { return false }
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
        return ranges
    }

    /// True when the character at `loc` starts with an uppercase letter — the secondary
    /// capitalization FP-guard for common-word suggestions ("Will" the name vs "will" the verb).
    private static func startsUppercase(_ text: String, at loc: Int) -> Bool {
        let ns = text as NSString
        guard loc >= 0, loc < ns.length else { return false }
        return ns.substring(with: NSRange(location: loc, length: 1)).first?.isUppercase ?? false
    }

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
