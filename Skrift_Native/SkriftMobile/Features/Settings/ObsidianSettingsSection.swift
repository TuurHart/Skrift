import SwiftUI
import UniformTypeIdentifiers

/// Settings → Obsidian.
///
/// **Two different jobs, split by what the device can actually do** (Tuur, 2026-08-11):
///
/// - **Picking the folder is for EVERY device, including the phone** — because the phone
///   wants to READ your vault ("we just want the phone to be able to read the vault, so
///   it's good to pick a folder, but that is about it"). The security-scoped bookmark is
///   the prerequisite for that, so the picker earns its place on iPhone even though
///   nothing there writes.
/// - **Exporting is only offered where the device can PROCESS a note** —
///   `PolishCenter.isAvailable`, the same gate the "Polish on this iPad" section uses.
///   Tuur: *"the phone can't even export anything to Obsidian, so it shouldn't even be
///   there. Only the iPad and the Mac can do that after they processed the note."* A
///   vault note is a POLISHED note; the phone captures, the Mac and iPad process, and
///   only what's been processed earns a place in the vault. Showing an Export button on
///   a device that can't produce one was a control that promised what it couldn't do.
///
/// (`ObsidianVault.setVault` had zero callers before 2026-07-26 — no picker meant no
/// vault could ever be configured, so none of the publish code had ever run on a device.)
struct ObsidianSettingsSection: View {
    /// The `author:` written into every note's frontmatter. Matching the Mac's
    /// Settings author matters: the SAME note exported by both devices must compile
    /// to the SAME bytes, or each device would see the other's file as "changed".
    @AppStorage("skrift.publish.author") private var author = ""

    @State private var pickingFolder = false
    @State private var folderName = ObsidianVault.displayName
    @State private var pickError: String?

    /// The four-destination feature. OFF by default and per-device — most people want one
    /// folder, and the whole thing is Tuur's own way of separating his thoughts from his
    /// work (2026-08-26: *"somebody might not care. This is very specific for me"*).
    @State private var destinationsOn = DestinationSettings.isEnabled
    @State private var pickingPortfolio = false
    @State private var portfolioName = PortfolioVault.displayName

    /// Can THIS device turn a memo into a polished note? If not, it has nothing to
    /// export, so the export controls don't appear at all.
    private var canProcess: Bool { PolishCenter.shared.isAvailable }

    var body: some View {
        Section {
            Button {
                pickingFolder = true
            } label: {
                HStack {
                    Label("Folder", systemImage: "folder")
                        .foregroundStyle(Color.skText)
                    Spacer()
                    Text(folderName ?? "Choose…")
                        .foregroundStyle(folderName == nil ? Color.skAccent : Color.skTextDim)
                }
            }
            .accessibilityIdentifier("obsidian-folder")

            // No toggle and no bulk button (Tuur, 2026-08-18: "iPad can export so
            // it should, Mac can export so it should, phone cannot so it should
            // not" / exporting "can be done in the app itself... not in settings").
            // Picking a folder on a device that can process IS the consent — every
            // export on iOS is a deliberate tap in the app (nothing auto-publishes),
            // so a switch here only made a third consent out of two. And no "which
            // notes" picker either: export is RATED-ONLY, on every device (Tuur,
            // 2026-07-26 — "cant export either"); one rule, no setting to get wrong.
            if folderName != nil, canProcess {
                LabeledContent("Author") {
                    TextField("optional", text: $author)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                }
            }
            if let pickError {
                Text(pickError)
                    .font(.footnote)
                    .foregroundStyle(Color.skTextDim)
            }
        } header: {
            Text("Obsidian")
        } footer: {
            Text(footerText)
        }
        .fileImporter(isPresented: $pickingFolder,
                      allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            do {
                try ObsidianVault.setVault(url)
                folderName = ObsidianVault.displayName
                pickError = nil
            } catch {
                pickError = "Couldn't save the folder — pick it again."
            }
        }

        destinationsSection
    }

    /// Settings → Destinations. One switch, then ONE portfolio-folder pick.
    ///
    /// Not three pickers: the three portfolio destinations are siblings inside the portfolio
    /// (`_projects` / `_ideas` / `_inspiration`), so three questions would be the same question
    /// three times with two chances to answer it wrong. The subfolders are shown read-only
    /// underneath, so what Skrift will do with the folder is visible before it does it.
    @ViewBuilder
    private var destinationsSection: some View {
        Section {
            Toggle(isOn: $destinationsOn) {
                Label("Separate destinations", systemImage: "arrow.triangle.branch")
                    .foregroundStyle(Color.skText)
            }
            .tint(.skAccent)
            .accessibilityIdentifier("destinations-toggle")
            .onChange(of: destinationsOn) { _, on in
                // Only a REAL flip here: adopting the synced value also moves `destinationsOn`,
                // and re-stamping that as a new edit would let it overwrite a later change.
                guard on != DestinationSettings.storedEnabled() else { return }
                DestinationSettings.set(on)
                VocabularyCloudSync.run(NotesRepository.shared)   // push to CloudKit now (Q98)
            }
            // A value synced in from another device lands in UserDefaults; follow it.
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                let stored = DestinationSettings.storedEnabled()
                if stored != destinationsOn { destinationsOn = stored }
            }

            if destinationsOn {
                Button {
                    pickingPortfolio = true
                } label: {
                    HStack {
                        Label("Portfolio folder", systemImage: "folder.badge.gearshape")
                            .foregroundStyle(Color.skText)
                        Spacer()
                        Text(portfolioName ?? "Choose…")
                            .foregroundStyle(portfolioName == nil ? Color.skAccent : Color.skTextDim)
                    }
                }
                .accessibilityIdentifier("portfolio-folder")

                if let portfolioName {
                    ForEach(NoteDestination.allCases.filter(\.isPortfolio), id: \.self) { d in
                        LabeledContent(d.label) {
                            Text("\(portfolioName)/\(d.portfolioFolder ?? "")")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color.skTextFaint)
                                // Identified explicitly: `LabeledContent` folds its label and
                                // value into ONE accessibility element, so the resolved path
                                // is not findable by its own text.
                                .accessibilityIdentifier("portfolio-path-\(d.rawValue)")
                        }
                    }
                }
            }
        } header: {
            Text("Destinations")
        } footer: {
            Text(destinationsFooter)
        }
        .fileImporter(isPresented: $pickingPortfolio,
                      allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            do {
                try PortfolioVault.setRoot(url)
                portfolioName = PortfolioVault.displayName
                pickError = nil
            } catch {
                pickError = "Couldn't save the portfolio folder — pick it again."
            }
        }
    }

    /// Says what the switch actually does — including the part that matters most, which is
    /// which side of the line a note ends up on.
    private var destinationsFooter: String {
        guard destinationsOn else {
            return "Off, every note goes to your Obsidian vault. On, each note carries one of "
                 + "four destinations you pick on the note itself."
        }
        guard portfolioName != nil else {
            return DestinationSettings.needsFolderNotice + ". This switch is on for all your "
                 + "devices; the folder is chosen per device. Skrift writes Project, Idea and "
                 + "Inspiration notes into folders inside it. Personal notes still go to your "
                 + "Obsidian vault and never here."
        }
        return "Personal notes go to your Obsidian vault. Project, Idea and Inspiration go to the "
             + "portfolio — a folder you have chosen to let an AI read, so nothing personal is "
             + "ever written there."
    }

    /// Says what THIS device will actually do with the folder — never more.
    private var footerText: String {
        guard let folderName else {
            return canProcess
                ? "Pick the folder inside your vault where Skrift should put its notes — audio and photos land in subfolders beside them. Skrift only ever touches its own files."
                : "Pick your Skrift folder so this iPhone can read your vault. Notes are written to it by your Mac (and iPad) once they've been processed."
        }
        return canProcess
            ? "Notes, audio and photos go into “\(folderName)”. A note you edit or move in Obsidian is left alone — Skrift never overwrites your version."
            : "This iPhone reads “\(folderName)”; it doesn't write to it. Your Mac and iPad put notes there once they've processed them."
    }

}
