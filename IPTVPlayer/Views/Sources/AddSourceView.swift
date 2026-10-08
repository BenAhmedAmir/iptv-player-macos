import SwiftUI
import UniformTypeIdentifiers

// MARK: - Add Source View

/// Sheet for adding a new IPTV source with live feedback and validation.
struct AddSourceView: View {
    @EnvironmentObject var sourcesVM: SourcesViewModel
    @EnvironmentObject var profileVM: ProfileViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedType: IPTVSourceType = .xtreamCodes
    @State private var name = ""

    // Xtream fields
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""

    // M3U fields
    @State private var localFilePath = ""
    @State private var selectedFileURL: URL?
    @State private var remoteURL = ""

    @State private var isValidating = false
    @State private var validationError: String?
    @State private var isShowingFileImporter = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Source")
                        .font(.title2.bold())
                    Text("Configure an Xtream Codes or M3U playlist")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Error message banner
                    if let err = validationError ?? sourcesVM.error?.localizedDescription {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(err)
                                .font(.subheadline)
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red.opacity(0.12))
                        )
                    }

                    // Source type picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Source Type")
                            .font(.headline)

                        Picker("Type", selection: $selectedType) {
                            ForEach(IPTVSourceType.allCases) { type in
                                Label(type.displayName, systemImage: type.iconName)
                                    .tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedType) { _ in
                            validationError = nil
                            sourcesVM.error = nil
                        }
                    }

                    // Name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Source Name (Optional)")
                            .font(.headline)
                        TextField("e.g. My TV Provider", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Type-specific fields
                    switch selectedType {
                    case .xtreamCodes:
                        xtreamFields
                    case .m3uFile:
                        m3uFileFields
                    case .m3uURL:
                        m3uURLFields
                    }
                }
                .padding(20)
            }

            Divider()

            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    validateAndSubmit()
                } label: {
                    HStack(spacing: 8) {
                        if isValidating {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Connecting...")
                        } else {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Source")
                        }
                    }
                    .frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isValidating)
            }
            .padding(20)
        }
        .frame(width: 520, height: 500)
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [
                UTType(filenameExtension: "m3u") ?? .plainText,
                UTType(filenameExtension: "m3u8") ?? .plainText,
                .plainText,
                .data
            ],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // Store the actual URL for security-scoped access
                    selectedFileURL = url
                    localFilePath = url.path
                    if name.isEmpty {
                        name = url.deletingPathExtension().lastPathComponent
                    }
                    validationError = nil
                }
            case .failure(let error):
                validationError = "Failed to select file: \(error.localizedDescription)"
            }
        }
        .onAppear {
            if sourcesVM.profileID == nil, let activeID = profileVM.activeProfile?.id {
                sourcesVM.loadSources(profileID: activeID)
            }
        }
    }

    // MARK: - Xtream Fields

    private var xtreamFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Server URL")
                        .font(.headline)
                    Text("*")
                        .foregroundColor(.red)
                }
                TextField("http://example.com:8080", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
                Text("Include the port if required (e.g., :8080 or :25461)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Username")
                        .font(.headline)
                    Text("*")
                        .foregroundColor(.red)
                }
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Password")
                        .font(.headline)
                    Text("*")
                        .foregroundColor(.red)
                }
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
            }
        }
    }

    // MARK: - M3U File Fields

    private var m3uFileFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Playlist File")
                    .font(.headline)
                Text("*")
                    .foregroundColor(.red)
            }

            HStack {
                TextField("/path/to/playlist.m3u or click Browse...", text: $localFilePath)
                    .textFieldStyle(.roundedBorder)

                Button("Browse...") {
                    isShowingFileImporter = true
                }
                .buttonStyle(.bordered)
            }

            Text("Select an .m3u or .m3u8 playlist file on your Mac.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - M3U URL Fields

    private var m3uURLFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Playlist URL")
                    .font(.headline)
                Text("*")
                    .foregroundColor(.red)
            }

            TextField("https://example.com/playlist.m3u8", text: $remoteURL)
                .textFieldStyle(.roundedBorder)

            Text("Enter the full HTTP or HTTPS URL to an M3U or M3U8 stream list.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Validation & Submission

    private func validateAndSubmit() {
        validationError = nil
        sourcesVM.error = nil

        // Ensure profile is connected
        if sourcesVM.profileID == nil {
            if let activeID = profileVM.activeProfile?.id {
                sourcesVM.loadSources(profileID: activeID)
            } else {
                validationError = "No active profile selected. Please select a profile first."
                return
            }
        }

        switch selectedType {
        case .xtreamCodes:
            let trimmedServer = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedPass = password.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedServer.isEmpty {
                validationError = "Please enter the server URL."
                return
            }
            if trimmedUser.isEmpty {
                validationError = "Please enter your username."
                return
            }
            if trimmedPass.isEmpty {
                validationError = "Please enter your password."
                return
            }

            var formattedServer = trimmedServer
            if !formattedServer.lowercased().hasPrefix("http://") && !formattedServer.lowercased().hasPrefix("https://") {
                formattedServer = "http://" + formattedServer
                serverURL = formattedServer
            }

            Task {
                await executeAdd {
                    await sourcesVM.addXtreamSource(
                        name: name,
                        serverURL: formattedServer,
                        username: trimmedUser,
                        password: trimmedPass
                    )
                }
            }

        case .m3uFile:
            let trimmedPath = localFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedPath.isEmpty {
                validationError = "Please browse or enter the path to an M3U/M3U8 file."
                return
            }

            Task {
                await executeAdd {
                    // Use the security-scoped URL if available, otherwise create from path
                    let fileURL = selectedFileURL ?? URL(fileURLWithPath: trimmedPath)
                    await sourcesVM.addM3UFileSource(name: name, fileURL: fileURL)
                }
            }

        case .m3uURL:
            let trimmedURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedURL.isEmpty {
                validationError = "Please enter a playlist URL."
                return
            }

            var formattedURL = trimmedURL
            if !formattedURL.lowercased().hasPrefix("http://") && !formattedURL.lowercased().hasPrefix("https://") {
                formattedURL = "http://" + formattedURL
                remoteURL = formattedURL
            }

            Task {
                await executeAdd {
                    await sourcesVM.addM3UURLSource(name: name, url: formattedURL)
                }
            }
        }
    }

    private func executeAdd(action: () async -> Void) async {
        isValidating = true
        defer { isValidating = false }

        await action()

        if sourcesVM.error == nil {
            dismiss()
        }
    }
}
