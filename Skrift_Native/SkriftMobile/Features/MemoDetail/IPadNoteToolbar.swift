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
                IPadFormatPopover(state: editor?.formatState ?? EditorFormatState())
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

/// The iPad Aa popover: the Mac's full list (D197), dropped from the Aa button. Acts on the
/// caret's line (styles, lists, quote) or the selected words (B I U S, highlight, Monostyled on
/// a one-line selection). Written as Markdown; no colour.
struct IPadFormatPopover: View {
    @ObservedObject var state: EditorFormatState
    private var editor: NoteBodyView.Coordinator? { NoteEditorChrome.shared.current }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(IPadFormatMenu.marks, id: \.self) { mark in
                    markButton(mark)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(IPadFormatMenu.styles.enumerated()), id: \.offset) { i, row in
                    if i > 0 { Rectangle().fill(Color.skBorder).frame(height: 0.5) }
                    styleRow(row)
                }
            }
            .background(Color.skElev, in: .rect(cornerRadius: 12, style: .continuous))
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            HStack(spacing: 6) {
                ForEach(IPadFormatMenu.lists, id: \.label) { row in listButton(row) }
            }
            listButton(IPadFormatMenu.quote)
            Text("Written as Markdown in the note. No colour.")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.skTextFaint)
        }
        .padding(12)
        .frame(width: 356)
        .background(Color.skSurface)
        // .contain keeps the container's id off its buttons (Q359 finding).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ipad-format-popover")
    }

    private func isOn(_ row: IPadFormatMenu.Row) -> Bool {
        if case .line(let style) = row.action { return state.lineStyle == style }
        return false
    }

    private func run(_ row: IPadFormatMenu.Row) {
        switch row.action {
        case .line(let style): editor?.applyLineStyle(style)
        case .monostyled: editor?.applyMonostyled()
        }
    }

    private func markButton(_ mark: BodyFormat.InlineMark) -> some View {
        let on = state.marks.contains(mark)
        return Button { editor?.applyInline(mark) } label: {
            VStack(spacing: 1) {
                switch mark {
                case .bold: Text("B").font(.system(size: 17, weight: .heavy))
                case .italic: Text("I").font(.custom("Georgia-Italic", size: 17))
                case .underline: Text("U").font(.system(size: 17)).underline()
                case .strike: Text("S").font(.system(size: 17)).strikethrough()
                default: Image(systemName: "highlighter").font(.system(size: 16))
                }
                Text(IPadFormatMenu.markHint(mark))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(on ? Color.skAccentText : Color.skTextFaint)
            }
            .foregroundStyle(on ? Color.skAccent : Color.skText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(on ? Color.skAccentSoft : Color.skElev, in: .rect(cornerRadius: 10, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ipad-format-\(IPadFormatMenu.markLabel(mark))")
        .accessibilityLabel(IPadFormatMenu.markLabel(mark))
    }

    private func styleRow(_ row: IPadFormatMenu.Row) -> some View {
        let on = isOn(row)
        return Button { run(row) } label: {
            HStack(spacing: 10) {
                Text(row.label)
                    .font(row.action == .monostyled
                          ? .system(size: row.size, design: .monospaced)
                          : .system(size: row.size, weight: row.weight))
                Spacer(minLength: 0)
                Text(row.hint)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.skTextFaint)
            }
            .foregroundStyle(on ? Color.skAccent : Color.skText)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(on ? Color.skAccentSoft : Color.clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(row.id)
    }

    private func listButton(_ row: IPadFormatMenu.Row) -> some View {
        let on = isOn(row)
        let glyph: String = {
            switch row.action {
            case .line(.bullet): return "• "
            case .line(.dashed): return "– "
            case .line(.numbered): return "1. "
            case .line(.quote): return "❝ "
            default: return ""
            }
        }()
        return Button { run(row) } label: {
            VStack(spacing: 1) {
                Text(glyph + row.label).font(.system(size: 14))
                Text(row.hint)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(on ? Color.skAccentText : Color.skTextFaint)
            }
            .foregroundStyle(on ? Color.skAccent : Color.skText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(on ? Color.skAccentSoft : Color.skElev, in: .rect(cornerRadius: 10, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(row.id)
    }
}
