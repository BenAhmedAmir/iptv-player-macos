import Foundation

// MARK: - Persistence Controller

/// Manages local JSON-based persistence for profiles, sources, favorites, and history.
/// Uses Codable + file-based storage for macOS 13+ compatibility.
final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "com.iptvplayer.persistence", qos: .userInitiated)

    private var storageDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("IPTVPlayer", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        // Not pretty-printed: these are machine-written caches, and the largest
        // runs to tens of megabytes. Whitespace inflates the file, the write and
        // every subsequent decode. Keys stay sorted so writes remain diffable.
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - File Paths

    private var profilesFile: URL { storageDirectory.appendingPathComponent("profiles.json") }
    private var settingsFile: URL { storageDirectory.appendingPathComponent("settings.json") }

    private func sourcesFile(profileID: UUID) -> URL {
        profileDirectory(profileID).appendingPathComponent("sources.json")
    }

    private func favoritesFile(profileID: UUID) -> URL {
        profileDirectory(profileID).appendingPathComponent("favorites.json")
    }

    private func recentlyWatchedFile(profileID: UUID) -> URL {
        profileDirectory(profileID).appendingPathComponent("recently_watched.json")
    }

    private func playbackPositionsFile(profileID: UUID) -> URL {
        profileDirectory(profileID).appendingPathComponent("playback_positions.json")
    }

    private func catalogueFile(profileID: UUID, tab: CatalogueTab) -> URL {
        profileDirectory(profileID).appendingPathComponent("catalogue_\(tab.rawValue).json")
    }

    private func channelCacheFile(sourceID: UUID) -> URL {
        storageDirectory.appendingPathComponent("cache_\(sourceID.uuidString).json")
    }

    private func vodCategoriesFile(sourceID: UUID) -> URL {
        storageDirectory.appendingPathComponent("vod_cats_\(sourceID.uuidString).json")
    }

    private func vodMoviesFile(sourceID: UUID) -> URL {
        storageDirectory.appendingPathComponent("vod_movies_\(sourceID.uuidString).json")
    }

    private func seriesCategoriesFile(sourceID: UUID) -> URL {
        storageDirectory.appendingPathComponent("series_cats_\(sourceID.uuidString).json")
    }

    private func seriesFile(sourceID: UUID) -> URL {
        storageDirectory.appendingPathComponent("series_\(sourceID.uuidString).json")
    }

    private func profileDirectory(_ profileID: UUID) -> URL {
        let dir = storageDirectory.appendingPathComponent("profile_\(profileID.uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Generic Read/Write

    private func load<T: Codable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    /// Reads and decodes off the main thread.
    ///
    /// The big caches are slow enough to matter: decoding 14k channels measures
    /// ~90ms and 72k movies ~234ms. Done on the main actor — as every caller
    /// used to — that is a visible stall on launch, profile switch, and the
    /// first open of Movies.
    private func loadAsync<T: Codable>(_ type: T.Type, from url: URL) async -> T? {
        await withCheckedContinuation { continuation in
            // Serial queue, so sharing the decoder stays safe.
            queue.async { [decoder] in
                guard let data = try? Data(contentsOf: url) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: try? decoder.decode(T.self, from: data))
            }
        }
    }

    /// Save data asynchronously (for non-critical writes)
    private func saveAsync<T: Codable>(_ value: T, to url: URL) {
        queue.async { [encoder] in
            guard let data = try? encoder.encode(value) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Save data synchronously (for critical writes that must complete before reads)
    private func saveSync<T: Codable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Profiles

    func loadProfiles() -> [Profile] {
        load([Profile].self, from: profilesFile) ?? []
    }

    func saveProfiles(_ profiles: [Profile]) {
        saveSync(profiles, to: profilesFile)
    }

    // MARK: - Settings

    func loadSettings() -> AppSettings {
        load(AppSettings.self, from: settingsFile) ?? AppSettings()
    }

    func saveSettings(_ settings: AppSettings) {
        saveSync(settings, to: settingsFile)
    }

    // MARK: - Sources

    func loadSources(profileID: UUID) -> [IPTVSource] {
        load([IPTVSource].self, from: sourcesFile(profileID: profileID)) ?? []
    }

    func saveSources(_ sources: [IPTVSource], profileID: UUID) {
        // Synchronous write — channel loading reads sources immediately after
        saveSync(sources, to: sourcesFile(profileID: profileID))
    }

    // MARK: - Favorites

    func loadFavorites(profileID: UUID) -> [Favorite] {
        load([Favorite].self, from: favoritesFile(profileID: profileID)) ?? []
    }

    func saveFavorites(_ favorites: [Favorite], profileID: UUID) {
        saveSync(favorites, to: favoritesFile(profileID: profileID))
    }

    // MARK: - Recently Watched

    func loadRecentlyWatched(profileID: UUID) -> [RecentlyWatched] {
        load([RecentlyWatched].self, from: recentlyWatchedFile(profileID: profileID)) ?? []
    }

    func saveRecentlyWatched(_ items: [RecentlyWatched], profileID: UUID) {
        saveAsync(items, to: recentlyWatchedFile(profileID: profileID))
    }

    // MARK: - Playback Positions

    func loadPlaybackPositions(profileID: UUID) -> [PlaybackPosition] {
        load([PlaybackPosition].self, from: playbackPositionsFile(profileID: profileID)) ?? []
    }

    func savePlaybackPositions(_ positions: [PlaybackPosition], profileID: UUID) {
        // Written repeatedly during playback, so never block the player on it.
        saveAsync(positions, to: playbackPositionsFile(profileID: profileID))
    }

    // MARK: - Catalogue Preferences

    /// Sidebar selection, pins, expanded groups and filters — per profile and
    /// per tab, so Movies and TV Shows never share a selection.
    func loadCataloguePreferences(profileID: UUID, tab: CatalogueTab) -> CataloguePreferences {
        load(CataloguePreferences.self, from: catalogueFile(profileID: profileID, tab: tab))
            ?? .default
    }

    func saveCataloguePreferences(
        _ preferences: CataloguePreferences,
        profileID: UUID,
        tab: CatalogueTab
    ) {
        // Written on every pin, collapse and filter change, so never blocking.
        saveAsync(preferences, to: catalogueFile(profileID: profileID, tab: tab))
    }

    // MARK: - Channel Cache

    func loadCachedChannels(sourceID: UUID) -> [CachedChannel]? {
        load([CachedChannel].self, from: channelCacheFile(sourceID: sourceID))
    }

    func saveCachedChannels(_ channels: [CachedChannel], sourceID: UUID) {
        // Synchronous — channel loading reads this immediately after saving
        saveSync(channels, to: channelCacheFile(sourceID: sourceID))
    }

    /// Removes everything belonging to one source.
    ///
    /// Deleting a source used to drop only its channel cache and Keychain
    /// entry, leaving its VOD caches, categories and per-profile records on
    /// disk forever — invisible, but still counted and still taking space.
    func deleteAllData(sourceID: UUID, profileID: UUID) {
        // Source-scoped caches.
        for url in [
            channelCacheFile(sourceID: sourceID),
            vodCategoriesFile(sourceID: sourceID),
            vodMoviesFile(sourceID: sourceID),
            seriesCategoriesFile(sourceID: sourceID),
            seriesFile(sourceID: sourceID)
        ] {
            try? fileManager.removeItem(at: url)
        }

        // Profile-scoped records that point at this source.
        let favorites = loadFavorites(profileID: profileID).filter { $0.sourceID != sourceID }
        saveFavorites(favorites, profileID: profileID)

        let watched = loadRecentlyWatched(profileID: profileID).filter { $0.sourceID != sourceID }
        saveRecentlyWatched(watched, profileID: profileID)

        let positions = loadPlaybackPositions(profileID: profileID).filter { $0.sourceID != sourceID }
        savePlaybackPositions(positions, profileID: profileID)

        // Pinned categories and the selected category refer to ids that no
        // longer resolve, so browsing state resets with the source.
        for tab in [CatalogueTab.movies, .series] {
            saveCataloguePreferences(.default, profileID: profileID, tab: tab)
        }
    }

    func deleteCachedChannels(sourceID: UUID) {
        let url = channelCacheFile(sourceID: sourceID)
        try? fileManager.removeItem(at: url)
    }

    // MARK: - VOD & Series Cache

    func loadVODCategories(sourceID: UUID) -> [XtreamCategory]? {
        load([XtreamCategory].self, from: vodCategoriesFile(sourceID: sourceID))
    }

    func saveVODCategories(_ categories: [XtreamCategory], sourceID: UUID) {
        saveSync(categories, to: vodCategoriesFile(sourceID: sourceID))
    }

    func loadCachedMovies(sourceID: UUID) -> [Movie]? {
        load([Movie].self, from: vodMoviesFile(sourceID: sourceID))
    }

    func saveCachedMovies(_ movies: [Movie], sourceID: UUID) {
        saveSync(movies, to: vodMoviesFile(sourceID: sourceID))
    }

    func loadSeriesCategories(sourceID: UUID) -> [XtreamCategory]? {
        load([XtreamCategory].self, from: seriesCategoriesFile(sourceID: sourceID))
    }

    func saveSeriesCategories(_ categories: [XtreamCategory], sourceID: UUID) {
        saveSync(categories, to: seriesCategoriesFile(sourceID: sourceID))
    }

    func loadCachedSeries(sourceID: UUID) -> [Series]? {
        load([Series].self, from: seriesFile(sourceID: sourceID))
    }

    func saveCachedSeries(_ series: [Series], sourceID: UUID) {
        saveSync(series, to: seriesFile(sourceID: sourceID))
    }

    // MARK: - Async Cache Loads

    func loadCachedChannelsAsync(sourceID: UUID) async -> [CachedChannel]? {
        await loadAsync([CachedChannel].self, from: channelCacheFile(sourceID: sourceID))
    }

    func loadCachedMoviesAsync(sourceID: UUID) async -> [Movie]? {
        await loadAsync([Movie].self, from: vodMoviesFile(sourceID: sourceID))
    }

    func loadCachedSeriesAsync(sourceID: UUID) async -> [Series]? {
        await loadAsync([Series].self, from: seriesFile(sourceID: sourceID))
    }

    // MARK: - Profile Deletion

    func deleteProfileData(profileID: UUID) {
        let dir = profileDirectory(profileID)
        try? fileManager.removeItem(at: dir)
    }
}

// MARK: - Cached Channel (Codable wrapper)

/// Serializable version of Channel for disk caching.
struct CachedChannel: Codable {
    let id: String
    let sourceID: UUID
    let name: String
    let streamURL: String
    let logoURL: String?
    let group: String?
    let tvgID: String?
    let language: String?
    let country: String?

    init(from channel: Channel) {
        self.id = channel.id
        self.sourceID = channel.sourceID
        self.name = channel.name
        self.streamURL = channel.streamURL.absoluteString
        self.logoURL = channel.logoURL?.absoluteString
        self.group = channel.group
        self.tvgID = channel.tvgID
        self.language = channel.language
        self.country = channel.country
    }

    func toChannel() -> Channel? {
        guard let url = URL(string: streamURL) else { return nil }
        return Channel(
            id: id,
            sourceID: sourceID,
            name: name,
            streamURL: url,
            logoURL: logoURL.flatMap(URL.init(string:)),
            group: group,
            tvgID: tvgID,
            language: language,
            country: country
        )
    }
}
