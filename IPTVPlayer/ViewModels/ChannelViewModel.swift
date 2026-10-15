import Foundation
import SwiftUI
import Combine

// MARK: - Channel View Model

/// Manages channel browsing, search, filtering, favorites, and recently watched.
@MainActor
final class ChannelViewModel: ObservableObject {
    @Published var allChannels: [Channel] = []
    @Published var filteredChannels: [Channel] = []
    @Published var categories: [String] = []
    @Published var searchText = ""

    // Filtering runs from `didSet`, not from a `$selectedCategory` sink. A
    // @Published publisher fires in willSet, so a sink would call applyFilters()
    // while this property still held the *previous* value — selecting a category
    // would list the previously selected one. didSet runs after the assignment.
    @Published var selectedCategory: String? {
        didSet {
            guard oldValue != selectedCategory else { return }
            applyFilters()
        }
    }
    @Published var favorites: [Favorite] = []
    @Published var recentlyWatched: [RecentlyWatched] = []
    @Published var isLoading = false

    /// Same willSet hazard as `selectedCategory` — see the note there.
    @Published var selectedSourceFilter: UUID? {
        didSet {
            guard oldValue != selectedSourceFilter else { return }
            applyFilters()
        }
    }

    private let persistence = PersistenceController.shared
    private var profileID: UUID?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Search stays on a debounced pipeline: it fires per keystroke and the
        // filter walks every channel, so coalescing matters on large playlists.
        // The debounce also defers past the willSet emission, so applyFilters()
        // reads the committed searchText. Category and source filters are
        // single discrete actions and run synchronously from didSet instead.
        $searchText
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.applyFilters()
            }
            .store(in: &cancellables)
    }

    // MARK: - Load Channels

    /// Loads the channel caches off the main thread.
    ///
    /// Decoding measures ~90ms per 14k-channel source, which used to run on the
    /// main actor and stall launch and every profile switch.
    func loadChannels(profileID: UUID, sources: [IPTVSource]) async {
        self.profileID = profileID
        isLoading = true

        let enabledSources = sources.filter { $0.isEnabled }
        var channels: [Channel] = []

        for source in enabledSources {
            if let cached = await persistence.loadCachedChannelsAsync(sourceID: source.id) {
                let sourceChannels = cached.compactMap { $0.toChannel() }
                channels.append(contentsOf: sourceChannels)
            }
        }

        allChannels = channels
        rebuildSearchIndex()
        extractCategories()
        applyFilters()

        // Load favorites and history
        favorites = persistence.loadFavorites(profileID: profileID)
        recentlyWatched = persistence.loadRecentlyWatched(profileID: profileID)

        isLoading = false
    }

    // MARK: - Categories

    private func extractCategories() {
        var groups = Set(allChannels.compactMap { $0.group })
        if hidesRestrictedContent {
            groups = groups.filter { !ContentRestriction.isRestricted(category: $0) }
        }
        categories = groups.sorted()
    }

    // MARK: - Filtering

    /// Lowercased "name group" per channel, parallel to `allChannels`.
    ///
    /// Searching used to call `lowercased()` on every channel's name and group
    /// on each pass — ~24ms over 14k channels, allocating two strings per row.
    /// Folding the case once at load time removes that from the hot path.
    private var searchIndex: [String] = []

    /// Per-category tallies, rebuilt with the channel list.
    private var categoryCounts: [String: Int] = [:]

    /// Set from the active profile. Kids profiles never see adult categories,
    /// in the list or in the category sidebar.
    var hidesRestrictedContent = false

    private var filterTask: Task<Void, Never>?

    private func rebuildSearchIndex() {
        categoryCounts.removeAll()
        searchIndex = allChannels.map {
            ($0.name + " " + ($0.group ?? "")).lowercased()
        }
    }

    func applyFilters() {
        let channels = allChannels
        let index = searchIndex
        let sourceFilter = selectedSourceFilter
        let category = selectedCategory
        let query = searchText.lowercased()
        let hideRestricted = hidesRestrictedContent

        // Small result sets are not worth a thread hop; the hitch only shows up
        // on large playlists.
        guard channels.count > 2_000 else {
            filteredChannels = Self.filter(
                channels: channels, index: index,
                sourceFilter: sourceFilter, category: category, query: query,
                hideRestricted: hideRestricted
            )
            return
        }

        filterTask?.cancel()
        filterTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Self.filter(
                    channels: channels, index: index,
                    sourceFilter: sourceFilter, category: category, query: query,
                    hideRestricted: hideRestricted
                )
            }.value

            guard !Task.isCancelled else { return }
            self?.filteredChannels = result
        }
    }

    /// Pure so it can run off the main actor. `index` is positional, so it must
    /// be the one built for `channels`.
    nonisolated private static func filter(
        channels: [Channel],
        index: [String],
        sourceFilter: UUID?,
        category: String?,
        query: String,
        hideRestricted: Bool
    ) -> [Channel] {
        let useIndex = !query.isEmpty && index.count == channels.count
        var result: [Channel] = []
        result.reserveCapacity(min(channels.count, 512))

        for (position, channel) in channels.enumerated() {
            if hideRestricted, ContentRestriction.isRestricted(category: channel.group) { continue }
            if let sourceFilter, channel.sourceID != sourceFilter { continue }
            if let category, channel.group != category { continue }
            if !query.isEmpty {
                let haystack = useIndex
                    ? index[position]
                    : (channel.name + " " + (channel.group ?? "")).lowercased()
                if !haystack.contains(query) { continue }
            }
            result.append(channel)
        }
        return result
    }

    func clearFilters() {
        searchText = ""
        selectedCategory = nil
        selectedSourceFilter = nil
    }

    // MARK: - Favorites

    func isFavorite(_ channel: Channel) -> Bool {
        favorites.contains { $0.compoundChannelID == channel.compoundID }
    }

    func toggleFavorite(_ channel: Channel) {
        guard let profileID = profileID else { return }

        if let index = favorites.firstIndex(where: { $0.compoundChannelID == channel.compoundID }) {
            favorites.remove(at: index)
        } else {
            let favorite = Favorite(
                profileID: profileID,
                sourceID: channel.sourceID,
                channelID: channel.id,
                channelName: channel.name
            )
            favorites.append(favorite)
        }

        persistence.saveFavorites(favorites, profileID: profileID)
    }

    func favoriteChannels() -> [Channel] {
        let favoriteIDs = Set(favorites.map { $0.compoundChannelID })
        return allChannels.filter { favoriteIDs.contains($0.compoundID) }
    }

    // MARK: - Recently Watched

    func recordWatch(_ channel: Channel) {
        guard let profileID = profileID else { return }

        // Update or add
        if let index = recentlyWatched.firstIndex(where: { $0.compoundChannelID == channel.compoundID }) {
            recentlyWatched[index].lastWatchedAt = Date()
        } else {
            let entry = RecentlyWatched(
                profileID: profileID,
                sourceID: channel.sourceID,
                channelID: channel.id,
                channelName: channel.name
            )
            recentlyWatched.append(entry)
        }

        // Sort by most recent and limit to 20
        recentlyWatched.sort { $0.lastWatchedAt > $1.lastWatchedAt }
        if recentlyWatched.count > 20 {
            recentlyWatched = Array(recentlyWatched.prefix(20))
        }

        persistence.saveRecentlyWatched(recentlyWatched, profileID: profileID)
    }

    func recentChannels() -> [Channel] {
        let recentIDs = recentlyWatched.sorted { $0.lastWatchedAt > $1.lastWatchedAt }
            .map { $0.compoundChannelID }
        let channelMap = Dictionary(allChannels.map { ($0.compoundID, $0) }, uniquingKeysWith: { first, _ in first })
        return recentIDs.compactMap { channelMap[$0] }
    }

    // MARK: - Channel Count

    var totalChannelCount: Int { allChannels.count }

    /// Channel tally per category, for the counts beside the category list.
    /// Cached because the sidebar asks for every category on each render.
    func channelCount(inCategory category: String) -> Int {
        if let cached = categoryCounts[category] { return cached }
        let count = allChannels.reduce(into: 0) { total, channel in
            if channel.group == category { total += 1 }
        }
        categoryCounts[category] = count
        return count
    }
    var filteredChannelCount: Int { filteredChannels.count }
}
