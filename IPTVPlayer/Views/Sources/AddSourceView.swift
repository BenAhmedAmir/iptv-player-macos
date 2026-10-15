import SwiftUI
import UniformTypeIdentifiers

// MARK: - Add Source View

/// Adds an Xtream Codes or M3U source, with inline validation.
///
/// Errors are reported under the field that caused them rather than in a shared
/// banner, so a wrong password and an unreachable server do not look alike.
struct AddSourceView: View {
    @EnvironmentObject var sourcesVM: SourcesViewModel
    @EnvironmentObject var profileVM: ProfileViewModel
    @Environment(\.dismiss) private var dismiss

    /// Where an M3U playlist comes from.
    private enum PlaylistOrigin: String, CaseIterable, Identifiable {
        case url, file
        var id: String { rawValue }
        var label: String { self == .url ? "URL" : "Local File" }
    }

    /// Which field an error belongs under.
    private enum FieldError: Equatable {
        case server(String)
        case credentials(String)
        case playlist(String)
        case general(String)
    }

    @State private var selectedType: IPTVSourceType = .xtreamCodes
    @State private var origin: PlaylistOrigin = .url
    @State private var name = ""

    // Xtream
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""

    // M3U
    @State private var playlistURL = ""
    @State private var pickedFile: URL?
    @State private var epgURL = ""

    @State private var isConnecting = false
    @State private var fieldError: FieldError?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Source")
                .font(.system(size: 17, weight: .semibold))

            Picker("", selection: $selectedType) {
                Text("Xtream Codes").tag(IPTVSourceType.xtreamCodes)
                Text("M3U Playlist").tag(IPTVSourceType.m3uURL)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            field("Name") {
                TextField("e.g. Living room provider", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            if selectedType == .xtreamCodes {
                xtreamFields
            } else {
                m3uFields
            }

            if case .general(let message) = fieldError {
                InlineError(message: message)
            }

            Text("Credentials are stored in your Keychain.")
                .font(.system(size: 12))
                .foregroundColor(Theme.textTertiary)

            footer
        }
        .padding(22)
        .frame(width: 460)
        .disabled(isConnecting)
    }

    // MARK: - Fields

    private var xtreamFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Server URL", error: serverError) {
                TextField("http://provider.example:8080", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(alignment: .top, spacing: 10) {
                field("Username") {
                    TextField("", text: $username)
                        .textFieldStyle(.roundedBorder)
                }
                field("Password") {
                    SecureField("", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if case .credentials(let message) = fieldError {
                InlineError(message: message)
            }
        }
    }

    private var m3uFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $origin) {
                ForEach(PlaylistOrigin.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if origin == .url {
                field("Playlist URL", error: playlistError) {
                    TextField("https://provider.example/playlist.m3u", text: $playlistURL)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                field("Playlist file", error: playlistError) {
                    HStack(spacing: 10) {
                        // Shows the chosen filename rather than a full path,
                        // which would truncate to uselessness in this width.
                        Text(pickedFile?.lastPathComponent ?? "No file chosen")
                            .font(.system(size: 13))
                            .foregroundColor(pickedFile == nil ? Theme.textTertiary : Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button("Choose…", action: chooseFile)
                    }
                }
            }

            field("EPG URL (optional)") {
                TextField("https://provider.example/guide.xml", text: $epgURL)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ViewBuilder
    private func field<Content: View>(
        _ label: String,
        error: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
            content()
            if let error {
                InlineError(message: error)
            }
        }
    }

    private var serverError: String? {
        if case .server(let message) = fieldError { return message }
        return nil
    }

    private var credentialsError: String? {
        if case .credentials(let message) = fieldError { return message }
        return nil
    }

    private var playlistError: String? {
        if case .playlist(let message) = fieldError { return message }
        return nil
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if isConnecting {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting…")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button("Add") { submit() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit || isConnecting)
        }
    }

    private var canSubmit: Bool {
        switch selectedType {
        case .xtreamCodes:
            return !serverURL.trimmed.isEmpty && !username.trimmed.isEmpty && !password.trimmed.isEmpty
        default:
            return origin == .url ? !playlistURL.trimmed.isEmpty : pickedFile != nil
        }
    }

    // MARK: - Actions

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
        fieldError = nil
        if name.trimmed.isEmpty {
            name = url.deletingPathExtension().lastPathComponent
        }
    }

    private func submit() {
        fieldError = nil

        // Validate locally first so an obviously malformed URL is reported
        // against its own field instead of as a network failure.
        if selectedType == .xtreamCodes {
            guard isValidURL(serverURL) else {
                fieldError = .server("Enter a full address, including http:// or https://.")
                return
            }
        } else if origin == .url {
            guard isValidURL(playlistURL) else {
                fieldError = .playlist("Enter a full playlist address, including https://.")
                return
            }
        }

        isConnecting = true
        Task {
            await performAdd()
            isConnecting = false
        }
    }

    private func performAdd() async {
        let resolvedName = name.trimmed.isEmpty ? defaultName : name.trimmed

        switch selectedType {
        case .xtreamCodes:
            await sourcesVM.addXtreamSource(
                name: resolvedName,
                serverURL: serverURL.trimmed,
                username: username.trimmed,
                password: password
            )
        default:
            if origin == .url {
                await sourcesVM.addM3UURLSource(name: resolvedName, url: playlistURL.trimmed)
            } else if let pickedFile {
                await sourcesVM.addM3UFileSource(name: resolvedName, fileURL: pickedFile)
            }
        }

        if let error = sourcesVM.error {
            // Suppress the view model's own alert; this sheet shows the message
            // against the field that caused it.
            sourcesVM.showError = false
            sourcesVM.error = nil
            fieldError = mapped(error)
        } else {
            sourcesVM.persistEPGURL(epgURL.trimmed, forMostRecentSource: true)
            dismiss()
        }
    }

    private func mapped(_ error: IPTVError) -> FieldError {
        switch error {
        case .invalidCredentials, .expiredAccount:
            return .credentials(error.localizedDescription)
        case .serverUnavailable, .timeout, .networkUnavailable:
            return selectedType == .xtreamCodes
                ? .server(error.localizedDescription)
                : .playlist(error.localizedDescription)
        case .invalidM3U, .emptyM3U, .fileNotFound:
            return .playlist(error.localizedDescription)
        default:
            return .general(error.localizedDescription)
        }
    }

    private var defaultName: String {
        selectedType == .xtreamCodes ? "Xtream Source" : "M3U Playlist"
    }

    private func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string.trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            return false
        }
        return true
    }
}

// MARK: - Inline Error

/// Error text shown directly beneath the field that produced it.
struct InlineError: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
            Text(message)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundColor(Theme.destructive)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Previews

struct AddSourceView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AddSourceView()
                .previewDisplayName("Add Source — Dark")
                .preferredColorScheme(.dark)

            AddSourceView()
                .previewDisplayName("Add Source — Light")
                .preferredColorScheme(.light)
        }
        .environmentObject(SourcesViewModel())
        .environmentObject(ProfileViewModel())
    }
}

struct InlineError_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 12) {
            InlineError(message: "Invalid username or password. Please check your credentials.")
            InlineError(message: "The server is currently unavailable. Please try again later.")
        }
        .padding()
        .preferredColorScheme(.dark)
    }
}
