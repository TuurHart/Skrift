import Foundation

/// Q437: the one-call forms tests use to compile a note through export v2 (v1's
/// `Compiler.compile` was one call). Each is the app's own v2 compile, nothing re-implemented.
enum ExportV2Test {
    /// A `CompilerInput` as export v2 compiles it. The title is the input's (else its file stem,
    /// v1's fallback); `people` is the live roster (`people:` and the portfolio's kept links);
    /// `date` pins `date:` the way v1's override did, by making it the recording's day.
    static func markdown(_ input: CompilerInput, author: String = "", date: String? = nil,
                         people: [Person] = [], profile: ExportProfile = .obsidian) -> String {
        var input = input
        if let date { pin(&input, date: date) }
        let stem = (input.filename as NSString).deletingPathExtension
        var note = ExportV2.Note(input: input, title: input.enhancedTitle ?? stem)
        note.people = people
        note.author = author
        return ExportV2.compile(note, profile: profile, stem: stem).markdown
    }

    /// A Mac row as `VaultExporter.export` compiles it, nothing placed (`date` as above).
    static func markdown(_ pf: PipelineFile, author: String = "", date: String? = nil, people: [Person] = [],
                         profile: ExportProfile = .obsidian) -> String {
        var note = VaultExporter.v2Note(pf, people: people, author: author)
        if let date { pin(&note.input, date: date) }
        return ExportV2.compile(note, profile: profile, stem: VaultExporter.noteStem(pf)).markdown
    }

    private static func pin(_ input: inout CompilerInput, date: String) {
        input.metadata?.recordedAt = nil
        input.rawRecordedAt = date
    }

    /// One real `VaultExporter.export` of an audio note whose working folder is `working` (its
    /// manifests and files as an ingest leaves them), into a fresh vault and portfolio beside it.
    /// Returns the body below the frontmatter, the name of every other file the export wrote
    /// (`file(_:)` finds one) and the result.
    static func export(body: String, working: URL, title: String, profile: ExportProfile = .obsidian) throws
        -> (body: String, files: [String], result: VaultExporter.Result, file: (String) -> URL?) {
        let audio = working.appendingPathComponent("original.m4a")
        if !FileManager.default.fileExists(atPath: audio.path) { try Data([1, 2, 3]).write(to: audio) }
        let pf = PipelineFile(id: UUID().uuidString, filename: "memo.m4a", path: audio.path, size: 3, sourceType: .audio)
        pf.enhancedTitle = title
        pf.sanitised = body
        pf.includeAudioInExport = false
        if profile == .portfolio { pf.destination = .portfolio }
        let out = working.appendingPathComponent("export-out")
        var settings = AppSettings.default
        settings.noteFolder = out.appendingPathComponent("vault").path
        settings.portfolioRoot = out.appendingPathComponent("portfolio").path
        let r = try VaultExporter.export(pf, settings: settings)
        let md = try String(contentsOf: r.markdownURL, encoding: .utf8)
        let fence = md.range(of: "\n---\n", range: md.index(md.startIndex, offsetBy: 3)..<md.endIndex)!
        let written = (FileManager.default.enumerator(atPath: out.path)?.allObjects as? [String] ?? [])
            .filter { !$0.hasSuffix(".md") && !$0.hasPrefix(".") && !$0.contains("/.") }
            .filter { var d: ObjCBool = false
                      return FileManager.default.fileExists(atPath: out.appendingPathComponent($0).path, isDirectory: &d) && !d.boolValue }
        let file = { (name: String) in written.first { ($0 as NSString).lastPathComponent == name }.map(out.appendingPathComponent) }
        return (String(md[fence.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "\n")),
                written.map { ($0 as NSString).lastPathComponent }.sorted(), r, file)
    }
}
