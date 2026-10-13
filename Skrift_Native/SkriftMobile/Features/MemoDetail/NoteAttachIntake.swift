import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The attach menu's three pickers, one route on phone and iPad (D198, D199): a picked PICTURE goes
/// in as a photo (`insertPhoto`), a picked MOVIE or any other FILE as an attachment block
/// (`insertAttachment`). Which is which is `NoteAttachment.kind` / `NotePhoto.acceptedExtensions`.
enum NoteAttachIntake {

    /// The library picker's filter: Apple's "Choose Photo or Video".
    static let libraryFilter: PHPickerFilter = .any(of: [.images, .videos])

    /// A movie handed over by the photo library, copied out of the picker's sandbox.
    struct PickedMovie: Transferable {
        let url: URL
        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(contentType: .movie) { movie in SentTransferredFile(movie.url) } importing: { received in
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("attach-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let dest = dir.appendingPathComponent(received.file.lastPathComponent)
                try FileManager.default.copyItem(at: received.file, to: dest)
                return PickedMovie(url: dest)
            }
        }
    }

    /// A library pick → photo or video.
    @MainActor
    static func load(_ item: PhotosPickerItem, image: @escaping (UIImage) -> Void,
                     file: @escaping (URL, String?, String?) -> Void) async {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }),
           let movie = try? await item.loadTransferable(type: PickedMovie.self) {
            let uti = item.supportedContentTypes.first(where: { $0.conforms(to: .movie) })?.identifier
            file(movie.url, movie.url.lastPathComponent, uti)
            return
        }
        if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { image(img) }
    }

    /// A Files pick → a picture goes in as a photo, anything else as a file block.
    @MainActor
    static func importFile(_ url: URL, image: (UIImage) -> Void, file: (URL, String?, String?) -> Void) {
        if NotePhoto.acceptedExtensions.contains(url.pathExtension.lowercased()) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) { image(img); return }
        }
        let uti = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.identifier
        file(url, url.lastPathComponent, uti)
    }
}
