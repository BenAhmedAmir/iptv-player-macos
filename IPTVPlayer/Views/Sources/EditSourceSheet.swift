import SwiftUI
import UniformTypeIdentifiers

// MARK: - Edit Source Sheet

/// Edits an existing source in place.
///
/// Deliberately not "delete and re-add": favorites, watch history and playback
/// positions all key off the source id, so recreating it would orphan them.
struct EditSourceSheet: View {
    let source: IPTVSource
    @Binding var isPresented: Bool

    @EnvironmentObject var sourcesVM: SourcesViewModel

    @State private var name = ""
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var playlistURL = ""
    @State private var epgURL = ""
    @State private var pickedFile: URL?

    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            field("Name") {
                TextField("Source name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            switch source.type {
            case .xtreamCodes: xtreamFields
            case .m3uURL: playlistURLField
            case .m3uFile: playlistFileField
            }

            field("EPG URL (optional)") {
                TextField("https://provider.example/guide.xml", text: $epgURL)
                    .textFieldStyle(.roundedBorder)
            }

            if let errorMessage {
                InlineError(message: errorMessage)
            }

            footer
        }
        .padding(22)
        .frame(width: 470)
        .disabled(isSaving)
        .onAppear(perform: populate)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Edit Source")
                .font(.system(size: 17, weight: .semibold))
            Text("Favorites and watch history for this source are kept.")
                .font(.system(size: 12))
                .foregroundColor(Theme.textTertiary)
        }
    }

    private var xtreamFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Server URL") {
                TextField("http://provider.example:8080", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(alignment: .top, spacing: 10) {
                field("Username") {
                    TextField("", text: $username)
                        .textFieldStyle(.roundedBorder)
                }
                field("Password") {
                    // Never pre-filled from the Keychain; blank means "keep".
                    SecureField("Unchanged", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text("Leave the password blank to keep the one already saved.")
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
        }
    }

    private var playlistURLField: some View {
        field("Playlist URL") {
            TextField("https://provider.example/playlist.m3u", text: $playlistURL)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var playlistFileField: some View {
        field("Playlist file") {
            HStack(spacing: 10) {
                Text(pickedFile?.lastPathComponent
                     ?? (source.localFilePath as NSString?)?.lastPathComponent
                     ?? "No file chosen")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button("Choose…", action: chooseFile)
            }
        }
    }

    @ViewBuilder
    private func field<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
            content()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if isSaving {
                ProgressView().controlSize(.small)
                Text("Checking…")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            Button("Cancel") { isPresented = false }
                .keyboardShortcut(.cancelAction)

            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
        }
    }

    // MARK: - Actions

    private func populate() {
        name = source.name
        serverURL = source.serverURL ?? ""
        playlistURL = source.remoteURL ?? ""
        epgURL = source.epgURL ?? ""
        // Username is shown so it can be corrected; the password never is.
        username = KeychainService.shared.getCredentials(sourceID: source.id)?.username ?? ""
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Playlist"
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        let types = ["m3u", "m3u8"].compactMap { UTType(filenameExtension: $0) }
        if !types.isEmpty { panel.allowedContentTypes = types }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        pickedFile = url
    }

    private func save() {
        errorMessage = nil
        isSaving = true

        Task {
            var succeeded = true

            // A newly picked playlist file is applied first; the shared edit
            // path only covers the fields every source type has.
            if let pickedFile {
                succeeded = await sourcesVM.replacePlaylistFile(for: source, fileURL: pickedFile)
            }

            if succeeded {
                succeeded = await sourcesVM.updateSource(
                    source,
                    edits: .init(
                        name: name,
                        serverURL: serverURL,
                        username: username,
                        password: password,
                        playlistURL: playlistURL,
                        epgURL: epgURL
                    )
                )
            }

            isSaving = false

            if succeeded {
                isPresented = false
            } else {
                // Shown inline here rather than through the Sources alert, which
                // would appear behind this sheet.
                errorMessage = sourcesVM.error?.localizedDescription
                    ?? "Could not save those changes."
                sourcesVM.error = nil
                sourcesVM.showError = false
            }
        }
    }
}

// MARK: - Previews

struct EditSourceSheet_Previews: PreviewProvider {
    private static func sample(_ type: IPTVSourceType) -> IPTVSource {
        var source = IPTVSource(
            profileID: UUID(),
            name: type == .xtreamCodes ? "Home IPTV" : "Free-to-air",
            type: type,
            serverURL: type == .xtreamCodes ? "http://provider.example:8080" : nil,
            remoteURL: type == .m3uURL ? "https://provider.example/playlist.m3u" : nil
        )
        source.channelCount = 1284
        return source
    }

    static var previews: some View {
        Group {
            EditSourceSheet(source: sample(.xtreamCodes), isPresented: .constant(true))
                .previewDisplayName("Edit Xtream — Dark")
                .preferredColorScheme(.dark)

            EditSourceSheet(source: sample(.xtreamCodes), isPresented: .constant(true))
                .previewDisplayName("Edit Xtream — Light")
                .preferredColorScheme(.light)

            EditSourceSheet(source: sample(.m3uURL), isPresented: .constant(true))
                .previewDisplayName("Edit M3U URL — Dark")
                .preferredColorScheme(.dark)
        }
        .environmentObject(SourcesViewModel())
    }
}
