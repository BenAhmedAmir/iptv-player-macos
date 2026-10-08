import SwiftUI

// MARK: - Home View

/// Home screen showing recently watched, favorites, and channel preview.
struct HomeView: View {
    @Binding var selectedNav: NavigationItem?
    @EnvironmentObject var channelVM: ChannelViewModel
    @EnvironmentObject var vodVM: VODViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var sourcesVM: SourcesViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Header & Greeting
                headerSection

                // Quick Action Cards / Channel Banner
                if channelVM.totalChannelCount > 0 {
                    channelsOverviewBanner
                }

                // Recently Watched
                let recentChannels = channelVM.recentChannels()
                if !recentChannels.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Recently Watched", icon: "clock.fill")

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(recentChannels, id: \.compoundID) { channel in
                                    ChannelCard(channel: channel, isFavorite: channelVM.isFavorite(channel)) {
                                        channelVM.recordWatch(channel)
                                        playerVM.playChannel(channel)
                                    } onFavorite: {
                                        channelVM.toggleFavorite(channel)
                                    }
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }
                }

                // Favorites
                let favChannels = channelVM.favoriteChannels()
                if !favChannels.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Favorites", icon: "star.fill")

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(favChannels, id: \.compoundID) { channel in
                                    ChannelCard(channel: channel, isFavorite: true) {
                                        channelVM.recordWatch(channel)
                                        playerVM.playChannel(channel)
                                    } onFavorite: {
                                        channelVM.toggleFavorite(channel)
                                    }
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }
                }

                // Channels Preview on Home
                if !channelVM.allChannels.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SectionHeader(title: "Live Channels", icon: "tv.fill")
                            Spacer()
                            Button {
                                selectedNav = .liveTV
                            } label: {
                                HStack(spacing: 4) {
                                    Text("View All (\(channelVM.totalChannelCount))")
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                }
                                .font(.subheadline.weight(.medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                        }

                        // Grid of first 18 channels
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 14)],
                            spacing: 14
                        ) {
                            ForEach(Array(channelVM.allChannels.prefix(18)), id: \.compoundID) { channel in
                                ChannelCard(channel: channel, isFavorite: channelVM.isFavorite(channel)) {
                                    channelVM.recordWatch(channel)
                                    playerVM.playChannel(channel)
                                } onFavorite: {
                                    channelVM.toggleFavorite(channel)
                                }
                            }
                        }
                    }
                }

                // Movies Preview on Home
                if !vodVM.filteredMovies.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SectionHeader(title: "Featured Movies", icon: "film.stack.fill")
                            Spacer()
                            Button {
                                selectedNav = .movies
                            } label: {
                                HStack(spacing: 4) {
                                    Text("View All (\(vodVM.filteredMovies.count))")
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                }
                                .font(.subheadline.weight(.medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.orange)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 14) {
                                ForEach(Array(vodVM.filteredMovies.prefix(12)), id: \.compoundID) { movie in
                                    MovieCard(movie: movie) {
                                        playerVM.playMovie(movie)
                                    }
                                    .frame(width: 140)
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }
                }

                // TV Shows Preview on Home
                if !vodVM.filteredSeries.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SectionHeader(title: "Featured TV Shows", icon: "tv.inset.filled")
                            Spacer()
                            Button {
                                selectedNav = .series
                            } label: {
                                HStack(spacing: 4) {
                                    Text("View All (\(vodVM.filteredSeries.count))")
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                }
                                .font(.subheadline.weight(.medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.purple)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 14) {
                                ForEach(Array(vodVM.filteredSeries.prefix(12)), id: \.compoundID) { item in
                                    SeriesCard(series: item) {
                                        vodVM.openSeriesDetails(item)
                                    }
                                    .frame(width: 140)
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }
                } else if sourcesVM.sources.isEmpty {
                    // Truly empty state (no sources configured)
                    noSourcesState
                } else {
                    // Sources configured but channels not loaded yet
                    loadingChannelsState
                }

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                if let profile = profileVM.activeProfile {
                    Text(profile.name)
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if channelVM.totalChannelCount > 0 {
                Button {
                    selectedNav = .liveTV
                } label: {
                    Label("Browse All Channels", systemImage: "play.tv.fill")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Overview Banner

    private var channelsOverviewBanner: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 14)],
            spacing: 14
        ) {
            // Live TV quick card
            Button {
                selectedNav = .liveTV
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "tv.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.blue.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(channelVM.totalChannelCount) Channels")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Live TV")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
            .buttonStyle(.plain)

            // Movies quick card
            Button {
                selectedNav = .movies
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "film.stack.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.orange.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(vodVM.filteredMovies.count) Movies")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("On Demand")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
            .buttonStyle(.plain)

            // TV Shows quick card
            Button {
                selectedNav = .series
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "tv.inset.filled")
                        .font(.system(size: 24))
                        .foregroundColor(.purple)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.purple.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(vodVM.filteredSeries.count) TV Shows")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Series & Seasons")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
            .buttonStyle(.plain)

            // Favorites quick card
            Button {
                selectedNav = .favorites
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.yellow)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.yellow.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(channelVM.favorites.count) Favorites")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Saved Channels")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Empty States

    private var noSourcesState: some View {
        VStack(spacing: 20) {
            Image(systemName: "tv.inset.filled")
                .font(.system(size: 56))
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            VStack(spacing: 6) {
                Text("Welcome to IPTV Player")
                    .font(.title2.bold())

                Text("Add an IPTV source to start browsing and watching channels.")
                    .foregroundColor(.secondary)
            }

            Button {
                sourcesVM.isShowingAddSource = true
            } label: {
                Label("Add Source", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var loadingChannelsState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading channels from sources...")
                .foregroundColor(.secondary)

            Button("Refresh Sources") {
                if let profile = profileVM.activeProfile {
                    for source in sourcesVM.sources {
                        Task { await sourcesVM.refreshSource(source) }
                    }
                    Task { await channelVM.loadChannels(profileID: profile.id, sources: sourcesVM.sources) }
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text(title)
                .font(.title3.bold())
        }
    }
}

// MARK: - Channel Card

struct ChannelCard: View {
    let channel: Channel
    let isFavorite: Bool
    let onPlay: () -> Void
    let onFavorite: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 8) {
                // Logo area
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 140, height: 90)

                    if let logoURL = channel.logoURL {
                        CachedImageView(url: logoURL)
                            .frame(width: 60, height: 60)
                    } else {
                        Image(systemName: "tv")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                    }

                    // Play overlay
                    if isHovered {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.black.opacity(0.4))
                            .frame(width: 140, height: 90)

                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.white)
                    }

                    // Favorite badge
                    if isFavorite {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                                    .padding(6)
                            }
                            Spacer()
                        }
                    }
                }

                // Channel name
                Text(channel.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)

                // Group
                if let group = channel.group {
                    Text(group)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(width: 140, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button {
                onPlay()
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                onFavorite()
            } label: {
                Label(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: isFavorite ? "star.slash" : "star.fill")
            }
        }
    }
}
