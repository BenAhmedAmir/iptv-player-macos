import SwiftUI

// MARK: - Sources View

/// Manages IPTV sources for the active profile.
struct SourcesView: View {
    @Binding var selectedNav: NavigationItem?
    @EnvironmentObject var sourcesVM: SourcesViewModel
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var channelVM: ChannelViewModel
    @State private var sourceToRename: IPTVSource?
    @State private var showRename = false
    @State private var sourceToReauth: IPTVSource?
    @State private var showReauth = false
    @State private var showDeleteConfirm = false
    @State private var sourceToDelete: IPTVSource?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sources")
                        .font(.title2.bold())
                    Text("\(sourcesVM.sources.count) source\(sourcesVM.sources.count == 1 ? "" : "s") configured")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }

                Spacer()

                Button {
                    sourcesVM.isShowingAddSource = true
                } label: {
                    Label("Add Source", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)

            Divider()

            // Sources list
            if sourcesVM.sources.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(sourcesVM.sources) { source in
                        SourceRow(
                            source: source,
                            isLoading: sourcesVM.loadingSourceID == source.id,
                            needsCredentials: sourcesVM.needsCredentials(source),
                            onViewChannels: {
                                channelVM.selectedSourceFilter = source.id
                                selectedNav = .liveTV
                            },
                            onToggle: { sourcesVM.toggleSource(source) },
                            onRefresh: { Task { await sourcesVM.refreshSource(source) } },
                            onSignIn: {
                                sourceToReauth = source
                                showReauth = true
                            },
                            onRename: {
                                sourceToRename = source
                                showRename = true
                            },
                            onDelete: {
                                sourceToDelete = source
                                showDeleteConfirm = true
                            }
                        )
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showRename) {
            if let source = sourceToRename {
                RenameSheet(
                    title: "Rename Source",
                    currentName: source.name,
                    isPresented: $showRename
                ) { newName in
                    sourcesVM.renameSource(source, to: newName)
                }
            }
        }
        .sheet(isPresented: $showReauth) {
            if let source = sourceToReauth {
                XtreamSignInSheet(
                    source: source,
                    isPresented: $showReauth
                ) { username, password in
                    await sourcesVM.updateXtreamCredentials(
                        source,
                        username: username,
                        password: password
                    )
                }
            }
        }
        .alert("Delete Source", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let source = sourceToDelete {
                    sourcesVM.deleteSource(source)
                }
            }
        } message: {
            Text("Are you sure you want to delete this source? All associated channels will be removed.")
        }
        .alert("Error", isPresented: $sourcesVM.showError) {
            Button("OK") { sourcesVM.showError = false }
        } message: {
            Text(sourcesVM.error?.localizedDescription ?? "An error occurred.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Text("No sources yet")
                .font(.title2.bold())

            Text("Add an Xtream Codes or M3U source to get started.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                sourcesVM.isShowingAddSource = true
            } label: {
                Label("Add Source", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Xtream Sign In Sheet

/// Re-enters Xtream credentials for an existing source, keeping its `sourceID`
/// so favorites and watch history survive. Credentials are verified against the
/// server before being written to the Keychain.
struct XtreamSignInSheet: View {
    let source: IPTVSource
    @Binding var isPresented: Bool
    let onSubmit: (String, String) async -> Bool

    @State private var username = ""
    @State private var password = ""
    @State private var isSubmitting = false

    private var canSubmit: Bool {
        !username.isEmpty && !password.isEmpty && !isSubmitting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sign In to \(source.name)")
                .font(.title2.bold())

            Text("Enter the username and password for this Xtream provider. Your favorites and watch history are kept.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let serverURL = source.serverURL {
                LabeledContent("Server") {
                    Text(serverURL)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }

            Form {
                TextField("Username", text: $username)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
            .formStyle(.grouped)
            .frame(height: 90)

            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    isSubmitting = true
                    Task {
                        let success = await onSubmit(username, password)
                        isSubmitting = false
                        if success {
                            // Leave the sheet open on failure so the error alert has
                            // context and the user can correct a typo in place.
                            isPresented = false
                        }
                    }
                } label: {
                    if isSubmitting {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Text("Sign In")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

// MARK: - Source Row

struct SourceRow: View {
    let source: IPTVSource
    let isLoading: Bool
    let needsCredentials: Bool
    let onViewChannels: () -> Void
    let onToggle: () -> Void
    let onRefresh: () -> Void
    let onSignIn: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: source.type.iconName)
                .font(.title2)
                .foregroundColor(source.isEnabled ? .blue : .secondary)
                .frame(width: 36)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(source.name)
                        .font(.headline)

                    Text(source.type.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.15))
                        )
                }

                HStack(spacing: 12) {
                    Text("\(source.channelCount) channels")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let lastRefresh = source.lastRefreshedAt {
                        Text("Updated \(lastRefresh, style: .relative) ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !source.isEnabled {
                        Text("Disabled")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    if needsCredentials {
                        Label("Sign-in required", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }

            // Without credentials every refresh and VOD request fails, so surface
            // the fix directly rather than leaving the source silently broken.
            if needsCredentials {
                Button(action: onSignIn) {
                    Label("Sign In", systemImage: "key.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
            }

            // View Channels Button
            if source.channelCount > 0 {
                Button(action: onViewChannels) {
                    Label("View Channels", systemImage: "tv")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }

            // Toggle
            Toggle("", isOn: Binding(
                get: { source.isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
        .opacity(source.isEnabled ? 1.0 : 0.6)
        .contextMenu {
            Button { onRefresh() } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Button { onRename() } label: {
                Label("Rename", systemImage: "pencil")
            }
            if source.type == .xtreamCodes {
                Button { onSignIn() } label: {
                    Label("Update Credentials…", systemImage: "key")
                }
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
