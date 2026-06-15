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
    ///
    /// `aboutPeople` is the OPT-IN naming gate (mocks/opt-in-naming.html): when non-nil,
    /// only the people whose canonical key it lists are linked — everyone else stays
    /// plain. An EMPTY set links NOBODY (a fresh note before the user taps any chip).
    /// `nil` = ungated: link every matching person (the matching engine's raw behavior,
    /// exercised by engine-level tests). The product callers (`BatchRunner` /
    /// `ProcessingCoordinator`) ALWAYS pass the note's `aboutPeople`, so the product
    /// never auto-links. The gate is applied BEFORE ambiguity is computed, so tapping
    /// ONE of two people who share an alias links them (the alias is unambiguous within
    /// the gated set), while tapping BOTH records the alias as ambiguous for the resolver.
    static func process(text inputText: String, people: [Person], neverLink: Set<String> = [], aboutPeople: Set<String>? = nil) -> Result {
        var text = inputText
        let skip = Set(neverLink.map { NamesMerge.keyName($0).trimmingCharacters(in: .whitespaces).lowercased() })
        let live = people.filter {
            !$0.isDeleted && !skip.contains(NamesMerge.keyName($0.canonical).trimmingCharacters(in: .whitespaces).lowercased())
        }
        // Opt-in gate: link only the people the note is about (nil = ungated = all).
        let linkable = gated(live, by: aboutPeople)

        var aliasMap: [String: [Person]] = [:]
        for p in linkable {
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
        for p in linkable.sorted(by: { NamesMerge.keyName($0.canonical).lowercased() < NamesMerge.keyName($1.canonical).lowercased() }) {
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
    /// `aboutPeople` is the opt-in gate: only matched SPEAKERS (auto-linked in their header)
    /// and the people whose canonical it lists earn inline links; everyone else stays plain.
    /// `nil` = ungated (link every unambiguous mention, still first-only). Falls back to
    /// `process` when the text isn't actually attributed.
    static func processConversation(text inputText: String, people: [Person], neverLink: Set<String> = [], aboutPeople: Set<String>? = nil) -> Result {
        guard let parsedWP = SpeakerTranscript.parseWithPreamble(inputText) else {
            return process(text: inputText, people: people, neverLink: neverLink, aboutPeople: aboutPeople)
        }
        let parsed = parsedWP.turns
        let preamble = parsedWP.preamble
        let skip = Set(neverLink.map { NamesMerge.keyName($0).trimmingCharacters(in: .whitespaces).lowercased() })
        let live = people.filter {
            !$0.isDeleted && !skip.contains(NamesMerge.keyName($0.canonical).trimmingCharacters(in: .whitespaces).lowercased())
        }

        // FULL alias map (over all live people) — resolves matched-speaker headers, which
        // auto-link regardless of the opt-in gate (a speaker is definitionally a subject).
        var aliasMap: [String: [Person]] = [:]
        for p in live {
            for a in p.aliases {
                let al = a.trimmingCharacters(in: .whitespaces).lowercased()
                if !al.isEmpty { aliasMap[al, default: []].append(p) }
            }
        }
        let ambiguousAliases = Set(aliasMap.filter { $0.value.count >= 2 }.keys)

        // Resolve a header label to a UNIQUE live person — by canonical key (the phone
        // sends a matched speaker's full canonical, e.g. "Tiuri Hartog") OR an
        // unambiguous alias. nil = "Speaker N" / unknown / ambiguous → header left plain.
        func resolveHeader(_ rawName: String) -> Person? {
            let key = rawName.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty else { return nil }
            if let p = live.first(where: {
                NamesMerge.keyName($0.canonical).trimmingCharacters(in: .whitespaces).lowercased() == key
            }) { return p }
            if !ambiguousAliases.contains(key), let cands = aliasMap[key], cands.count == 1 { return cands[0] }
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

        // Opt-in gate for INLINE mentions: only an about-person earns a NEW inline link
        // (matched speakers are linked in their header → tracked in `seen` → their inline
        // mentions demote to the short name regardless of this set). nil = ungated.
        let inlineLinkable: Set<String>? = aboutPeople.map {
            Set($0.map { NamesMerge.keyName($0).trimmingCharacters(in: .whitespaces).lowercased() })
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
        // sharing `seen`: each person's FIRST not-yet-linked inline mention → the
        // alias-display link, the rest → the short name. The preamble (e.g. an early image
        // marker) is preserved as its own block, never dropped.
        var blocks: [String] = []
        if !preamble.isEmpty {
            blocks.append(linkInline(preamble, live: live, ambiguousAliases: ambiguousAliases,
                                     linkable: inlineLinkable, seen: &seen))
        }
        for (i, m) in merged.enumerated() {
            let body = linkInline(m.text, live: live, ambiguousAliases: ambiguousAliases,
                                  linkable: inlineLinkable, seen: &seen)
            blocks.append("**\(headers[i]):** \(body)")
        }
        let finalText = blocks.joined(separator: "\n\n")
        let ambiguous = ambiguousOccurrences(in: finalText, aliasMap: aliasMap, ambiguousAliases: ambiguousAliases)
        return Result(sanitised: finalText, ambiguous: ambiguous)
    }

    /// Link inline alias mentions, FIRST-ONLY per person ("one note, one link"). For each
    /// person not yet linked anywhere in the conversation (`seen`), their FIRST eligible
    /// mention becomes the Obsidian alias-display link `[[Canonical|short]]` (or bare
    /// `[[Canonical]]` when the short equals the canonical) and every LATER mention — plus
    /// every mention of an already-linked person (a matched speaker linked in their header,
    /// or a person linked in an earlier turn) — demotes to the plain short name. The display
    /// is the short, NOT the transcribed surface, so a misheard name ("cherry"/"thierry" for
    /// "Tuur") normalises to the correct short. The whole match (alias + trailing possessive)
    /// is replaced and the possessive re-appended OUTSIDE the brackets.
    ///
    /// `linkable` is the opt-in gate (nil = ungated): a person NOT already linked may earn a
    /// NEW inline link only when their canonical is in this set. A person already in `seen` is
    /// demoted to the short regardless (their link lives elsewhere). Ambiguous aliases and
    /// matches already inside a link are left untouched. `seen` is shared across the whole
    /// document (headers + every body) and updated in place, so each person links exactly once.
    private static func linkInline(_ inputText: String, live: [Person], ambiguousAliases: Set<String>,
                                   linkable: Set<String>?, seen: inout Set<String>) -> String {
        var text = inputText
        for p in live.sorted(by: { NamesMerge.keyName($0.canonical).lowercased() < NamesMerge.keyName($1.canonical).lowercased() }) {
            let canonKey = NamesMerge.keyName(p.canonical).trimmingCharacters(in: .whitespaces)
            let keyLower = canonKey.lowercased()
            let aliases = p.aliases
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !ambiguousAliases.contains($0.lowercased()) }
            guard !aliases.isEmpty else { continue }
            // The display is the person's short name — fixed per person, independent of
            // what was transcribed — so every matched form normalises to it.
            let short = shortName(for: p)
            let display = (short.isEmpty || short.caseInsensitiveCompare(canonKey) == .orderedSame)
                ? "[[\(canonKey)]]"
                : "[[\(canonKey)|\(short)]]"
            let patterns = aliases.compactMap { wordRegex($0) }

            if !seen.contains(keyLower) {
                // Not linked yet. The opt-in gate decides whether they may link here at all;
                // a non-about, non-speaker person stays entirely plain.
                guard linkable?.contains(keyLower) ?? true else { continue }
                // First eligible mention across the person's aliases → the alias-display link.
                var earliest: (range: NSRange, poss: String)?
                for rx in patterns {
                    guard let m = rx.firstMatch(in: text, range: fullRange(text)) else { continue }
                    if avoidInside && !notInsideLink(text, m.range.location) { continue }
                    if earliest == nil || m.range.location < earliest!.range.location {
                        earliest = (m.range, possText(m, in: text))
                    }
                }
                guard let first = earliest else { continue }    // no eligible mention in this block
                text = nsReplace(text, first.range, with: display + first.poss)
                seen.insert(keyLower)
            }
            // Remaining mentions (and EVERY mention of an already-linked person) → the short.
            guard !short.isEmpty else { continue }
            for rx in patterns {
                for m in rx.matches(in: text, range: fullRange(text)).reversed() {
                    if avoidInside && !notInsideLink(text, m.range.location) { continue }
                    text = nsReplace(text, m.range, with: short + possText(m, in: text))
                }
            }
        }
        return text
    }

    /// Ambiguous-alias occurrences (plain whole-word mentions of an alias that maps to 2+
    /// people, not inside a link) over `text`, with offsets into `text` — the same
    /// detection `process` uses, factored out so the conversation path records them
    /// against the FINAL rendered body.
    private static func ambiguousOccurrences(in text: String, aliasMap: [String: [Person]], ambiguousAliases: Set<String>) -> [AmbiguousOccurrence] {
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
        return ambiguous
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
            // pre-linked mention, bare OR `[[Canonical|alias]]`) — then every plain
            // occurrence is a LATER mention.
            let alreadyLinked = hasCanonicalLink(core, in: text)
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
                // A canonical the body already links (e.g. a turn header, bare or
                // `[[Canonical|alias]]`) counts as introduced — plain mentions get the short name.
                let isFirst = !introduced.contains(core) && !hasCanonicalLink(core, in: text)
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
                    let isFirst = !introduced.contains(core) && !hasCanonicalLink(core, in: inputText)
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

    /// The plain text a mention reads as once unlinked — the SAME short-name rule
    /// `process` uses when demoting later mentions (short override → first word of
    /// the canonical), falling back to the bare canonical.
    static func spokenAlias(for p: Person) -> String {
        let short = shortName(for: p)
        if !short.isEmpty { return short }
        return NamesMerge.keyName(p.canonical).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Helpers

    /// Apply the opt-in naming gate: `nil` returns `live` unchanged (ungated); a set
    /// keeps only the people whose canonical key it contains (matched case-insensitively,
    /// bracket-tolerant). An empty set → nobody. The single source of the gate logic for
    /// both `process` and `processConversation`.
    private static func gated(_ live: [Person], by aboutPeople: Set<String>?) -> [Person] {
        guard let aboutPeople else { return live }
        let about = Set(aboutPeople.map { NamesMerge.keyName($0).trimmingCharacters(in: .whitespaces).lowercased() })
        return live.filter {
            about.contains(NamesMerge.keyName($0.canonical).trimmingCharacters(in: .whitespaces).lowercased())
        }
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
