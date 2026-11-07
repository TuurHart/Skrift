import Foundation

/// The ONE containment check for every place a name or path that came from outside the app
/// (a `.skriftbook` entry, a synced filename, a shared file's name, an Apple Note's attachment
/// reference) becomes a file path (Q534). Foundation only, so both apps and the host-less Mac
/// test bundle compile it.
///
/// Two jobs, kept apart on purpose:
/// - `component` / `child` / `isContained` REFUSE. Used on names that must already be one plain
///   file name (a manifest entry, a synced `MemoAsset.filename`). A name real data already uses is
///   never refused: only what can leave the folder is (`/`, NUL, control characters, `.`, `..`).
///   A leading dot is allowed here, because it stays inside the folder and a real file may have one.
/// - `sanitisedFilename` REWRITES. Used when a new filename is derived from untrusted text.
enum PathSafety {

    /// True when `name` is exactly one plain file name that cannot step out of a folder.
    static func isSafeComponent(_ name: String) -> Bool {
        if name.isEmpty || name == "." || name == ".." { return false }
        return !name.unicodeScalars.contains { $0 == "/" || $0.value < 0x20 || $0.value == 0x7F }
    }

    /// `name` itself when it is a safe component, else nil.
    static func component(_ name: String) -> String? {
        isSafeComponent(name) ? name : nil
    }

    /// True when `url`, standardised and with symlinks resolved, is strictly inside `root`.
    /// A final component that does not exist yet is judged by its resolved parent, so a symlinked
    /// folder cannot carry a new file out, and an existing symlink at the target is followed.
    static func isContained(_ url: URL, in root: URL) -> Bool {
        let base = resolved(root)
        let target = resolved(url)
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        return target.path.hasPrefix(basePath) && target.path.count > basePath.count
    }

    /// `root/name` when `name` is a safe component and the resolved result stays inside `root`;
    /// nil otherwise. The one call a join site makes in place of `appendingPathComponent`.
    static func child(_ name: String, in root: URL) -> URL? {
        guard isSafeComponent(name) else { return nil }
        let url = root.appendingPathComponent(name)
        return isContained(url, in: root) ? url : nil
    }

    /// `child`, or — for a join site that must return a URL — a path inside `root` that never holds
    /// a file, so a refused name reads as "not there" and a write or delete through it hits nothing.
    static func childOrInert(_ name: String, in root: URL) -> URL {
        child(name, in: root) ?? root.appendingPathComponent(".refused-unsafe-name")
    }

    /// `root/relative` for a relative path of several components (a zip entry path such as
    /// `audio/part1.m4a`): every component must be safe, and the resolved result must stay in `root`.
    /// Absolute paths, `..` and empty components are refused.
    static func descendant(_ relative: String, in root: URL) -> URL? {
        guard !relative.hasPrefix("/") else { return nil }
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy(isSafeComponent) else { return nil }
        var url = root
        for p in parts { url.appendPathComponent(p) }
        return isContained(url, in: root) ? url : nil
    }

    /// A filename derived from untrusted text: separators and control characters become a space,
    /// every `..` run goes, leading dots go, and it is never empty. For NEW names only; callers
    /// whose names already exist on disk keep them (`component` refuses instead).
    static func sanitisedFilename(_ raw: String, fallback: String = "file") -> String {
        var scalars = String.UnicodeScalarView()
        for s in raw.unicodeScalars {
            if s == "/" || s == "\\" || s.value < 0x20 || s.value == 0x7F { scalars.append(" ") } else { scalars.append(s) }
        }
        var text = String(scalars)
        while text.contains("..") { text = text.replacingOccurrences(of: "..", with: ".") }
        text = text.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        text = String(text.drop(while: { $0 == "." || $0 == " " }))
        text = text.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? fallback : text
    }

    // MARK: Internals

    /// Standardised, symlinks resolved. A path that does not exist yet resolves its parent and
    /// re-attaches the last component (and follows the last component too if it does exist).
    private static func resolved(_ url: URL, depth: Int = 0) -> URL {
        guard depth < 40 else { return url.standardizedFileURL }   // a symlink loop
        let std = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: std.path) || (try? std.checkResourceIsReachable()) == true {
            return std.resolvingSymlinksInPath()
        }
        // A dangling symlink exists as a link even though its target does not: resolve it by hand.
        if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: std.path) {
            let target = dest.hasPrefix("/") ? URL(fileURLWithPath: dest)
                                             : std.deletingLastPathComponent().appendingPathComponent(dest)
            return resolved(target, depth: depth + 1)
        }
        let parent = std.deletingLastPathComponent()
        if parent.path == std.path || parent.path == "/" { return std }
        return resolved(parent, depth: depth + 1).appendingPathComponent(std.lastPathComponent)
    }
}
