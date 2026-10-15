import SwiftUI

// MARK: - Main Navigation View

/// Application shell: a fixed sidebar beside a titled content column.
///
/// Built from a plain `HStack` rather than `NavigationSplitView` because the
/// design specifies an exact 232pt sidebar with its own grouping, counts and a
/// profile row pinned to the bottom — none of which a split view's sidebar
/// styling allows. Search lives in the shell header and drives whichever screen
/// is showing, as the design puts one search affordance in the chrome rather
/// than one per screen.
struct MainNavigationView: View {
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var sourcesVM: SourcesViewModel
    @EnvironmentObject var channelVM: ChannelViewModel
    @EnvironmentObject var vodVM: VODViewModel
    @EnvironmentObject var playerVM: PlayerViewModel

    @State private var selectedNav: NavigationItem? = .home
    @State private var searchDraft = ""
    @State private var searchSyncTask: Task<Void, Never>?
    @State private var isRefreshingChannels = false
    @State private var channelError: IPTVError?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            mainColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .sheet(isPresented: $sourcesVM.isShowingAddSource) {
            AddSourceView()
                .environmentObject(sourcesVM)
                .environmentObject(profileVM)
        }
        .onAppear {
            if let profile = profileVM.activeProfile {
                // Kids profiles never see adult categories.
                channelVM.hidesRestrictedContent = profile.isRestricted
                vodVM.hidesRestrictedContent = profile.isRestricted
                // Sidebar selection, pins, expanded groups and filters.
                vodVM.loadPreferences(profileID: profile.id)
                sourcesVM.loadSources(profileID: profile.id)
                // Defer channel and VOD loading slightly to ensure sources are available
                DispatchQueue.main.async {
                    Task { await channelVM.loadChannels(profileID: profile.id, sources: sourcesVM.sources) }
                    vodVM.loadData(sources: sourcesVM.sources)
                }
            }
        }
        // Each screen keeps its own query, so the field is reloaded when switching.
        .onChange(of: selectedNav) { _ in
            searchSyncTask?.cancel()
            searchDraft = currentSearchText
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 1) {
            // Clears the window's traffic lights.
            Spacer().frame(height: 42)

            navRow(.home, title: "Home", icon: "house")

            sectionLabel("Live TV")
            navRow(.liveTV, title: "Channels", icon: "tv",
                   trailing: count(channelVM.totalChannelCount))
            navRow(.favorites, title: "Favorites", icon: "star",
                   trailing: count(channelVM.favorites.count))

            sectionLabel("On Demand")
            navRow(.movies, title: "Movies", icon: "film",
                   trailing: count(vodVM.movies.count))
            navRow(.series, title: "TV Shows", icon: "sparkles.tv",
                   trailing: count(vodVM.series.count))

            sectionLabel("Library")
            navRow(.sources, title: "Sources", icon: "externaldrive",
                   trailing: AnyView(
                    Circle()
                        .fill(sourceStatusColor)
                        .frame(width: 7, height: 7)
                   ))
            navRow(.settings, title: "Settings", icon: "gearshape")

            Spacer(minLength: 12)

            profileSwitcher
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .frame(width: Theme.Metrics.sidebarWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(Theme.surfaceRaised)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.separator).frame(width: 1)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Theme.textTertiary)
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private func count(_ value: Int) -> AnyView {
        AnyView(
            Text(value, format: .number)
                .font(.system(size: 12))
                .foregroundColor(Theme.textTertiary)
        )
    }

    private func navRow(
        _ item: NavigationItem,
        title: String,
        icon: String,
        trailing: AnyView? = nil
    ) -> some View {
        let isSelected = selectedNav == item
        return Button {
            selectedNav = item
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Theme.accent)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                Spacer(minLength: 4)
                trailing
            }
            .padding(.horizontal, 10)
            .frame(height: Theme.Metrics.navRowHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .fill(isSelected ? Theme.fillSelected : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Green when every enabled source has channels, amber when one came back
    /// empty, grey when there are none at all.
    private var sourceStatusColor: Color {
        let enabled = sourcesVM.sources.filter(\.isEnabled)
        if enabled.isEmpty { return Theme.textTertiary }
        return enabled.contains { $0.channelCount == 0 } ? Theme.warning : Theme.ok
    }

    private var profileSwitcher: some View {
        Button {
            profileVM.isShowingProfilePicker = true
        } label: {
            HStack(spacing: 10) {
                profileAvatar(for: profileVM.activeProfile)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profileVM.activeProfile?.name ?? "No Profile")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                    Text(profileVM.activeProfile?.isRestricted == true
                         ? "Restricted · Switch profile"
                         : "Switch profile")
                        .font(.system(size: 11))
                        .foregroundColor(profileVM.activeProfile?.isRestricted == true
                                         ? Theme.accent : Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: Theme.Radius.tile, color: Theme.fill)
    }

    private func profileAvatar(for profile: Profile?) -> some View {
        let name = profile?.name ?? "?"
        return Circle()
            .fill(AvatarPalette.gradient(for: profile?.avatarColorID))
            .frame(width: 28, height: 28)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            )
    }

    // MARK: - Main Column

    private var mainColumn: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.separator)

            if let error = channelError, selectedNav == .liveTV || selectedNav == .favorites {
                ErrorBanner(
                    title: channelErrorTitle(error),
                    message: channelVM.totalChannelCount > 0
                        ? "\(error.localizedDescription) Showing the channels from the last successful update."
                        : error.localizedDescription,
                    actionTitle: "Open Sources",
                    action: { selectedNav = .sources },
                    onRetry: { Task { await refreshChannels() } },
                    onDismiss: { channelError = nil },
                    isRetrying: isRefreshingChannels
                )
            }

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.surface)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(screenTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.textPrimary)

            Spacer(minLength: 0)

            if selectedNav == .sources {
                Button("Add Source") {
                    sourcesVM.isShowingAddSource = true
                }
                .buttonStyle(DesignPrimaryButtonStyle())
                .help("Add a new IPTV source (⌘N)")
            }

            // Live TV channels come from the same API; Movies and TV Shows have
            // their own refresh in the catalogue header.
            if selectedNav == .liveTV || selectedNav == .favorites {
                Button {
                    Task { await refreshChannels() }
                } label: {
                    Group {
                        if isRefreshingChannels {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.textPrimary)
                .disabled(isRefreshingChannels)
                .help("Reload channels from your provider (⌘R)")
                .keyboardShortcut("r", modifiers: .command)
            }

            if showsSearch {
                DesignSearchField(placeholder: searchPlaceholder, text: $searchDraft)
                    .onChange(of: searchDraft) { newValue in
                        // Debounced so a keystroke does not republish to a view
                        // model that hundreds of rows observe.
                        searchSyncTask?.cancel()
                        searchSyncTask = Task {
                            try? await Task.sleep(nanoseconds: 150_000_000)
                            guard !Task.isCancelled else { return }
                            applySearch(newValue)
                        }
                    }
            }
        }
        .padding(.leading, 22)
        .padding(.trailing, 16)
        .frame(height: Theme.Metrics.headerHeight)
    }

    /// Re-fetches every enabled source, then reloads the channel list.
    private func refreshChannels() async {
        guard !isRefreshingChannels, let profile = profileVM.activeProfile else { return }
        isRefreshingChannels = true
        defer { isRefreshingChannels = false }
        channelError = nil

        for source in sourcesVM.sources where source.isEnabled {
            await sourcesVM.refreshSource(source)
            // refreshSource reports through the Sources alert; on Live TV that
            // alert is never presented, so the failure is captured here instead
            // and shown inline.
            if let error = sourcesVM.error {
                channelError = error
                sourcesVM.error = nil
                sourcesVM.showError = false
            }
        }
        await channelVM.loadChannels(profileID: profile.id, sources: sourcesVM.sources)
    }

    private func channelErrorTitle(_ error: IPTVError) -> String {
        switch error {
        case .expiredAccount: return "Your subscription has expired"
        case .invalidCredentials: return "Your provider rejected the sign-in"
        case .networkUnavailable: return "No internet connection"
        case .timeout: return "Your provider timed out"
        default: return "Couldn’t refresh channels"
        }
    }

    private var screenTitle: String {
        switch selectedNav {
        case .home, .none: return "Home"
        case .liveTV: return channelVM.selectedCategory ?? "Channels"
        case .favorites: return "Favorites"
        case .movies: return "Movies"
        case .series: return "TV Shows"
        case .sources: return "Sources"
        case .settings: return "Settings"
        }
    }

    private var showsSearch: Bool {
        switch selectedNav {
        case .liveTV, .favorites, .movies, .series: return true
        default: return false
        }
    }

    private var searchPlaceholder: String {
        switch selectedNav {
        case .movies: return "Search movies"
        case .series: return "Search TV shows"
        default: return "Search channels"
        }
    }

    private var currentSearchText: String {
        switch selectedNav {
        case .movies: return vodVM.movieSearchText
        case .series: return vodVM.seriesSearchText
        default: return channelVM.searchText
        }
    }

    private func applySearch(_ value: String) {
        switch selectedNav {
        case .movies: vodVM.movieSearchText = value
        case .series: vodVM.seriesSearchText = value
        default: channelVM.searchText = value
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selectedNav {
        case .home:
            HomeView(selectedNav: $selectedNav)
        case .liveTV:
            LiveTVView()
        case .favorites:
            FavoritesView()
        case .movies:
            MoviesView(onOpenSources: { selectedNav = .sources })
        case .series:
            SeriesView(onOpenSources: { selectedNav = .sources })
        case .sources:
            SourcesView(selectedNav: $selectedNav)
        case .settings:
            SettingsView()
        case .none:
            HomeView(selectedNav: $selectedNav)
        }
    }
}

// MARK: - Previews

struct MainNavigationView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MainNavigationView().previewDisplayName("Shell — Dark").preferredColorScheme(.dark)
            MainNavigationView().previewDisplayName("Shell — Light").preferredColorScheme(.light)
        }
        .environmentObject(ProfileViewModel())
        .environmentObject(SourcesViewModel())
        .environmentObject(ChannelViewModel())
        .environmentObject(VODViewModel())
        .environmentObject(PlayerViewModel())
        .frame(width: 1100, height: 680)
    }
}
