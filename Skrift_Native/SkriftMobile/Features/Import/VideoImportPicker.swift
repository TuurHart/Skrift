import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A Photos picker filtered to VIDEOS, for importing a self-recorded clip (e.g. a
/// "life advice to myself" video) as a memo. The selected video's audio is stripped
/// to a `.m4a` + one frame becomes a `[[img_001]]` thumbnail, then it transcribes
/// on-device exactly like an audio import (`MemoSaver.importVideo`).
///
/// The memo's `recordedAt` comes from the video's recording date, NOT the import
/// time: the picker passes the library `PHAsset.creationDate` (when Photos access is
/// granted) as a fallback, and `MemoSaver.importVideo` additionally reads the date
/// embedded inside the file itself (which survives the copy out of the library).
///
/// Presented as a `.sheet`; `onImported(memoID)` fires once the memo has been
/// created so the caller can navigate to it. Self-contained — wired up by the
/// caller (the record/list lane owns the entry-point button).
struct VideoImportPicker: UIViewControllerRepresentable {
    /// Called on the main actor with the new memo id once import has kicked off, or
    /// nil if nothing was picked / the pick failed.
    var onImported: (UUID?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImported: onImported) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        // `.current` keeps the original encoding (so the embedded creation date +
        // audio track survive) rather than transcoding to a delivered format.
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onImported: (UUID?) -> Void
        init(onImported: @escaping (UUID?) -> Void) { self.onImported = onImported }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Dismiss right away on the main thread; the import then runs in the
            // background without holding a reference to the (non-Sendable) picker.
            picker.dismiss(animated: true)

            guard let result = results.first else { onImported(nil); return }

            // The library creation date, if Photos access is granted (best fallback
            // when the file's own embedded date is missing). The picker copy itself
            // usually preserves the embedded date, which `importVideo` reads directly.
            let libraryDate = Self.libraryCreationDate(for: result.assetIdentifier)

            Self.copyToTemp(result.itemProvider) { [onImported] tempURL in
                Task { @MainActor in
                    guard let tempURL else { onImported(nil); return }
                    let id = MemoSaver().importVideo(from: tempURL, creationDate: libraryDate)
                    onImported(id)
                }
            }
        }

        /// Copy the picked video out of the picker's transient storage into our temp
        /// dir (the provided URL is only valid inside the load closure). Completion is
        /// hopped to the main actor by the caller.
        private static func copyToTemp(_ provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
            let typeID = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .movie) == true }
                ?? UTType.movie.identifier
            provider.loadFileRepresentation(forTypeIdentifier: typeID) { url, _ in
                guard let url else { completion(nil); return }
                let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("import_\(UUID().uuidString).\(ext)")
                do {
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.copyItem(at: url, to: dest)
                    completion(dest)
                } catch {
                    completion(nil)
                }
            }
        }

        /// `PHAsset.creationDate` for a picked result, only if Photos access is already
        /// authorized (we never PROMPT — the picker works without library access; this
        /// is a best-effort date fallback). nil otherwise.
        private static func libraryCreationDate(for assetIdentifier: String?) -> Date? {
            guard let assetIdentifier else { return nil }
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard status == .authorized || status == .limited else { return nil }
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
            return assets.firstObject?.creationDate
        }
    }
}
