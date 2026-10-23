import Foundation

extension CopyEditV2 {
    /// The post-conditions on every copy-edit output (C177, C35), checked against the prose the
    /// model was given. A failed gate ships the unedited body; the prompt is not the cure.
    /// D209: the gate fails only on real damage — a translation, a lost name or number, an
    /// invented proper noun. A dropped ordinary word is the price of a model; the edit ships.
    enum Gate {
        /// Fillers (C35: "um/uh/eh"). `lostWords` skips them: it reports what else an edit dropped.
        static let fillers: Set<String> = ["um", "uh", "eh", "uhm", "umm", "uhh", "ehm", "erm", "hmm", "mm"]

        /// Number words, English and Dutch (C35: "numbers ... stay"). "een" is left out: in Dutch
        /// it is the article far more often than the number.
        static let numberWords: Set<String> = Set("""
            zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen \
            fifteen sixteen seventeen eighteen nineteen twenty thirty forty fifty sixty seventy eighty \
            ninety hundred thousand million billion half dozen \
            nul twee drie vier vijf zes zeven acht negen tien elf twaalf dertien veertien vijftien \
            zestien zeventien achttien negentien twintig dertig veertig vijftig zestig zeventig tachtig \
            negentig honderd duizend miljoen half
            """.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))

        /// Words a language's text carries and the other's does not — the language-flip gauge.
        static let english: Set<String> = Set("""
            the and that this with for have has but not you they what there just are it to so like my our \
            would will should can from about which when then because been people also really very these \
            those your if into than
            """.split(separator: " ").map(String.init))
        static let dutch: Set<String> = Set("""
            de het een en dat niet maar ook ik je jij wij zij hij van voor met naar dus nog wel heb heeft \
            hebben zijn mijn er als dan moet kan wat die deze dit gewoon echt mensen om te aan bij uit zo \
            geen nu hier daar veel even wordt worden
            """.split(separator: " ").map(String.init))

        static func check(input: String, output: String) -> Fallback? {
            if !newProperNouns(input: input, output: output).isEmpty { return .newProperNoun }
            if languageFlipped(input: input, output: output) { return .languageFlip }
            if !lostNamesOrNumbers(input: input, output: output).isEmpty { return .nameOrNumberLost }
            if !respelled(input: input, output: output).isEmpty { return .respelled }
            if !lostSentences(input: input, output: output).isEmpty { return .sentenceLost }
            return nil
        }

        // MARK: - D215: his sentences and his spelling

        /// Words a copy-edit may drop as a whole sentence ("Yeah.", "Okay so."): fillers and
        /// discourse words. D215: dropping fillers and "okay so" stays.
        static let discourse: Set<String> = fillers.union([
            "okay", "ok", "oke", "oké", "so", "yeah", "yep", "yes", "right", "well", "anyway", "alright",
            "ja", "nou",
        ])

        /// D215: a note under this many words that loses a whole sentence falls back (above it,
        /// the C33 shrink guard looks).
        static let shortNoteWords = 40

        /// D215: in a note under 40 words, the input sentences the output no longer says — more
        /// than half of a sentence's words (fillers and discourse words aside) gone from the output.
        static func lostSentences(input: String, output: String) -> [String] {
            guard input.split(whereSeparator: \.isWhitespace).count < shortNoteWords else { return [] }
            let kept = Set(words(output))
            return sentences(input).filter { s in
                let content = Set(words(s)).subtracting(discourse)
                guard !content.isEmpty else { return false }
                return content.filter(kept.contains).count * 2 < content.count
            }
        }

        /// The sentences of a text: split after . ! ? … and at every line break.
        static func sentences(_ s: String) -> [String] {
            s.replacingOccurrences(of: #"(?<=[.!?…])\s+"#, with: "\n", options: .regularExpression)
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        /// British / American pairs no suffix rule reaches.
        private static let spellingPairs: [String: String] = [
            "grey": "gray", "greys": "grays", "greyish": "grayish", "tyre": "tire", "tyres": "tires",
            "aluminium": "aluminum", "programme": "program", "programmes": "programs", "plough": "plow",
            "mould": "mold", "moulds": "molds", "sceptical": "skeptical", "defence": "defense",
            "offence": "offense", "licence": "license", "pretence": "pretense", "jewellery": "jewelry",
            "whisky": "whiskey", "draught": "draft", "storey": "story", "pyjamas": "pajamas",
        ]

        /// The spelling-neutral form of a word: colour/color, apologising/apologizing,
        /// centre/center, travelling/traveling, analyse/analyze, catalogue/catalog → one key.
        static func spellingKey(_ w: String) -> String {
            if let us = spellingPairs[w] { return us }
            var k = w
            for (pattern, template) in spellingRules {
                k = k.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
            }
            return k
        }

        private static let spellingRules: [(String, String)] = [
            (#"^(\p{L}{3,})our(s|ed|ing|ite|ites|able|er|ers|ful|less)?$"#, "$1or$2"),
            (#"^(\p{L}{3,})is(e|es|ed|ing|er|ers|ation|ations)$"#, "$1iz$2"),
            (#"^(\p{L}{2,})ys(e|es|ed|ing)$"#, "$1yz$2"),
            (#"^(\p{L}{3,})(t|b)re(s)?$"#, "$1$2er$3"),
            (#"^(\p{L}{3,}[aeiou])ll(ing|ed|er|ers)$"#, "$1l$2"),
            (#"^(\p{L}{3,})ogue(s)?$"#, "$1og$2"),
        ]

        /// D215: input words the output replaced by a spelling variant ("colour→color"): the input
        /// word is gone, and the output says a word the input never did with the same spelling key.
        static func respelled(input: String, output: String) -> [String] {
            let inWords = Set(words(input)), outWords = Set(words(output))
            var byKey: [String: String] = [:]
            for w in outWords.subtracting(inWords) { byKey[spellingKey(w)] = w }
            guard !byKey.isEmpty else { return [] }
            return inWords.subtracting(outWords).sorted().compactMap { w in
                byKey[spellingKey(w)].map { "\(w)→\($0)" }
            }
        }

        /// Lower-cased words, curly apostrophes read as straight ones.
        static func words(_ s: String) -> [String] {
            s.lowercased().replacingOccurrences(of: "’", with: "'")
                .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
                .filter { !$0.isEmpty }
        }

        /// Every distinct word of the input, fillers aside, that the output no longer says. A
        /// report, not a gate (D209): `check` fails only on the names and numbers among them.
        static func lostWords(input: String, output: String) -> [String] {
            let kept = Set(words(output))
            var seen = Set<String>()
            return words(input).filter { !fillers.contains($0) && seen.insert($0).inserted && !kept.contains($0) }
        }

        /// C35 / D209: the names and numbers of the input the output no longer says. A name is a
        /// capitalised word inside a sentence (a link reaches the model as its shown text, so a
        /// linked name counts); its possessive survives as the bare name. A number is a word with
        /// a digit or a number word.
        static func lostNamesOrNumbers(input: String, output: String) -> [String] {
            let out = words(output)
            let kept = Set(out).union(out.map(stem))
            var seen = Set<String>(), lost: [String] = []
            for w in names(in: input) + words(input).filter(isNumber)
            where seen.insert(w).inserted && !kept.contains(w) && !kept.contains(stem(w)) {
                lost.append(w)
            }
            return lost
        }

        static func isNumber(_ w: String) -> Bool {
            w.contains(where: \.isNumber) || numberWords.contains(w)
        }

        private static func stem(_ w: String) -> String { w.hasSuffix("'s") ? String(w.dropLast(2)) : w }

        /// The capitalised words inside a sentence, lower-cased ("I" aside).
        static func names(in text: String) -> [String] {
            let ns = text as NSString
            return properNounRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
                guard !startsSentence(ns, at: m.range.location), !followsLetter(ns, m.range.location) else { return nil }
                let w = words(ns.substring(with: m.range)).first ?? ""
                return w.isEmpty || ["i", "i'm", "i've", "i'll", "i'd"].contains(w) ? nil : w
            }
        }

        private static let properNounRegex = try! NSRegularExpression(pattern: #"\p{Lu}[\p{L}\p{M}\p{N}'’]*"#)

        private static func followsLetter(_ ns: NSString, _ location: Int) -> Bool {
            location > 0 && CharacterSet.letters.contains(ns.substring(with: NSRange(location: location - 1, length: 1)).unicodeScalars.first!)
        }

        /// C177: a capitalised word inside a sentence that the input never says (any casing).
        static func newProperNouns(input: String, output: String) -> [String] {
            let known = Set(words(input))
            let ns = output as NSString
            let regex = try! NSRegularExpression(pattern: #"\p{Lu}[\p{L}\p{M}\p{N}'’]*"#)
            var found: [String] = []
            for m in regex.matches(in: output, range: NSRange(location: 0, length: ns.length)) {
                let word = ns.substring(with: m.range)
                guard !startsSentence(ns, at: m.range.location) else { continue }
                if m.range.location > 0, CharacterSet.letters.contains(ns.substring(with: NSRange(location: m.range.location - 1, length: 1)).unicodeScalars.first!) { continue }
                let w = words(word).first ?? ""
                let stem = w.hasSuffix("'s") ? String(w.dropLast(2)) : w
                if ["i", "i'm", "i've", "i'll", "i'd"].contains(w) || known.contains(w) || known.contains(stem) { continue }
                found.append(word)
            }
            return found
        }

        /// The first word of the text, a line, or a sentence (after . ! ? : and any quote,
        /// bracket, bullet or heading mark).
        private static func startsSentence(_ ns: NSString, at location: Int) -> Bool {
            var i = location - 1
            while i >= 0 {
                let c = ns.substring(with: NSRange(location: i, length: 1))
                if c == " " || c == "\t" || "\"“”'‘(*_#->[".contains(c) || c.first?.isNumber == true { i -= 1; continue }
                return c == "\n" || ".!?:…".contains(c)
            }
            return true
        }

        /// C177 / C35: the language never flips. A language the input speaks (≥ 3 of its own
        /// words) keeps at least half of them, and the English share moves by at most 0.2.
        static func languageFlipped(input: String, output: String) -> Bool {
            func count(_ s: String) -> (en: Int, nl: Int) {
                let w = words(s)
                return (w.filter(english.contains).count, w.filter(dutch.contains).count)
            }
            let a = count(input), b = count(output)
            if a.en >= 3, b.en * 2 < a.en { return true }
            if a.nl >= 3, b.nl * 2 < a.nl { return true }
            guard a.en + a.nl >= 8, b.en + b.nl > 0 else { return false }
            let shareIn = Double(a.en) / Double(a.en + a.nl), shareOut = Double(b.en) / Double(b.en + b.nl)
            return abs(shareIn - shareOut) > 0.2
        }
    }
}
