import Foundation

/// Pure ePub → book-text extractor. Turns an ALREADY-UNZIPPED ePub (archive-relative path →
/// bytes; the zip layer itself is the conductor's, post-merge) into the flat block list the
/// aligner (`AlignmentCore`) consumes and the TOC the chapter feature consumes. Pure Foundation,
/// no I/O, no singletons, deterministic — values in, values out.
///
/// Real-world ePubs are lenient about well-formedness (named HTML entities like `&nbsp;` are
/// undefined in bare XML and hard-fail a strict parse; manifest attribute order isn't guaranteed)
/// so every spine file gets a strict `XMLParser` pass first, falling back to a regex-based
/// tag-strip when that fails. See `LANES-2026-07-21B/PLAN_EPUB.md` for the design writeup and
/// the tabled edge-case decisions.
enum EPubParse {

    enum ParseError: Error, Equatable {
        /// `META-INF/container.xml` missing from the entry set.
        case missingContainer
        /// `container.xml` has no readable `rootfile/@full-path`, or that OPF isn't in `entries`.
        case missingRootfile
        /// The OPF has no `<manifest>` or `<spine>`.
        case missingSpine
        /// Every spine file yielded zero blocks AND the book isn't DRM-protected — a genuine
        /// parse failure, distinguishable from an expected-empty protected book.
        case noReadableText
    }

    // MARK: - Public entry point

    static func parse(entries: [String: Data]) throws -> EPubBook {
        guard let containerData = entries["META-INF/container.xml"] else {
            throw ParseError.missingContainer
        }
        guard let containerRoot = parseXMLTree(containerData),
              let rootfileNode = findFirst(containerRoot, localName: "rootfile"),
              let opfPath = rootfileNode.attributes["full-path"],
              let opfData = entries[opfPath] else {
            throw ParseError.missingRootfile
        }
        guard let opfRoot = parseXMLTree(opfData),
              let manifestNode = findFirst(opfRoot, localName: "manifest"),
              let spineNode = findFirst(opfRoot, localName: "spine") else {
            throw ParseError.missingSpine
        }
        let opfDir = directory(of: opfPath)

        var manifest: [String: ManifestItem] = [:]
        for item in manifestNode.children where item.localName == "item" {
            guard let id = item.attributes["id"], let href = item.attributes["href"] else { continue }
            manifest[id] = ManifestItem(
                id: id, href: href,
                mediaType: item.attributes["media-type"] ?? "",
                properties: item.attributes["properties"] ?? "")
        }
        let spineIDs = spineNode.children
            .filter { $0.localName == "itemref" }
            .compactMap { $0.attributes["idref"] }

        var blocks: [EPubBlock] = []
        for id in spineIDs {
            guard let item = manifest[id] else { continue }
            let path = resolvePath(base: opfDir, href: item.href)
            guard let data = entries[path] else { continue }
            blocks.append(contentsOf: parseSpineBody(data: data, sourceFile: path))
        }

        let drm = evaluateDRM(entries)
        guard !blocks.isEmpty || drm != .none else {
            throw ParseError.noReadableText
        }

        let toc = resolveTOC(manifest: manifest, spineTOCAttr: spineNode.attributes["toc"],
                              opfDir: opfDir, entries: entries)
        return EPubBook(blocks: blocks, toc: toc, drm: drm)
    }

    // MARK: - Manifest item

    private struct ManifestItem {
        let id: String
        let href: String
        let mediaType: String
        let properties: String
    }

    // MARK: - Body extraction

    private static let blockTags: Set<String> = ["p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote"]

    private static func parseSpineBody(data: Data, sourceFile: String) -> [EPubBlock] {
        if let root = parseXMLTree(data) {
            let body = findFirst(root, localName: "body") ?? root
            var blocks: [EPubBlock] = []
            collectBlocks(body, sourceFile: sourceFile, into: &blocks)
            return blocks
        }
        return lenientParse(data: data, sourceFile: sourceFile)
    }

    /// True when `node` (script/style/img/a footnote marker/a footnote body) must never
    /// contribute text and must never be descended into.
    private static func shouldSkip(_ node: MiniNode) -> Bool {
        let ln = node.localName
        if ln == "script" || ln == "style" || ln == "img" { return true }
        return isFootnote(node)
    }

    private static func isFootnote(_ node: MiniNode) -> Bool {
        let epubType = (node.attributes["epub:type"] ?? "").lowercased()
        if epubType.contains("noteref") || epubType.contains("footnote") { return true }
        let cls = (node.attributes["class"] ?? "").lowercased()
        let id = (node.attributes["id"] ?? "").lowercased()
        for marker in ["footnote", "fn-", "note-"] {
            if cls.contains(marker) || id.contains(marker) { return true }
        }
        return false
    }

    /// Concatenates `#text` descendants in document order, honoring `shouldSkip`.
    private static func flattenText(_ node: MiniNode) -> String {
        var out = ""
        for child in node.children {
            if child.name == "#text" { out += child.text; continue }
            if shouldSkip(child) { continue }
            out += flattenText(child)
        }
        return out
    }

    /// Does `node`'s subtree contain a block-level element anywhere below it? Drives the
    /// "a div with no block children = one block" rule.
    private static func hasBlockDescendant(_ node: MiniNode) -> Bool {
        for child in node.children {
            guard child.name != "#text" else { continue }
            if shouldSkip(child) { continue }
            if blockTags.contains(child.localName) { return true }
            if hasBlockDescendant(child) { return true }
        }
        return false
    }

    private static func collectBlocks(_ node: MiniNode, sourceFile: String, into blocks: inout [EPubBlock]) {
        for child in node.children {
            guard child.name != "#text" else { continue }
            if shouldSkip(child) { continue }
            let ln = child.localName
            if blockTags.contains(ln) {
                let text = collapseWhitespace(flattenText(child))
                if !text.isEmpty { blocks.append(EPubBlock(text: text, sourceFile: sourceFile)) }
            } else if ln == "div", !hasBlockDescendant(child) {
                let text = collapseWhitespace(flattenText(child))
                if !text.isEmpty { blocks.append(EPubBlock(text: text, sourceFile: sourceFile)) }
            } else {
                collectBlocks(child, sourceFile: sourceFile, into: &blocks)
            }
        }
    }

    // MARK: - Lenient fallback (strict XMLParser failed on this spine file)

    private static let namedEntities: [String: String] = [
        "nbsp": " ", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "mdash": "\u{2014}", "ndash": "\u{2013}", "hellip": "\u{2026}",
        "rsquo": "\u{2019}", "lsquo": "\u{2018}", "rdquo": "\u{201D}", "ldquo": "\u{201C}",
        "shy": "",
    ]

    private static func lenientParse(data: Data, sourceFile: String) -> [EPubBlock] {
        guard var html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return []
        }
        // Strip script/style entirely (tag + content) before anything else touches them.
        html = replaceRegex(html, pattern: "<script\\b[^>]*>.*?</script>",
                             with: "", options: [.caseInsensitive, .dotMatchesLineSeparators])
        html = replaceRegex(html, pattern: "<style\\b[^>]*>.*?</style>",
                             with: "", options: [.caseInsensitive, .dotMatchesLineSeparators])
        // Best-effort, non-nested footnote strip (single tag name, open...close).
        html = replaceRegex(
            html,
            pattern: "<([a-zA-Z0-9]+)\\b[^>]*(?:epub:type\\s*=\\s*\"[^\"]*(?:noteref|footnote)[^\"]*\"" +
                     "|class\\s*=\\s*\"[^\"]*(?:footnote|fn-|note-)[^\"]*\"" +
                     "|id\\s*=\\s*\"[^\"]*(?:footnote|fn-|note-)[^\"]*\")[^>]*>.*?</\\1\\s*>",
            with: "", options: [.caseInsensitive, .dotMatchesLineSeparators])
        // Mark block boundaries at both ends of a block tag — an unclosed tag still gets a
        // boundary from the NEXT tag's opening marker.
        let blockSep = "\u{2029}"
        let blockTagPattern = "(?:p|h1|h2|h3|h4|h5|h6|li|blockquote)"
        html = replaceRegex(html, pattern: "</\(blockTagPattern)\\s*>", with: blockSep, options: [.caseInsensitive])
        html = replaceRegex(html, pattern: "<\(blockTagPattern)(?:\\s[^>]*)?>", with: blockSep, options: [.caseInsensitive])
        // Strip every remaining tag.
        html = replaceRegex(html, pattern: "<[^>]+>", with: "", options: [])
        // Entities AFTER tag-stripping, so a decoded `&lt;` never gets re-read as a tag.
        html = substituteEntities(html)
        return html.components(separatedBy: blockSep)
            .map(collapseWhitespace)
            .filter { !$0.isEmpty }
            .map { EPubBlock(text: $0, sourceFile: sourceFile) }
    }

    private static func substituteEntities(_ s: String) -> String {
        var out = s
        for (name, replacement) in namedEntities {
            out = out.replacingOccurrences(of: "&\(name);", with: replacement)
        }
        out = replaceRegexTransform(out, pattern: "&#x([0-9A-Fa-f]+);") { hex in
            guard let v = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(v) else { return "" }
            return String(Character(scalar))
        }
        out = replaceRegexTransform(out, pattern: "&#([0-9]+);") { dec in
            guard let v = UInt32(dec), let scalar = Unicode.Scalar(v) else { return "" }
            return String(Character(scalar))
        }
        return out
    }

    // MARK: - TOC

    private static func resolveTOC(manifest: [String: ManifestItem], spineTOCAttr: String?,
                                    opfDir: String, entries: [String: Data]) -> [EPubTOCEntry] {
        // EPUB3 nav doc preferred.
        if let navItem = manifest.values.first(where: {
            $0.properties.split(separator: " ").map(String.init).contains("nav")
        }) {
            let navPath = resolvePath(base: opfDir, href: navItem.href)
            if let data = entries[navPath], let root = parseXMLTree(data) {
                let found = navTOCEntries(root, base: directory(of: navPath))
                if !found.isEmpty { return found }
            }
        }
        // EPUB2 NCX fallback.
        var ncxItem: ManifestItem?
        if let tocID = spineTOCAttr { ncxItem = manifest[tocID] }
        if ncxItem == nil {
            ncxItem = manifest.values.first(where: { $0.mediaType == "application/x-dtbncx+xml" })
        }
        if let ncxItem {
            let ncxPath = resolvePath(base: opfDir, href: ncxItem.href)
            if let data = entries[ncxPath], let root = parseXMLTree(data) {
                return ncxTOCEntries(root, base: directory(of: ncxPath))
            }
        }
        return []
    }

    private static func findTOCNav(_ root: MiniNode) -> MiniNode? {
        for nav in findAll(root, localName: "nav") {
            let epubType = nav.attributes["epub:type"] ?? nav.attributes["type"] ?? ""
            if epubType.split(separator: " ").map(String.init).contains("toc") { return nav }
        }
        return nil
    }

    private static func navTOCEntries(_ root: MiniNode, base: String) -> [EPubTOCEntry] {
        guard let nav = findTOCNav(root) else { return [] }
        var out: [EPubTOCEntry] = []
        for a in findAll(nav, localName: "a") {
            guard let href = a.attributes["href"] else { continue }
            let title = collapseWhitespace(flattenText(a))
            guard !title.isEmpty else { continue }
            let (relPath, fragment) = splitFragment(href)
            let path = relPath.isEmpty ? "" : resolvePath(base: base, href: relPath)
            out.append(EPubTOCEntry(title: title, sourceFile: path, fragment: fragment))
        }
        return out
    }

    private static func ncxTOCEntries(_ root: MiniNode, base: String) -> [EPubTOCEntry] {
        guard let navMap = findFirst(root, localName: "navMap") else { return [] }
        var out: [EPubTOCEntry] = []
        func walk(_ node: MiniNode) {
            for np in node.children where np.localName == "navPoint" {
                let label = findFirst(np, localName: "navLabel")
                    .flatMap { findFirst($0, localName: "text") }
                    .map { collapseWhitespace(flattenText($0)) } ?? ""
                if let contentNode = findFirst(np, localName: "content"),
                   let src = contentNode.attributes["src"], !label.isEmpty {
                    let (relPath, fragment) = splitFragment(src)
                    let path = resolvePath(base: base, href: relPath)
                    out.append(EPubTOCEntry(title: label, sourceFile: path, fragment: fragment))
                }
                walk(np)
            }
        }
        walk(navMap)
        return out
    }

    // MARK: - DRM

    private static let fontObfuscationURIs: Set<String> = [
        "http://www.idpf.org/2008/embedding",
        "http://ns.adobe.com/pdf/enc#RC",
    ]

    private static func evaluateDRM(_ entries: [String: Data]) -> EPubDRMVerdict {
        guard let encData = entries["META-INF/encryption.xml"] else { return .none }
        let hasRights = entries["META-INF/rights.xml"] != nil
        if hasRights { return .protected(reason: "ADEPT rights.xml present") }
        guard let root = parseXMLTree(encData) else {
            return .protected(reason: "encryption.xml present but could not be parsed")
        }
        let algorithms = findAll(root, localName: "EncryptionMethod").compactMap { $0.attributes["Algorithm"] }
        if algorithms.isEmpty {
            return .protected(reason: "encryption.xml present with no recognized algorithm")
        }
        if algorithms.allSatisfy({ fontObfuscationURIs.contains($0) }) {
            return .none
        }
        let unknown = algorithms.first { !fontObfuscationURIs.contains($0) } ?? algorithms[0]
        return .protected(reason: "encrypted content (algorithm: \(unknown))")
    }

    // MARK: - Path resolution

    private static func directory(of path: String) -> String {
        guard let idx = path.lastIndex(of: "/") else { return "" }
        return String(path[..<idx])
    }

    private static func splitFragment(_ href: String) -> (path: String, fragment: String?) {
        guard let hashIdx = href.firstIndex(of: "#") else { return (href, nil) }
        let path = String(href[..<hashIdx])
        let frag = String(href[href.index(after: hashIdx)...])
        return (path, frag.isEmpty ? nil : frag)
    }

    private static func resolvePath(base: String, href: String) -> String {
        let (rawPath, _) = splitFragment(href)
        let decoded = rawPath.removingPercentEncoding ?? rawPath
        if decoded.hasPrefix("/") { return String(decoded.dropFirst()) }
        var baseComponents = base.isEmpty ? [] : base.split(separator: "/").map(String.init)
        for comp in decoded.split(separator: "/") {
            if comp == "." { continue }
            if comp == ".." { if !baseComponents.isEmpty { baseComponents.removeLast() }; continue }
            baseComponents.append(String(comp))
        }
        return baseComponents.joined(separator: "/")
    }

    // MARK: - Text utilities

    private static func collapseWhitespace(_ s: String) -> String {
        replaceRegex(s, pattern: "\\s+", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replaceRegex(_ s: String, pattern: String, with template: String,
                                      options: NSRegularExpression.Options = []) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: template)
    }

    private static func replaceRegexTransform(_ s: String, pattern: String,
                                               transform: (String) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var result = ""
        var last = 0
        re.enumerateMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            let full = match.range
            result += ns.substring(with: NSRange(location: last, length: full.location - last))
            let captured = ns.substring(with: match.range(at: 1))
            result += transform(captured)
            last = full.location + full.length
        }
        result += ns.substring(from: last)
        return result
    }

    // MARK: - Minimal in-memory XML tree (one XMLParser pass, no namespace processing)

    private final class MiniNode {
        let name: String
        var text: String = ""
        var attributes: [String: String] = [:]
        var children: [MiniNode] = []
        init(name: String) { self.name = name }
        var localName: String {
            guard let idx = name.lastIndex(of: ":") else { return name }
            return String(name[name.index(after: idx)...])
        }
    }

    private final class TreeBuilder: NSObject, XMLParserDelegate {
        let root = MiniNode(name: "#root")
        private var stack: [MiniNode]
        private(set) var failed = false

        override init() {
            stack = []
            super.init()
            stack = [root]
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes attributeDict: [String: String]) {
            let node = MiniNode(name: elementName)
            node.attributes = attributeDict
            stack.last?.children.append(node)
            stack.append(node)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?) {
            if stack.count > 1 { stack.removeLast() }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard let top = stack.last else { return }
            if let last = top.children.last, last.name == "#text" {
                last.text += string
            } else {
                let t = MiniNode(name: "#text")
                t.text = string
                top.children.append(t)
            }
        }

        func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
            failed = true
        }
    }

    private static func parseXMLTree(_ data: Data) -> MiniNode? {
        let builder = TreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        let ok = parser.parse()
        guard ok, !builder.failed else { return nil }
        return builder.root
    }

    private static func findFirst(_ node: MiniNode, localName target: String) -> MiniNode? {
        for child in node.children {
            if child.localName == target { return child }
            if let found = findFirst(child, localName: target) { return found }
        }
        return nil
    }

    private static func findAll(_ node: MiniNode, localName target: String) -> [MiniNode] {
        var out: [MiniNode] = []
        for child in node.children {
            if child.localName == target { out.append(child) }
            out.append(contentsOf: findAll(child, localName: target))
        }
        return out
    }
}

// MARK: - Public value types (pinned names — LANE_ALIGN's Block structurally mirrors EPubBlock
// on purpose but never imports it; see LANES-2026-07-21B/BASE.md)

struct EPubBlock: Equatable, Sendable {
    let text: String
    let sourceFile: String
}

struct EPubTOCEntry: Equatable, Sendable {
    let title: String
    let sourceFile: String
    let fragment: String?
}

enum EPubDRMVerdict: Equatable, Sendable {
    case none
    case protected(reason: String)
}

struct EPubBook: Equatable, Sendable {
    let blocks: [EPubBlock]
    let toc: [EPubTOCEntry]
    let drm: EPubDRMVerdict
}
