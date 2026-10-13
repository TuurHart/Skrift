import Foundation
import Photos
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The hold / right-click menu's file verbs for a block (D202, mock Q384 pick 6), one copy for
/// the phone, iPad and Mac. Which verbs a block gets is `NoteAttachment.holdMenu`; this only
/// moves bytes. Share stays with each app (it needs the app's own presenter).
enum NoteBlockFileActions {

    /// Copy: a picture goes on the pasteboard as its image, anything else as the file itself.
    static func copy(_ url: URL, isPicture: Bool) {
        #if canImport(UIKit)
        if isPicture, let image = UIImage(contentsOfFile: url.path) {
            UIPasteboard.general.image = image
        } else if let provider = NSItemProvider(contentsOf: url) {
            UIPasteboard.general.setItemProviders([provider], localOnly: false, expirationDate: nil)
        }
        #else
        let pb = NSPasteboard.general
        pb.clearContents()
        if isPicture, let image = NSImage(contentsOf: url) {
            pb.writeObjects([image])
        } else {
            pb.writeObjects([url as NSURL])
        }
        #endif
    }

    /// Save to Photos: a photo or video added to the library (add-only permission). `done` runs
    /// on the main thread with whether it was saved.
    static func saveToPhotos(_ url: URL, isVideo: Bool, done: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { done(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                if isVideo {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } else {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            }) { ok, _ in DispatchQueue.main.async { done(ok) } }
        }
    }

    #if canImport(UIKit)
    /// Save to Files: the system exporter saving a copy under `name`. `host` is the controller
    /// to present from; nil = the topmost one of the key window.
    @MainActor
    static func saveToFiles(_ url: URL, name: String, from host: UIViewController? = nil) {
        let named = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: named)
        let source = (try? FileManager.default.copyItem(at: url, to: named)) != nil ? named : url
        var top = host ?? UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
        if host == nil { while let presented = top?.presentedViewController { top = presented } }
        top?.present(UIDocumentPickerViewController(forExporting: [source], asCopy: true), animated: true)
    }
    #endif

    #if os(macOS)
    /// Save to Downloads: a copy under its own name in ~/Downloads ("name 2.ext" when taken),
    /// selected in Finder. Returns where it went.
    @discardableResult
    static func saveToDownloads(_ url: URL, name: String) -> URL? {
        let fm = FileManager.default
        guard let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return nil }
        let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var target = downloads.appendingPathComponent(name)
        var n = 2
        while fm.fileExists(atPath: target.path) {
            target = downloads.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            n += 1
        }
        guard (try? fm.copyItem(at: url, to: target)) != nil else { return nil }
        NSWorkspace.shared.activateFileViewerSelecting([target])
        return target
    }
    #endif
}
