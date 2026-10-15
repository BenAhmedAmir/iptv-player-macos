import SwiftUI

// MARK: - Home View

/// Landing screen: greeting, Continue Watching, Favorites and Recently Added.
struct HomeView: View {
    @Binding var selectedNav: NavigationItem?
    @EnvironmentObject var channelVM: ChannelViewModel
    @EnvironmentObject var vodVM: VODViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var sourcesVM: SourcesViewModel

    /// Read once per appearance rather than per render — it touches the disk.
    @State private var resumable: [PlaybackPosition] = []

    var body: some View {
        Group {
            if sourcesVM.sources.filter(\.isEnabled).isEmpty {
                welcomeState
            } else if isLoading {
                loadingSkeleton
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .onAppear { resumable = playerVM.resumableItems(limit: 3) }
        .onChange(of: playerVM.showPlayer) { isShowing in
            // Refresh when the player closes, so progress is current.
            if !isShowing { resumable = playerVM.resumableItems(limit: 3) }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text(greeting)
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.5)
                    .foregroundColor(Theme.textPrimary)

                if !resumable.isEmpty {
                    continueWatchingSection
                }

                if !favoriteChannels.isEmpty {
                    favoritesSection
                }

                if !recentMovies.isEmpty {
                    recentMoviesSection
                }

                if resumable.isEmpty && favoriteChannels.isEmpty && recentMovies.isEmpty {
                    gettingStarted
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 32)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part: String
        switch hour {
        case 5..<12: part = "Good morning"
        case 12..<18: part = "Good afternoon"
        default: part = "Good evening"
        }
        guard let name = profileVM.activeProfile?.name else { return part }
        return "\(part), \(name)"
    }

    // MARK: - Continue Watching

    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Continue Watching")

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3),
                spacing: 16
            ) {
                ForEach(resumable) { item in
                    ContinueWatchingCard(position: item) {
                        playerVM.resume(item)
                    }
                }
            }
        }
    }

    // MARK: - Favorites

    private var favoriteChannels: [Channel] {
        Array(channelVM.favoriteChannels().prefix(8))
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Favorites", actionTitle: "Show all") {
                selectedNav = .favorites
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                spacing: 12
            ) {
                ForEach(favoriteChannels, id: \.compoundID) { channel in
                    ChannelTileCard(channel: channel) {
                        channelVM.recordWatch(channel)
                        playerVM.playChannel(channel)
                    } onToggleFavorite: {
                        channelVM.toggleFavorite(channel)
                    }
                }
            }
        }
    }

    // MARK: - Recently Added

    /// Newest by the provider's `added` timestamp, which is the only date
    /// movies actually carry.
    private var recentMovies: [Movie] {
        vodVM.movies
            .sorted { ($0.addedDate ?? .distantPast) > ($1.addedDate ?? .distantPast) }
            .prefix(7)
            .map { $0 }
    }

    private var recentMoviesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Recently Added Movies", actionTitle: "Show all") {
                selectedNav = .movies
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 7),
                spacing: 14
            ) {
                ForEach(recentMovies, id: \.compoundID) { movie in
                    PosterCard(
                        title: movie.name,
                        meta: movieMeta(movie),
                        artworkURL: movie.posterURL,
                        progress: 0
                    ) {
                        playerVM.playMovie(movie)
                    }
                }
            }
        }
    }

    private func movieMeta(_ movie: Movie) -> String {
        var parts: [String] = []
        if let year = movie.year { parts.append(String(year)) }
        if let rating = movie.normalizedRating {
            parts.append("★ \(String(format: "%.1f", rating))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Empty States

    private var welcomeState: some View {
        VStack(spacing: 14) {
            Text("Welcome to IPTV Player")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.5)
                .foregroundColor(Theme.textPrimary)

            Text("Add a playlist from your provider to see live channels, movies and TV shows. You can add an M3U link or Xtream Codes login.")
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 460)

            Button("Add Your First Source") {
                sourcesVM.isShowingAddSource = true
            }
            .buttonStyle(DesignPrimaryButtonStyle(horizontalPadding: 18, verticalPadding: 8))
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gettingStarted: some View {
        EmptyStateView(
            kind: .empty(
                title: "Nothing to pick up yet",
                message: "Browse Live TV, star a few channels, or start a movie — they will show up here."
            ),
            actionTitle: "Browse Live TV"
        ) {
            selectedNav = .liveTV
        }
        .frame(minHeight: 260)
    }

    private var isLoading: Bool {
        channelVM.isLoading || (vodVM.isLoadingMovies && vodVM.movies.isEmpty)
    }

    /// Mirrors the real sections so the page keeps its shape while loading.
    private var loadingSkeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                SkeletonBlock(cornerRadius: 6)
                    .frame(width: 260, height: 26)

                VStack(alignment: .leading, spacing: 12) {
                    SkeletonBlock(cornerRadius: 4).frame(width: 150, height: 14)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3),
                        spacing: 16
                    ) {
                        ForEach(0..<3, id: \.self) { _ in
                            SkeletonBlock(cornerRadius: Theme.Radius.card)
                                .aspectRatio(16 / 9, contentMode: .fit)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SkeletonBlock(cornerRadius: 4).frame(width: 110, height: 14)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                        spacing: 12
                    ) {
                        ForEach(0..<4, id: \.self) { _ in
                            SkeletonBlock(cornerRadius: Theme.Radius.card).frame(height: 64)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Continue Watching Card

/// 16:9 card with a watch-progress bar and a kind badge.
struct ContinueWatchingCard: View {
    let position: PlaybackPosition
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottom) {
                    artwork
                    WatchProgressBar(
                        fraction: position.fractionComplete,
                        height: 4,
                        tint: Theme.textPrimary,
                        trackColor: Color.white.opacity(0.2)
                    )
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .stroke(Theme.tileBorder, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    DesignBadge(
                        text: position.isEpisode == true ? "EPISODE" : "MOVIE",
                        background: Color.black.opacity(0.5)
                    )
                    .padding(10)
                }

                Text(position.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                Text(remainingText)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var artwork: some View {
        if let raw = position.artworkURL, let url = URL(string: raw) {
            PosterImageView(url: url)
        } else {
            Rectangle().fill(IdentityColor.artwork(for: position.title))
        }
    }

    private var remainingText: String {
        guard position.duration > 0 else {
            return position.subtitle ?? ""
        }
        let remaining = Int((position.duration - position.seconds) / 60)
        let suffix = remaining > 0 ? "\(remaining) min left" : "Almost finished"
        guard let subtitle = position.subtitle, !subtitle.isEmpty else { return suffix }
        return "\(subtitle) · \(suffix)"
    }
}

// MARK: - Poster Card

/// 2:3 poster with title and metadata, used by Home and the VOD grids.
struct PosterCard: View {
    let title: String
    let meta: String
    let artworkURL: URL?
    var progress: Double = 0
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .bottom) {
                    if let artworkURL {
                        PosterImageView(url: artworkURL)
                    } else {
                        Rectangle()
                            .fill(IdentityColor.artwork(for: title))
                            .overlay(alignment: .bottomLeading) {
                                Text(title)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(3)
                                    .padding(10)
                            }
                    }

                    if progress > 0 {
                        WatchProgressBar(
                            fraction: progress,
                            height: 3,
                            tint: Theme.textPrimary,
                            trackColor: Color.white.opacity(0.25)
                        )
                    }
                }
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.tile)
                        .stroke(Theme.tileBorder, lineWidth: 1)
                )

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            HomeView(selectedNav: .constant(.home))
                .previewDisplayName("Home — Dark")
                .preferredColorScheme(.dark)

            HomeView(selectedNav: .constant(.home))
                .previewDisplayName("Home — Light")
                .preferredColorScheme(.light)
        }
        .environmentObject(ChannelViewModel())
        .environmentObject(VODViewModel())
        .environmentObject(PlayerViewModel())
        .environmentObject(ProfileViewModel())
        .environmentObject(SourcesViewModel())
        .frame(width: 900, height: 620)
    }
}
