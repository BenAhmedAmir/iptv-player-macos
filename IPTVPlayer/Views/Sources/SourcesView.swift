import SwiftUI

// MARK: - Sources View

/// Manages IPTV sources for the active profile.
struct SourcesView: View {
    @Binding var selectedNav: NavigationItem?
    @EnvironmentObject var sourcesVM: SourcesViewModel
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var channelVM: ChannelViewModel
    @EnvironmentObject var vodVM: VODViewModel
    @State private var sourceToRename: IPTVSource?
    @State private var showRename = false
    @State private var sourceToEdit: IPTVSource?
    @State private var showEdit = false
    @State private var sourceToReauth: IPTVSource?
    @State private var showReauth = false
    @State private var showDeleteConfirm = false
    @State private var sourceToDelete: IPTVSource?

    var body: some View {
        Group {
            if sourcesVM.sources.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(sourcesVM.sources) { source in
                            SourceCard(
                                source: source,
                                needsCredentials: sourcesVM.needsCredentials(source),
                                isLoading: sourcesVM.loadingSourceID == source.id,
                                onViewChannels: {
                                    channelVM.selectedSourceFilter = source.id
                                    selectedNav = .liveTV
                                },
                                onRefresh: { Task { await sourcesVM.refreshSource(source) } },
                                onToggle: { sourcesVM.toggleSource(source) },
                                onSignIn: {
                                    sourceToReauth = source
                                    showReauth = true
                                },
                                onEdit: {
                                    sourceToEdit = source
                                    showEdit = true
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

                        Text("Credentials are stored in your Keychain. Refresh a source to pull its latest channels.")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .sheet(isPresented: $showEdit) {
            if let source = sourceToEdit {
                EditSourceSheet(source: source, isPresented: $showEdit)
                    .environmentObject(sourcesVM)
            }
        }
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
                XtreamSignInSheet(source: source, isPresented: $showReauth) { username, password in
                    await sourcesVM.updateXtreamCredentials(source, username: username, password: password)
                }
            }
        }
        .alert("Delete Source", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let source = sourceToDelete {
                    sourcesVM.deleteSource(source)
                    // Caches are gone from disk; drop what is still loaded so
                    // the library does not keep showing removed content.
                    reloadLibrary()
                }
            }
        } message: {
            Text("This removes the source along with its channels, movies, TV shows, favorites and watch history. This cannot be undone.")
        }
        .alert("Error", isPresented: $sourcesVM.showError) {
            Button("OK") { sourcesVM.showError = false }
        } message: {
            Text(sourcesVM.error?.localizedDescription ?? "An error occurred.")
        }
    }

    /// Reloads channels and VOD after the source list changes.
    private func reloadLibrary() {
        guard let profileID = sourcesVM.profileID else { return }
        Task {
            await channelVM.loadChannels(profileID: profileID, sources: sourcesVM.sources)
            vodVM.loadData(sources: sourcesVM.sources)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("No sources yet")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Text("Add an M3U playlist or Xtream Codes login to get started.")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
            Button("Add Source") { sourcesVM.isShowingAddSource = true }
                .buttonStyle(DesignPrimaryButtonStyle(horizontalPadding: 18, verticalPadding: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Source Card

/// One configured source: status dot, name, type badge, endpoint and actions.
struct SourceCard: View {
    let source: IPTVSource
    let needsCredentials: Bool
    let isLoading: Bool
    let onViewChannels: () -> Void
    let onRefresh: () -> Void
    let onToggle: () -> Void
    let onSignIn: () -> Void
    var onEdit: () -> Void = {}
    let onRename: () -> Void
    let onDelete: () -> Void

    /// Grey when disabled, amber when it needs attention, green when healthy.
    private var statusColor: Color {
        if !source.isEnabled { return Theme.textTertiary }
        if needsCredentials || source.channelCount == 0 { return Theme.warning }
        return Theme.ok
    }

    private var statusText: String {
        if needsCredentials { return "Sign-in required" }
        if !source.isEnabled { return "Disabled" }
        if source.channelCount == 0 { return "No channels loaded" }
        guard let refreshed = source.lastRefreshedAt else { return "Never refreshed" }
        return "Updated \(refreshed.formatted(.relative(presentation: .named)))"
    }

    /// Subscription expiry, when the provider reports one.
    ///
    /// Lifetime and M3U sources send nothing, so the row is simply absent
    /// rather than showing a placeholder. Colour escalates as it approaches:
    /// a date two years out is not worth the same weight as one next week.
    private var expiryLine: (text: String, icon: String, color: Color)? {
        guard let expiry = source.expiresAt else { return nil }

        let formatted = expiry.formatted(date: .abbreviated, time: .omitted)
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0

        if expiry < Date() {
            return (
                "Expired \(expiry.formatted(.relative(presentation: .named))) · \(formatted)",
                "exclamationmark.circle.fill",
                Theme.destructive
            )
        }
        if days <= 14 {
            return (
                "Expires in \(days) day\(days == 1 ? "" : "s") · \(formatted)",
                "clock.badge.exclamationmark",
                Theme.warning
            )
        }
        return ("Expires \(formatted)", "calendar", Theme.textSecondary)
    }

    private var endpoint: String {
        source.serverURL ?? source.remoteURL ?? source.localFilePath ?? "—"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)

                    Text(source.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)

                    Text(source.type.displayName)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.fill))
                }

                Text(endpoint)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 4) {
                    Text("\(source.channelCount) channels")
                    Text("·")
                    Text(statusText)
                        .foregroundColor(statusColor == Theme.ok ? Theme.textSecondary : statusColor)
                }
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)

                if let expiry = expiryLine {
                    HStack(spacing: 5) {
                        Image(systemName: expiry.icon)
                            .font(.system(size: 10))
                        Text(expiry.text)
                        if source.isTrialAccount == true {
                            Text("TRIAL")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Theme.fill))
                        }
                        if let connections = source.maxConnections {
                            Text("· \(connections) connection\(connections == 1 ? "" : "s")")
                                .foregroundColor(Theme.textTertiary)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundColor(expiry.color)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().scaleEffect(0.6).frame(width: 20)
                }

                if needsCredentials {
                    Button("Sign In", action: onSignIn)
                        .buttonStyle(DesignPrimaryButtonStyle())
                } else if source.channelCount > 0 {
                    Button("Channels", action: onViewChannels)
                        .buttonStyle(DesignSecondaryButtonStyle())
                }

                Button("Edit", action: onEdit)
                    .buttonStyle(DesignSecondaryButtonStyle())

                Button("Refresh", action: onRefresh)
                    .buttonStyle(DesignSecondaryButtonStyle())

                Button(source.isEnabled ? "Disable" : "Enable", action: onToggle)
                    .buttonStyle(DesignSecondaryButtonStyle())

                Button("Remove", action: onDelete)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.destructive)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.panel).fill(Theme.surfaceRaised))
        .opacity(source.isEnabled ? 1 : 0.55)
        .contextMenu {
            Button("Edit…", action: onEdit)
            Button("Rename", action: onRename)
            if source.type == .xtreamCodes {
                Button("Update Credentials…", action: onSignIn)
            }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
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

// MARK: - Previews

struct SourcesView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SourcesView(selectedNav: .constant(.sources))
                .previewDisplayName("Sources — Dark")
                .preferredColorScheme(.dark)

            SourcesView(selectedNav: .constant(.sources))
                .previewDisplayName("Sources — Light")
                .preferredColorScheme(.light)
        }
        .environmentObject(SourcesViewModel())
        .environmentObject(ProfileViewModel())
        .environmentObject(ChannelViewModel())
        .frame(width: 820, height: 420)
    }
}

struct SourceCard_Previews: PreviewProvider {
    private static func sample(
        name: String,
        enabled: Bool = true,
        channels: Int = 1284,
        expiresIn days: Int? = nil,
        trial: Bool = false,
        connections: Int? = nil
    ) -> IPTVSource {
        var source = IPTVSource(
            profileID: UUID(),
            name: name,
            type: .xtreamCodes,
            serverURL: "http://provider.example:8080"
        )
        source.isEnabled = enabled
        source.channelCount = channels
        source.lastRefreshedAt = Date()
        source.expiresAt = days.map { Calendar.current.date(byAdding: .day, value: $0, to: Date())! }
        source.isTrialAccount = trial
        source.maxConnections = connections
        return source
    }

    private static func card(
        _ source: IPTVSource,
        needsCredentials: Bool = false,
        isLoading: Bool = false
    ) -> some View {
        SourceCard(
            source: source,
            needsCredentials: needsCredentials,
            isLoading: isLoading,
            onViewChannels: {}, onRefresh: {}, onToggle: {},
            onSignIn: {}, onRename: {}, onDelete: {}
        )
    }

    private static var allStates: some View {
        VStack(spacing: 12) {
            // Comfortably valid — neutral treatment.
            card(sample(name: "Home IPTV", expiresIn: 280, connections: 2))
            // Close to lapsing — amber.
            card(sample(name: "Renewing Soon", expiresIn: 6, connections: 1))
            // Lapsed — destructive, and sign-in is the fix.
            card(sample(name: "Lapsed Provider", channels: 0, expiresIn: -3), needsCredentials: true)
            // Trial account.
            card(sample(name: "Trial Line", expiresIn: 2, trial: true, connections: 1))
            // No expiry reported — the row is absent, not blank.
            card(sample(name: "Lifetime / M3U", expiresIn: nil))
        }
        .padding()
        .frame(width: 780)
    }

    static var previews: some View {
        Group {
            allStates
                .previewDisplayName("Source cards — Dark")
                .preferredColorScheme(.dark)

            allStates
                .previewDisplayName("Source cards — Light")
                .preferredColorScheme(.light)
        }
    }
}
