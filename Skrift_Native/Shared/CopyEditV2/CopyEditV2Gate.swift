import Foundation

extension CopyEditV2 {
    /// The post-conditions on every copy-edit output (C177, C35), checked against the prose the
    /// model was given. A failed gate ships the unedited body; the prompt is not the cure.
    enum Gate {
        /// The only words a copy-edit may drop outright (C35: "Fillers (um/uh/eh)"). Repeats go
        /// too: the check is per distinct word, so a word kept once is kept.
        static let fillers: Set<String> = ["um", "uh", "eh", "uhm", "umm", "uhh", "ehm", "erm", "hmm", "mm"]

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
            if !lostWords(input: input, output: output).isEmpty { return .wordLost }
            return nil
        }

        /// Lower-cased words, curly apostrophes read as straight ones.
        static func words(_ s: String) -> [String] {
            s.lowercased().replacingOccurrences(of: "’", with: "'")
                .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
                .filter { !$0.isEmpty }
        }

        /// C35: every distinct word of the input that is not a filler is still in the output.
        static func lostWords(input: String, output: String) -> [String] {
            let kept = Set(words(output))
            var seen = Set<String>()
            return words(input).filter { !fillers.contains($0) && seen.insert($0).inserted && !kept.contains($0) }
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
