import SwiftUI

// MARK: - Live TV View

/// Browsable channel list with search, category filter, and source filter.
struct LiveTVView: View {
    @EnvironmentObject var channelVM: ChannelViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var sourcesVM: SourcesViewModel

    @State private var viewMode: ViewMode = .grid
    @State private var displayLimit = 120
    @State private var searchDraft = ""
    @State private var searchSyncTask: Task<Void, Never>?

    enum ViewMode: String, CaseIterable {
        case grid, list
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            Divider()

            // Content
            if channelVM.isLoading {
                loadingView
            } else if channelVM.filteredChannels.isEmpty {
                emptyView
            } else {
                channelContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: channelVM.searchText) { _ in displayLimit = 120 }
        .onChange(of: channelVM.selectedCategory) { _ in displayLimit = 120 }
        .onChange(of: channelVM.selectedSourceFilter) { _ in displayLimit = 120 }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                // Bound to local state, not straight to the view model. Writing a
                // @Published property on every keystroke fires objectWillChange
                // and invalidates this whole toolbar — including a Picker that
                // rebuilds a 323-item menu each time.
                TextField("Search channels...", text: $searchDraft)
                    .textFieldStyle(.plain)
                    .onChange(of: searchDraft) { newValue in
                        searchSyncTask?.cancel()
                        searchSyncTask = Task {
                            try? await Task.sleep(nanoseconds: 150_000_000)
                            guard !Task.isCancelled else { return }
                            channelVM.searchText = newValue
                        }
                    }
                if !searchDraft.isEmpty {
                    Button {
                        searchDraft = ""
                        searchSyncTask?.cancel()
                        channelVM.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .frame(maxWidth: 300)

            // Category filter. Equatable so SwiftUI can skip rebuilding its
            // menu — there are hundreds of categories and nothing about them
            // changes while the viewer types.
            CategoryPicker(
                categories: channelVM.categories,
                selection: $channelVM.selectedCategory
            )
            .equatable()
            .frame(maxWidth: 200)

            // Source filter
            if sourcesVM.sources.count > 1 {
                Picker("Source", selection: $channelVM.selectedSourceFilter) {
                    Text("All Sources").tag(nil as UUID?)
                    Divider()
                    ForEach(sourcesVM.sources) { source in
                        Text(source.name).tag(source.id as UUID?)
                    }
                }
                .frame(maxWidth: 180)
            }

            Spacer()

            // Channel count
            Text("\(channelVM.filteredChannelCount) channels")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // View mode
            Picker("View", selection: $viewMode) {
                Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                Image(systemName: "list.bullet").tag(ViewMode.list)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Channel Content

    @ViewBuilder
    private var channelContent: some View {
        switch viewMode {
        case .grid:
            channelGrid
        case .list:
            channelList
        }
    }

    private var channelGrid: some View {
        let items = Array(channelVM.filteredChannels.prefix(displayLimit))
        return ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16)],
                spacing: 16
            ) {
                ForEach(items, id: \.compoundID) { channel in
                    ChannelGridItem(
                        channel: channel,
                        isFavorite: channelVM.isFavorite(channel)
                    ) {
                        channelVM.recordWatch(channel)
                        playerVM.playChannel(channel)
                    } onFavorite: {
                        channelVM.toggleFavorite(channel)
                    }
                }
            }
            .padding(16)

            if channelVM.filteredChannels.count > displayLimit {
                Button {
                    displayLimit += 120
                } label: {
                    Text("Load More Channels (Showing \(displayLimit) of \(channelVM.filteredChannels.count))")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .padding(.vertical, 20)
            }
        }
    }

    private var channelList: some View {
        let items = Array(channelVM.filteredChannels.prefix(displayLimit))
        return List {
            ForEach(items, id: \.compoundID) { channel in
                ChannelListRow(
                    channel: channel,
                    isFavorite: channelVM.isFavorite(channel)
                ) {
                    channelVM.recordWatch(channel)
                    playerVM.playChannel(channel)
                } onFavorite: {
                    channelVM.toggleFavorite(channel)
                }
            }

            if channelVM.filteredChannels.count > displayLimit {
                Button {
                    displayLimit += 120
                } label: {
                    Text("Load More Channels (Showing \(displayLimit) of \(channelVM.filteredChannels.count))")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderless)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading channels...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: channelVM.searchText.isEmpty ? "tv.slash" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(channelVM.searchText.isEmpty ? "No channels available" : "No channels found")
                .font(.title2.bold())

            Text(channelVM.searchText.isEmpty
                 ? (sourcesVM.sources.isEmpty ? "Add an IPTV source to start browsing channels." : "Channels are not loaded yet.")
                 : "Try a different search term or filter.")
                .foregroundColor(.secondary)

            if sourcesVM.sources.isEmpty {
                Button {
                    sourcesVM.isShowingAddSource = true
                } label: {
                    Label("Add Source", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            } else if !channelVM.searchText.isEmpty || channelVM.selectedCategory != nil {
                Button("Clear Filters") {
                    channelVM.clearFilters()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Reload Channels") {
                    if let profileID = sourcesVM.profileID {
                        Task { await channelVM.loadChannels(profileID: profileID, sources: sourcesVM.sources) }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Channel Grid Item

struct ChannelGridItem: View {
    let channel: Channel
    let isFavorite: Bool
    let onPlay: () -> Void
    let onFavorite: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onPlay) {
            VStack(spacing: 0) {
                // Logo area
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(height: 100)
                    .overlay {
                        if let logoURL = channel.logoURL {
                            CachedImageView(url: logoURL)
                                .frame(width: 56, height: 56)
                        } else {
                            Image(systemName: "tv")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary)
                        }
                    }

                // Play overlay
                if isHovered {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.black.opacity(0.35))
                        .frame(height: 100)
                        .overlay {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                                .shadow(radius: 4)
                        }
                }

                // Favorite badge
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .padding(6)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                if let group = channel.group {
                    Text(group)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isHovered ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.15 : 0.05), radius: isHovered ? 8 : 2)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contextMenu {
            Button { onPlay() } label: {
                Label("Play", systemImage: "play.fill")
            }
            Button { onFavorite() } label: {
                Label(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: isFavorite ? "star.slash" : "star.fill")
            }
        }
    }
}

// MARK: - Channel List Row

struct ChannelListRow: View {
    let channel: Channel
    let isFavorite: Bool
    let onPlay: () -> Void
    let onFavorite: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                // Logo
            Group {
                if let logoURL = channel.logoURL {
                    CachedImageView(url: logoURL)
                        .frame(width: 36, height: 36)
                } else {
                    Image(systemName: "tv")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .frame(width: 36, height: 36)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.body.weight(.medium))

                if let group = channel.group {
                    Text(group)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Favorite indicator
            if isFavorite {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
            }

            // Play button
            Image(systemName: "play.fill")
                .foregroundColor(.blue)
        }
        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onPlay() } label: {
                Label("Play", systemImage: "play.fill")
            }
            Button { onFavorite() } label: {
                Label(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: isFavorite ? "star.slash" : "star.fill")
            }
        }
    }
}

// MARK: - Category Picker

/// Category menu, isolated from the rest of the toolbar.
///
/// A playlist can carry several hundred categories, and `Picker` builds a menu
/// item for every one of them on each view update. Conforming to `Equatable`
/// lets SwiftUI skip that work when only unrelated state — such as the search
/// text — has changed.
private struct CategoryPicker: View, Equatable {
    let categories: [String]
    @Binding var selection: String?

    static func == (lhs: CategoryPicker, rhs: CategoryPicker) -> Bool {
        lhs.selection == rhs.selection && lhs.categories == rhs.categories
    }

    var body: some View {
        Picker("Category", selection: $selection) {
            Text("All Categories").tag(nil as String?)
            Divider()
            ForEach(categories, id: \.self) { category in
                Text(category).tag(category as String?)
            }
        }
    }
}
