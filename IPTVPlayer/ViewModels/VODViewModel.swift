import Foundation
import SwiftUI
import Combine

// MARK: - VOD View Model

/// Manages Movies and TV Shows (Series) browsing, categories, filtering, and episode retrieval.
@MainActor
final class VODViewModel: ObservableObject {
    // MARK: - Movies State
    @Published var movies: [Movie] = []
    @Published var movieCategories: [XtreamCategory] = []
    @Published var selectedMovieCategory: XtreamCategory?
    @Published var movieSearchText: String = ""
    @Published var filteredMovies: [Movie] = []
    @Published var displayedMovieLimit: Int = 80
    @Published var isLoadingMovies: Bool = false
    @Published var hasLoadedMovies: Bool = false

    // MARK: - Series State
    @Published var series: [Series] = []
    @Published var seriesCategories: [XtreamCategory] = []
    @Published var selectedSeriesCategory: XtreamCategory?
    @Published var seriesSearchText: String = ""
    @Published var filteredSeries: [Series] = []
    @Published var displayedSeriesLimit: Int = 80
    @Published var isLoadingSeries: Bool = false
    @Published var hasLoadedSeries: Bool = false

    // MARK: - Selected Series Details State
    // MARK: - Catalogue Browsing

    @Published private(set) var moviePreferences = CataloguePreferences.default
    @Published private(set) var seriesPreferences = CataloguePreferences.default

    /// Item tallies per category id, filled in as categories load.
    @Published private(set) var movieCategoryCounts: [String: Int] = [:]
    @Published private(set) var seriesCategoryCounts: [String: Int] = [:]

    private var profileID: UUID?
    private var watchState = CatalogueFiltering.WatchState.empty
    private var movieFilterTask: Task<Void, Never>?
    private var seriesFilterTask: Task<Void, Never>?

    /// Loads the per-profile, per-tab browsing state. Called when the profile
    /// becomes active; without it nothing is persisted.
    func loadPreferences(profileID: UUID) {
        self.profileID = profileID
        moviePreferences = persistence.loadCataloguePreferences(profileID: profileID, tab: .movies)
        seriesPreferences = persistence.loadCataloguePreferences(profileID: profileID, tab: .series)
        watchState = CatalogueFiltering.WatchState.make(
            from: persistence.loadPlaybackPositions(profileID: profileID)
        )
        applyMovieFilters()
        applySeriesFilters()
    }

    /// Last failure per tab. Surfaced as a banner rather than thrown away, so a
    /// dead provider is visible instead of looking like an empty catalogue.
    @Published var movieError: IPTVError?
    @Published var seriesError: IPTVError?

    func error(for tab: CatalogueTab) -> IPTVError? {
        tab == .movies ? movieError : seriesError
    }

    func clearError(for tab: CatalogueTab) {
        if tab == .movies { movieError = nil } else { seriesError = nil }
    }

    private func report(_ error: Error, for tab: CatalogueTab) {
        let mapped = (error as? IPTVError) ?? .unknown(error.localizedDescription)
        if tab == .movies { movieError = mapped } else { seriesError = mapped }
    }

    @Published private(set) var isRefreshingMovies = false
    @Published private(set) var isRefreshingSeries = false

    func isRefreshing(_ tab: CatalogueTab) -> Bool {
        tab == .movies ? isRefreshingMovies : isRefreshingSeries
    }

    /// Re-pulls categories and the whole catalogue from the provider.
    ///
    /// Bypasses both caches on purpose: the in-memory one would return the same
    /// titles, and the disk one is what the viewer is trying to get past.
    func refreshCatalogue(_ tab: CatalogueTab) async {
        guard let source = sources.first,
              let serverURL = source.serverURL,
              let creds = KeychainService.shared.getCredentials(sourceID: source.id) else {
            // No usable source or no Keychain entry — say so rather than
            // returning to an empty screen with no explanation.
            if !sources.isEmpty { report(IPTVError.invalidCredentials, for: tab) }
            return
        }

        // Validate the account first. An expired or suspended Xtream account
        // commonly answers the catalogue endpoints with HTTP 200 and "{}",
        // which would otherwise read as a legitimately empty catalogue.
        do {
            _ = try await xtreamService.authenticate(
                serverURL: serverURL, username: creds.username, password: creds.password
            )
        } catch {
            report(error, for: tab)
            return
        }

        if tab == .movies {
            guard !isRefreshingMovies else { return }
            isRefreshingMovies = true
            defer { isRefreshingMovies = false }

            do {
                let cats = try await xtreamService.getVODCategories(
                    serverURL: serverURL, username: creds.username, password: creds.password
                )
                movieCategories = hidesRestrictedContent
                    ? cats.filter { !ContentRestriction.isRestricted(category: $0.categoryName) }
                    : cats
                persistence.saveVODCategories(cats, sourceID: source.id)
            } catch {
                // Report and stop: fetching titles against a server that just
                // refused the category call would only fail again.
                report(error, for: .movies)
                return
            }

            moviesByCategory.removeAll()
            await selectMovieCategory(nil)
        } else {
            guard !isRefreshingSeries else { return }
            isRefreshingSeries = true
            defer { isRefreshingSeries = false }

            do {
                let cats = try await xtreamService.getSeriesCategories(
                    serverURL: serverURL, username: creds.username, password: creds.password
                )
                seriesCategories = hidesRestrictedContent
                    ? cats.filter { !ContentRestriction.isRestricted(category: $0.categoryName) }
                    : cats
                persistence.saveSeriesCategories(cats, sourceID: source.id)
            } catch {
                report(error, for: .series)
                return
            }

            seriesByCategory.removeAll()
            await selectSeriesCategory(nil)
        }

        // A provider that answers but returns nothing leaves an empty screen;
        // name it rather than letting it look like a successful refresh.
        let isEmpty = tab == .movies ? movies.isEmpty : series.isEmpty
        if isEmpty, error(for: tab) == nil {
            report(IPTVError.emptyChannelList, for: tab)
        }

        update(tab) { $0.lastRefreshedAt = Date() }
    }

    /// How many titles in this tab have a resumable position.
    func continueWatchingCount(in tab: CatalogueTab) -> Int {
        let keys = watchState.inProgressKeys
        guard !keys.isEmpty else { return 0 }
        return tab == .movies
            ? movies.reduce(into: 0) { $0 += keys.contains($1.catalogueKey) ? 1 : 0 }
            : series.reduce(into: 0) { $0 += keys.contains($1.catalogueKey) ? 1 : 0 }
    }

    /// Recomputes sidebar tallies from whatever is loaded. Counts are only as
    /// complete as the catalogue in memory — selecting "All" loads everything
    /// and fills them in.
    func refreshCategoryCounts(for tab: CatalogueTab) {
        if tab == .movies {
            movieCategoryCounts = CatalogueFiltering.counts(for: movies)
        } else {
            seriesCategoryCounts = CatalogueFiltering.counts(for: series)
        }
    }

    private func persist(_ tab: CatalogueTab) {
        guard let profileID else { return }
        let preferences = tab == .movies ? moviePreferences : seriesPreferences
        persistence.saveCataloguePreferences(preferences, profileID: profileID, tab: tab)
    }

    // MARK: Mutations

    func select(_ selection: CategorySelection, in tab: CatalogueTab) {
        update(tab) { $0.selection = selection }
    }

    func togglePin(categoryID: String, in tab: CatalogueTab) {
        update(tab) { preferences in
            if let index = preferences.pinnedCategoryIDs.firstIndex(of: categoryID) {
                preferences.pinnedCategoryIDs.remove(at: index)
            } else {
                preferences.pinnedCategoryIDs.append(categoryID)
            }
        }
    }

    func isPinned(categoryID: String, in tab: CatalogueTab) -> Bool {
        preferences(for: tab).pinnedCategoryIDs.contains(categoryID)
    }

    func toggleGroup(_ group: String, in tab: CatalogueTab) {
        update(tab) { preferences in
            if let index = preferences.expandedGroups.firstIndex(of: group) {
                preferences.expandedGroups.remove(at: index)
            } else {
                preferences.expandedGroups.append(group)
            }
        }
    }

    func isGroupExpanded(_ group: String, in tab: CatalogueTab) -> Bool {
        preferences(for: tab).expandedGroups.contains(group)
    }

    /// Expands the locale's group the first time a catalogue is seen, so the
    /// sidebar is not a wall of collapsed headers.
    func seedExpandedGroupIfNeeded(groups: [String], in tab: CatalogueTab) {
        guard preferences(for: tab).expandedGroups.isEmpty,
              let preferred = CategoryNaming.defaultExpandedGroup(from: groups) else {
            return
        }
        update(tab) { $0.expandedGroups = [preferred] }
    }

    func setFilters(_ filters: CatalogueFilters, in tab: CatalogueTab) {
        update(tab) { $0.filters = filters }
    }

    func resetFilters(in tab: CatalogueTab) {
        update(tab) { $0.filters = .none }
    }

    func setSort(_ sort: CatalogueSort, in tab: CatalogueTab) {
        update(tab) { $0.filters.sort = sort }
    }

    func preferences(for tab: CatalogueTab) -> CataloguePreferences {
        tab == .movies ? moviePreferences : seriesPreferences
    }

    private func update(_ tab: CatalogueTab, _ mutate: (inout CataloguePreferences) -> Void) {
        if tab == .movies {
            mutate(&moviePreferences)
            applyMovieFilters()
        } else {
            mutate(&seriesPreferences)
            applySeriesFilters()
        }
        persist(tab)
    }

    @Published var selectedSeries: Series?
    @Published var episodesBySeason: [Int: [Episode]] = [:]
    @Published var availableSeasons: [Int] = []
    @Published var selectedSeason: Int = 1
    @Published var isLoadingEpisodes: Bool = false

    // Dependencies
    private let persistence = PersistenceController.shared
    private let xtreamService = XtreamAPIService()
    private var sources: [IPTVSource] = []
    private var cancellables = Set<AnyCancellable>()

    // In-memory cache for fast category switching
    /// Kids profiles never see adult categories.
    var hidesRestrictedContent = false

    private var moviesByCategory: [String: [Movie]] = [:]
    private var seriesByCategory: [String: [Series]] = [:]

    init() {
        setupSearchDebouncing()
    }

    private func setupSearchDebouncing() {
        $movieSearchText
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.applyMovieFilters()
            }
            .store(in: &cancellables)

        $seriesSearchText
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.applySeriesFilters()
            }
            .store(in: &cancellables)
    }

    // MARK: - Initial Loading

    func loadData(sources: [IPTVSource]) {
        self.sources = sources.filter { $0.isEnabled && $0.type == .xtreamCodes }

        guard !self.sources.isEmpty else {
            movies = []
            filteredMovies = []
            movieCategories = []
            series = []
            filteredSeries = []
            seriesCategories = []
            return
        }

        Task {
            await loadMovieCategoriesAndInitialContent()
            await loadSeriesCategoriesAndInitialContent()
        }
    }

    // MARK: - Movies Logic

    func loadMovieCategoriesAndInitialContent() async {
        guard let source = sources.first,
              let serverURL = source.serverURL,
              let creds = KeychainService.shared.getCredentials(sourceID: source.id) else {
            // No usable source or no Keychain entry — say so rather than
            // returning to an empty screen with no explanation.
            if !sources.isEmpty { report(IPTVError.invalidCredentials, for: .movies) }
            return
        }

        // Try disk cache for categories first
        if let cachedCats = persistence.loadVODCategories(sourceID: source.id), !cachedCats.isEmpty {
            self.movieCategories = cachedCats
        }

        if let cachedMovies = await persistence.loadCachedMoviesAsync(sourceID: source.id), !cachedMovies.isEmpty {
            self.movies = cachedMovies
            self.hasLoadedMovies = true
            self.applyMovieFilters()
        }

        // Fetch fresh categories from API
        do {
            let cats = try await xtreamService.getVODCategories(
                serverURL: serverURL,
                username: creds.username,
                password: creds.password
            )
            self.movieCategories = hidesRestrictedContent
                ? cats.filter { !ContentRestriction.isRestricted(category: $0.categoryName) }
                : cats
            self.persistence.saveVODCategories(cats, sourceID: source.id)

            // Always load the entire catalogue. The sidebar filters in memory,
            // so a partial set silently empties every category — and the cache
            // cannot be trusted to be complete (older builds wrote one category
            // into it). Cached titles already painted above, so this refreshes
            // rather than blocks.
            await selectMovieCategory(nil)
        } catch {
            report(error, for: .movies)
        }
    }

    func selectMovieCategory(_ category: XtreamCategory?) async {
        selectedMovieCategory = category
        displayedMovieLimit = 80

        guard let source = sources.first,
              let serverURL = source.serverURL,
              let creds = KeychainService.shared.getCredentials(sourceID: source.id) else {
            // No usable source or no Keychain entry — say so rather than
            // returning to an empty screen with no explanation.
            if !sources.isEmpty { report(IPTVError.invalidCredentials, for: .movies) }
            return
        }

        let catID = category?.categoryID ?? ""

        // Check cache first
        if let cached = moviesByCategory[catID], !cached.isEmpty {
            self.movies = cached
            self.applyMovieFilters()
            return
        }

        isLoadingMovies = true
        defer { isLoadingMovies = false }

        do {
            let streams = try await xtreamService.getVODStreams(
                serverURL: serverURL,
                username: creds.username,
                password: creds.password,
                categoryID: catID.isEmpty ? nil : catID
            )

            let converted = xtreamService.convertToMovies(
                streams: streams,
                categories: movieCategories,
                serverURL: serverURL,
                username: creds.username,
                password: creds.password,
                sourceID: source.id
            )

            self.movieError = nil
            self.moviesByCategory[catID] = converted
            self.movies = converted
            self.hasLoadedMovies = true
            self.applyMovieFilters()

            // Only ever cache the *whole* catalogue. Writing one category over
            // it leaves a partial file that looks complete on next launch, so
            // "All" shows a handful of titles and every other category is empty.
            if catID.isEmpty {
                self.persistence.saveCachedMovies(converted, sourceID: source.id)
            }
        } catch {
            report(error, for: .movies)
        }
    }

    func loadMoreMovies() {
        if displayedMovieLimit < filteredMovies.count {
            displayedMovieLimit += 60
        }
    }

    /// Debounced and off the main actor: a provider category can hold thousands
    /// of titles, and the sidebar plus grid must stay responsive while typing.
    func applyMovieFilters() {
        refreshCategoryCounts(for: .movies)
        let items = movies
        let selection = moviePreferences.selection
        let search = movieSearchText
        let filters = moviePreferences.filters
        let watch = watchState

        movieFilterTask?.cancel()
        movieFilterTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }

            let result = await Task.detached(priority: .userInitiated) {
                CatalogueFiltering.apply(
                    to: items, selection: selection, search: search,
                    filters: filters, watch: watch
                )
            }.value

            guard !Task.isCancelled else { return }
            self?.filteredMovies = result
        }
    }


    func loadSeriesCategoriesAndInitialContent() async {
        guard let source = sources.first,
              let serverURL = source.serverURL,
              let creds = KeychainService.shared.getCredentials(sourceID: source.id) else {
            // No usable source or no Keychain entry — say so rather than
            // returning to an empty screen with no explanation.
            if !sources.isEmpty { report(IPTVError.invalidCredentials, for: .series) }
            return
        }

        if let cachedCats = persistence.loadSeriesCategories(sourceID: source.id), !cachedCats.isEmpty {
            self.seriesCategories = cachedCats
        }

        if let cachedSeries = await persistence.loadCachedSeriesAsync(sourceID: source.id), !cachedSeries.isEmpty {
            self.series = cachedSeries
            self.hasLoadedSeries = true
            self.applySeriesFilters()
        }

        do {
            let cats = try await xtreamService.getSeriesCategories(
                serverURL: serverURL,
                username: creds.username,
                password: creds.password
            )
            self.seriesCategories = hidesRestrictedContent
                ? cats.filter { !ContentRestriction.isRestricted(category: $0.categoryName) }
                : cats
            self.persistence.saveSeriesCategories(cats, sourceID: source.id)

            // Same as movies: always fetch the whole catalogue, then filter in memory.
            await selectSeriesCategory(nil)
        } catch {
            report(error, for: .series)
        }
    }

    func selectSeriesCategory(_ category: XtreamCategory?) async {
        selectedSeriesCategory = category
        displayedSeriesLimit = 80

        guard let source = sources.first,
              let serverURL = source.serverURL,
              let creds = KeychainService.shared.getCredentials(sourceID: source.id) else {
            // No usable source or no Keychain entry — say so rather than
            // returning to an empty screen with no explanation.
            if !sources.isEmpty { report(IPTVError.invalidCredentials, for: .series) }
            return
        }

        let catID = category?.categoryID ?? ""

        // Check cache
        if let cached = seriesByCategory[catID], !cached.isEmpty {
            self.series = cached
            self.applySeriesFilters()
            return
        }

        isLoadingSeries = true
        defer { isLoadingSeries = false }

        do {
            let items = try await xtreamService.getSeries(
                serverURL: serverURL,
                username: creds.username,
                password: creds.password,
                categoryID: catID.isEmpty ? nil : catID
            )

            let converted = xtreamService.convertToSeries(
                items: items,
                categories: seriesCategories,
                serverURL: serverURL,
                username: creds.username,
                password: creds.password,
                sourceID: source.id
            )

            self.seriesError = nil
            self.seriesByCategory[catID] = converted
            self.series = converted
            self.hasLoadedSeries = true
            self.applySeriesFilters()

            // Same as movies: only the complete catalogue is cacheable.
            if catID.isEmpty {
                self.persistence.saveCachedSeries(converted, sourceID: source.id)
            }
        } catch {
            report(error, for: .series)
        }
    }

    func loadMoreSeries() {
        if displayedSeriesLimit < filteredSeries.count {
            displayedSeriesLimit += 60
        }
    }

    func applySeriesFilters() {
        refreshCategoryCounts(for: .series)
        let items = series
        let selection = seriesPreferences.selection
        let search = seriesSearchText
        let filters = seriesPreferences.filters
        let watch = watchState

        seriesFilterTask?.cancel()
        seriesFilterTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }

            let result = await Task.detached(priority: .userInitiated) {
                CatalogueFiltering.apply(
                    to: items, selection: selection, search: search,
                    filters: filters, watch: watch
                )
            }.value

            guard !Task.isCancelled else { return }
            self?.filteredSeries = result
        }
    }

    /// Genres present in the loaded series, for the filter menu. The provider
    /// mixes languages (Drama / Drame / دراما), so these are listed as sent
    /// rather than merged — collapsing them would guess at translations.
    var availableGenres: [String] {
        var counts: [String: Int] = [:]
        for show in series {
            for genre in show.genreList { counts[genre, default: 0] += 1 }
        }
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map(\.key)
    }

    // MARK: - Series Details & Episodes

    func openSeriesDetails(_ item: Series) {
        selectedSeries = item
        episodesBySeason = [:]
        availableSeasons = []
        selectedSeason = 1
        isLoadingEpisodes = true

        guard let source = sources.first(where: { $0.id == item.sourceID }) ?? sources.first,
              let serverURL = source.serverURL,
              let creds = KeychainService.shared.getCredentials(sourceID: source.id) else {
            isLoadingEpisodes = false
            return
        }

        Task {
            do {
                let info = try await xtreamService.getSeriesInfo(
                    serverURL: serverURL,
                    username: creds.username,
                    password: creds.password,
                    seriesID: item.id
                )

                let episodes = xtreamService.convertToEpisodes(
                    response: info,
                    seriesID: item.id,
                    serverURL: serverURL,
                    username: creds.username,
                    password: creds.password,
                    sourceID: source.id
                )

                var dict: [Int: [Episode]] = [:]
                for ep in episodes {
                    dict[ep.seasonNumber, default: []].append(ep)
                }

                self.episodesBySeason = dict
                let seasons = dict.keys.sorted()
                self.availableSeasons = seasons
                self.selectedSeason = seasons.first ?? 1
                self.isLoadingEpisodes = false
            } catch {
                print("Failed to load series info: \(error.localizedDescription)")
                self.isLoadingEpisodes = false
            }
        }
    }

    func closeSeriesDetails() {
        selectedSeries = nil
        episodesBySeason = [:]
        availableSeasons = []
    }
}
