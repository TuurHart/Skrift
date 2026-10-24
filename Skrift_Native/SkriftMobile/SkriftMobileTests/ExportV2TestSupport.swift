import Foundation
@testable import SkriftMobile

/// Q437: the one-call form tests use to compile a memo through export v2 (v1's
/// `MemoExporter.markdown` was one call). It is the publisher's own v2 compile, nothing placed.
enum ExportV2Test {
    static func markdown(for memo: Memo, people: [Person], author: String = "",
                         enhancement: MemoEnhancement? = nil, linkStems: [UUID: String] = [:],
                         profile: ExportProfile = .obsidian) -> String {
        let title = MemoExporter.exportTitle(for: memo, people: people, enhancement: enhancement)
        let note = ObsidianPublisher.v2Note(memo, people: people, author: author, enhancement: enhancement,
                                            linkStems: linkStems, title: title)
        return ExportV2.compile(note, profile: profile,
                                stem: ExportNaming.stem(title: title, filename: memo.audioFilename)).markdown
    }

    /// A `CompilerInput` as export v2 compiles it (the title the input carries).
    static func markdown(_ input: CompilerInput, author: String = "", people: [Person] = [],
                         profile: ExportProfile = .obsidian) -> String {
        let stem = (input.filename as NSString).deletingPathExtension
        var note = ExportV2.Note(input: input, title: input.enhancedTitle ?? stem)
        note.people = people
        note.author = author
        return ExportV2.compile(note, profile: profile, stem: stem).markdown
    }

    /// `[[img_NNN]]` through export v2's converter (v1's `convertPhotoMarkers` shape): the
    /// markdown and (source filename, embed name) for each picture it placed.
    static func convertPictures(_ markdown: String, manifest: [ImageManifestEntry], stem: String,
                                profile: ExportProfile = .obsidian) -> (String, [(String, String)]) {
        var note = ExportV2.Note(input: CompilerInput(filename: "n.md", transcript: "", sourceType: .note), title: "N")
        note.pictureManifest = manifest.map(\.filename)
        let r = ExportV2.convertPictures(markdown, note: note, profile: profile, stem: stem, place: { _, name in name })
        return (r.markdown, r.placed.map { ($0.source, $0.embedName) })
    }
}
