import SwiftUI

// MARK: - Main Navigation View

/// Primary navigation with macOS sidebar.
struct MainNavigationView: View {
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var sourcesVM: SourcesViewModel
    @EnvironmentObject var channelVM: ChannelViewModel
    @EnvironmentObject var vodVM: VODViewModel
    @EnvironmentObject var playerVM: PlayerViewModel

    @State private var selectedNav: NavigationItem? = .home

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if let profile = profileVM.activeProfile {
                    Menu {
                        ForEach(profileVM.profiles) { p in
                            Button {
                                profileVM.selectProfile(p)
                            } label: {
                                HStack {
                                    Text(p.name)
                                    if p.id == profile.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        Divider()
                        Button("Manage Profiles") {
                            profileVM.isShowingProfilePicker = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            profileAvatar(for: profile)
                            Text(profile.name)
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    sourcesVM.isShowingAddSource = true
                } label: {
                    Label("Add Source", systemImage: "plus")
                }
                .help("Add a new IPTV source (⌘N)")
            }
        }
        .sheet(isPresented: $sourcesVM.isShowingAddSource) {
            AddSourceView()
                .environmentObject(sourcesVM)
                .environmentObject(profileVM)
        }
        .onAppear {
            if let profile = profileVM.activeProfile {
                sourcesVM.loadSources(profileID: profile.id)
                // Defer channel and VOD loading slightly to ensure sources are available
                DispatchQueue.main.async {
                    Task { await channelVM.loadChannels(profileID: profile.id, sources: sourcesVM.sources) }
                    vodVM.loadData(sources: sourcesVM.sources)
                }
            }
        }
        // Reload channels and VOD whenever the sources list changes
        .onChange(of: sourcesVM.sources.map(\.id)) { _ in
            reloadAllContent()
        }
        .onChange(of: sourcesVM.sources.map(\.channelCount)) { _ in
            reloadAllContent()
        }
        .onChange(of: sourcesVM.sources.map(\.isEnabled)) { _ in
            reloadAllContent()
        }
        .onChange(of: sourcesVM.loadingSourceID) { loadingID in
            if loadingID == nil {
                reloadAllContent()
            }
        }
    }

    private func reloadAllContent() {
        if let profile = profileVM.activeProfile {
            Task { await channelVM.loadChannels(profileID: profile.id, sources: sourcesVM.sources) }
            vodVM.loadData(sources: sourcesVM.sources)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedNav) {
            Section {
                NavigationLink(value: NavigationItem.home) {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(NavigationItem.home)
            }

            Section("Live TV") {
                NavigationLink(value: NavigationItem.liveTV) {
                    Label("All Channels", systemImage: "tv")
                        .badge(channelVM.totalChannelCount)
                }
                .tag(NavigationItem.liveTV)

                NavigationLink(value: NavigationItem.favorites) {
                    Label("Favorites", systemImage: "star.fill")
                        .badge(channelVM.favorites.count)
                }
                .tag(NavigationItem.favorites)
            }

            Section("On Demand") {
                NavigationLink(value: NavigationItem.movies) {
                    Label("Movies", systemImage: "film.stack.fill")
                        .badge(vodVM.filteredMovies.count)
                }
                .tag(NavigationItem.movies)

                NavigationLink(value: NavigationItem.series) {
                    Label("TV Shows", systemImage: "tv.inset.filled")
                        .badge(vodVM.filteredSeries.count)
                }
                .tag(NavigationItem.series)
            }

            Section {
                NavigationLink(value: NavigationItem.sources) {
                    Label("Sources", systemImage: "externaldrive.connected.to.line.below")
                        .badge(sourcesVM.sources.count)
                }
                .tag(NavigationItem.sources)
            }

            Section {
                NavigationLink(value: NavigationItem.settings) {
                    Label("Settings", systemImage: "gear")
                }
                .tag(NavigationItem.settings)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
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
            MoviesView()
        case .series:
            SeriesView()
        case .sources:
            SourcesView(selectedNav: $selectedNav)
        case .settings:
            SettingsView()
        case .none:
            HomeView(selectedNav: $selectedNav)
        }
    }

    // MARK: - Profile Avatar

    private func profileAvatar(for profile: Profile) -> some View {
        let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .teal]
        let color = colors[abs(profile.name.hashValue) % colors.count]

        return Circle()
            .fill(color.gradient)
            .frame(width: 24, height: 24)
            .overlay(
                Text(profile.name.prefix(1).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            )
    }
}
