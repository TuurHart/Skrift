import Foundation

extension CopyEditV2 {
    /// D215: lines the model never sees, held aside like pictures and put back in place.
    /// Checkbox lines (`- [ ]` / `- [x]`) and heading lines (`# …` to `###### …`, Q501) always,
    /// so a task keeps its box and its state and a heading stays his; every list line (`- `,
    /// `* `, `1. `) of a TYPED note, so a typed list stays a list. A run of
    /// held lines is one block: a block that was a paragraph of its own returns as one after the
    /// same number of edited paragraphs; a block inside a paragraph returns inside the same-index
    /// edited paragraph, at its line when the paragraph kept its line count, else at its edge.
    struct HeldLines {
        struct Block: Equatable {
            let lines: [String]
            /// Own paragraph: the number of model paragraphs before it. Inside one: that paragraph's index.
            let para: Int
            /// Inside a paragraph: the number of that paragraph's model lines before it.
            let line: Int
            let own: Bool
        }

        /// What the model reads: the text with every held line out. Byte-identical to the input
        /// when nothing is held.
        let prose: String
        let blocks: [Block]
        /// Lines per model paragraph, as the model was given them.
        let lineCounts: [Int]

        static let checkboxRegex = try! NSRegularExpression(pattern: #"^[ \t]*(?:[-*+]|\d+[.)])[ \t]+\[[ xX]\]"#)
        static let listRegex = try! NSRegularExpression(pattern: #"^[ \t]*(?:[-*+]|\d+[.)])[ \t]+\S"#)
        static let headingRegex = try! NSRegularExpression(pattern: #"^[ ]{0,3}#{1,6}[ \t]+\S"#)

        static func isHeld(_ line: String, typed: Bool) -> Bool {
            let r = NSRange(location: 0, length: (line as NSString).length)
            if headingRegex.firstMatch(in: line, range: r) != nil { return true }
            return (typed ? listRegex : checkboxRegex).firstMatch(in: line, range: r) != nil
        }

        init(_ text: String, typed: Bool) {
            guard text.components(separatedBy: "\n").contains(where: { Self.isHeld($0, typed: typed) }) else {
                prose = text; blocks = []; lineCounts = []
                return
            }
            var model: [String] = [], counts: [Int] = [], blocks: [Block] = []
            for para in CopyEditV2.paragraphs(text) {
                var textLines: [String] = [], run: [String] = []
                var inner: [(lines: [String], line: Int)] = []
                for line in para.components(separatedBy: "\n") {
                    if Self.isHeld(line, typed: typed) { run.append(line); continue }
                    if !run.isEmpty { inner.append((run, textLines.count)); run = [] }
                    textLines.append(line)
                }
                if !run.isEmpty { inner.append((run, textLines.count)) }
                if textLines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    blocks.append(Block(lines: inner.flatMap(\.lines), para: model.count, line: 0, own: true))
                } else {
                    blocks += inner.map { Block(lines: $0.lines, para: model.count, line: $0.line, own: false) }
                    model.append(textLines.joined(separator: "\n"))
                    counts.append(textLines.count)
                }
            }
            prose = model.joined(separator: "\n\n")
            self.blocks = blocks
            lineCounts = counts
        }

        /// Every held block back into `edited`, in its original order.
        func putBack(_ edited: String) -> String {
            guard !blocks.isEmpty else { return edited }
            let paras = CopyEditV2.paragraphs(edited)
            var out: [String] = []
            for k in 0...paras.count {
                // Own blocks before paragraph k; a block inside a paragraph the edit no longer has, at the end.
                out += blocks.filter { $0.own ? Swift.min($0.para, paras.count) == k : ($0.para >= paras.count && k == paras.count) }
                    .map { $0.lines.joined(separator: "\n") }
                guard k < paras.count else { break }
                let inside = blocks.filter { !$0.own && $0.para == k }
                out.append(inside.isEmpty ? paras[k] : Self.merge(paras[k], inside,
                                                                  inputLines: k < lineCounts.count ? lineCounts[k] : -1))
            }
            return out.joined(separator: "\n\n")
        }

        private static func merge(_ para: String, _ inside: [Block], inputLines: Int) -> String {
            var lines = para.components(separatedBy: "\n")
            if lines.count == inputLines {
                for b in inside.reversed() { lines.insert(contentsOf: b.lines, at: Swift.min(b.line, lines.count)) }
                return lines.joined(separator: "\n")
            }
            let head = inside.filter { $0.line == 0 }.flatMap(\.lines)
            let tail = inside.filter { $0.line != 0 }.flatMap(\.lines)
            return (head + lines + tail).joined(separator: "\n")
        }
    }
}

extension CopyEditV2 {
    /// Q501 (D215): bold and italic markup the model never sees. Each `**x**` / `__x__` / `*x*` /
    /// `_x_` span reaches the model as its bare text and is wrapped back around the first
    /// case-insensitive match of that text, in order; a span whose text the edit no longer says
    /// means the formatting was lost, and the note ships his words. `_` counts only between
    /// non-word characters, so snake_case and URLs are left alone.
    struct HeldEmphasis {
        struct Span: Equatable { let marker: String; let text: String }

        /// What the model reads: the text with each span's markup out. Byte-identical when none.
        let prose: String
        let spans: [Span]

        static let regex = try! NSRegularExpression(pattern:
            #"(\*\*)(?=\S)([^\n]+?)(?<=\S)\*\*"#
            + #"|(?<![_\w])(__)(?=\S)([^\n]+?)(?<=\S)__(?![_\w])"#
            + #"|(?<![*\w])(\*)(?=[^\s*])([^*\n]+?)(?<=\S)\*(?![*\w])"#
            + #"|(?<![_\w])(_)(?=[^\s_])([^_\n]+?)(?<=\S)_(?![_\w])"#)

        init(_ text: String) {
            let ns = text as NSString
            var spans: [Span] = []
            var out = "", last = 0
            for m in Self.regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let pair = [(1, 2), (3, 4), (5, 6), (7, 8)].first { m.range(at: $0.0).location != NSNotFound }!
                let marker = ns.substring(with: m.range(at: pair.0)), inner = ns.substring(with: m.range(at: pair.1))
                out += ns.substring(with: NSRange(location: last, length: m.range.location - last)) + inner
                last = m.range.location + m.range.length
                spans.append(Span(marker: marker, text: inner))
            }
            out += ns.substring(from: last)
            prose = spans.isEmpty ? text : out
            self.spans = spans
        }

        /// Every span's markup back around its text in `edited`, in order; the edited casing is
        /// kept. nil = a span's text did not survive the edit.
        func putBack(_ edited: String) -> String? {
            guard !spans.isEmpty else { return edited }
            let ns = NSMutableString(string: edited)
            var from = 0
            for span in spans {
                let r = ns.range(of: span.text, options: .caseInsensitive,
                                 range: NSRange(location: from, length: ns.length - from))
                guard r.location != NSNotFound else { return nil }
                let wrapped = span.marker + ns.substring(with: r) + span.marker
                ns.replaceCharacters(in: r, with: wrapped)
                from = r.location + (wrapped as NSString).length
            }
            return ns as String
        }
    }
}
