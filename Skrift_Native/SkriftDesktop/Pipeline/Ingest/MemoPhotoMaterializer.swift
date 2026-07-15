import Foundation

/// Heals a Mac note whose photos arrived AFTER its first ingest. `MemoCloudIngest`
/// writes a memo's photo files (+ `image_manifest.json`) only on the FIRST sync;
/// `MemoCloudUpdate` reflects later text/metadata edits but never wrote the image
/// files — so a photo inserted while EDITING an already-synced note left its
/// `[[img_NNN]]` marker unresolved on the Mac (rendered as literal text, and its
/// image never reached the vault on export). This writes any missing photo blobs
/// and refreshes `image_manifest.json` so the marker resolves (`NoteBody.imageURL`:
/// the Nth manifest entry's file under `images/`). Idempotent — it skips files
/// already on disk, so running it every sweep costs nothing once healed.
enum MemoPhotoMaterializer {

    /// Write any of `memo`'s photo assets that are missing from `pf`'s working
    /// `images/` folder, and bring `image_manifest.json` in line with the memo's
    /// manifest. Returns true only when it actually wrote something (so the caller
    /// can re-export + nudge the UI). No-op without photos/manifest or an on-disk path.
    @discardableResult
    static func materializeMissing(memo: Memo, assets: [MemoAsset], pf: PipelineFile) -> Bool {
        let manifest = memo.metadata?.imageManifest ?? []
        let photos = assets.filter { $0.kind == MemoAsset.Kind.photo && !$0.filename.isEmpty }
        guard !manifest.isEmpty || !photos.isEmpty, let folder = pf.workingFolder else { return false }

        let fm = FileManager.default
        let imagesDir = folder.appendingPathComponent("images", isDirectory: true)
        var wrote = false

        // 1. Write any photo blob whose file isn't on disk yet.
        for photo in photos {
            let dest = imagesDir.appendingPathComponent(photo.filename)
            guard !fm.fileExists(atPath: dest.path) else { continue }
            try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            if (try? photo.blob.write(to: dest)) != nil { wrote = true }
        }

        // 2. Bring image_manifest.json in line with the memo's manifest — but only when
        //    the ordered filenames actually differ (a semantic compare, so formatting/key
        //    order never causes a rewrite). This is what makes a NEW marker (img_002/003)
        //    resolvable after the first ingest wrote only img_001.
        let manifestURL = folder.appendingPathComponent("image_manifest.json")
        let want = manifest.map(\.filename)
        let have: [String] = {
            guard let data = try? Data(contentsOf: manifestURL),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            return arr.compactMap { $0["filename"] as? String }
        }()
        if !manifest.isEmpty, want != have {
            let entries: [[String: Any]] = manifest.map {
                ["filename": $0.filename, "offsetSeconds": $0.offsetSeconds]
            }
            if let data = try? JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted]) {
                try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
                if (try? data.write(to: manifestURL)) != nil { wrote = true }
            }
        }
        return wrote
    }
}
