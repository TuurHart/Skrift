import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Q379 (signed mock Q378-ipad-apple, D198): the note's editing tools at regular width, one
/// glass group in the top bar — Aa · checklist · attach · note link. The keyboard bar stays
/// away on iPad (`NoteBodyView.Coordinator.setKeyboardBarHidden`). Every verb runs on the editor
/// of the note on screen (`NoteEditorChrome.current`), at its caret.
struct IPadNoteToolbar: View {
    let memo: Memo

    @State private var showFormat = false
    @State private var showScanner = false
    @State private var showCamera = false
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var pickedPhoto: PhotosPickerItem?

    private var editor: NoteBodyView.Coordinator? { NoteEditorChrome.shared.current }

    var body: some View {
        HStack(spacing: 0) {
            Button { showFormat.toggle() } label: {
                Text("Aa")
                    .font(.system(size: 20, weight: .medium))
                    .kerning(-0.4)
                    .foregroundStyle(showFormat ? Color.skAccent : Color.skText)
                    .frame(width: 52, height: IPadLayout.glassHeight)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ipad-tool-format")
            .accessibilityLabel("Format")
            .popover(isPresented: $showFormat, arrowEdge: .top) {
                // The phone's own Aa panel with the full set (D197, `FormatCommand`), dropped
                // from the button the way the Mac's is.
                NoteFormatPanel(state: editor?.formatState ?? EditorFormatState(), items: .full,
                                onStyle: { editor?.applyLineStyle($0) },
                                onMark: { editor?.applyInline($0) },
                                onMonostyled: { editor?.applyMonostyled() },
                                onClose: { showFormat = false })
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 380)
                    .presentationCompactAdaptation(.popover)
            }

            tool("checklist", id: "ipad-tool-checklist", label: "Checklist") {
                editor?.toggleChecklistAtCaret()
            }

            // Apple's in-note attach menu minus Record Audio (D198): everything lands in THIS note.
            Menu {
                Section(IPadLayout.attachHeader) {
                    ForEach(IPadLayout.AttachItem.allCases, id: \.self) { item in
                        if item != .scanDocument || DocScanView.isSupported {
                            Button { attach(item) } label: { Label(item.title, systemImage: item.symbol) }
                                .accessibilityIdentifier(item.id)
                        }
                    }
                }
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.skText)
                    .frame(width: 52, height: IPadLayout.glassHeight)
                    .contentShape(.rect)
            }
            .accessibilityIdentifier("ipad-tool-attach")
            .accessibilityLabel("Attach")

            tool("link", id: "ipad-tool-link", label: "Link to a note") {
                editor?.requestMemoLinkAtCaret()
            }
        }
        .padding(.horizontal, 6)
        .frame(height: IPadLayout.glassHeight)
        .ipadGlass(in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ipad-note-tools")
        .fullScreenCover(isPresented: $showScanner) {
            DocScanView(onScan: { pages in
                showScanner = false
                pages.forEach(insert)
            }, onCancel: { showScanner = false })
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker { insert($0) }.ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotos, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    insert(image)
                }
                pickedPhoto = nil
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) { insert(image) }
        }
    }

    private func tool(_ symbol: String, id: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.skText)
                .frame(width: 52, height: IPadLayout.glassHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
    }

    private func attach(_ item: IPadLayout.AttachItem) {
        switch item {
        case .scanDocument: showScanner = true
        case .takePhoto: if CameraImagePicker.isAvailable { showCamera = true } else { showPhotos = true }
        case .choosePhoto: showPhotos = true
        case .attachFile: showFiles = true
        }
    }

    /// Same path as the keyboard bar's photo: into the text at the caret, then mirrored to
    /// CloudKit and queued for photo-text indexing.
    private func insert(_ image: UIImage) {
        editor?.insertPhoto(image)
        AssetMaterializer.capture(memoID: memo.id, repository: NotesRepository.shared)
        PhotoTextIndexer.run(NotesRepository.shared)
    }
}
