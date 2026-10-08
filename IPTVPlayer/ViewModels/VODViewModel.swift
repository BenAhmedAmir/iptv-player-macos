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
    // MARK: - Catalogue Filters

    /// Sort orders for the movie grid. Recency uses the provider's `added`
    /// timestamp, which is the only reliable date movies carry.
    enum MovieSortOrder: String, CaseIterable, Identifiable {
        case recentlyAdded, highestRated, newest, nameAscending

        var id: String { rawValue }

        var label: String {
            switch self {
            case .recentlyAdded: return "Recently Added"
            case .highestRated: return "Highest Rated"
            case .newest: return "Newest First"
            case .nameAscending: return "Name (A–Z)"
            }
        }

        func sort(_ items: [Movie]) -> [Movie] {
            switch self {
            case .recentlyAdded:
                return items.sorted { ($0.addedDate ?? .distantPast) > ($1.addedDate ?? .distantPast) }
            case .highestRated:
                return items.sorted { ($0.normalizedRating ?? -1) > ($1.normalizedRating ?? -1) }
            case .newest:
                return items.sorted { ($0.year ?? Int.min) > ($1.year ?? Int.min) }
            case .nameAscending:
                return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }
    }

    enum SeriesSortOrder: String, CaseIterable, Identifiable {
        case highestRated, newest, nameAscending

        var id: String { rawValue }

        var label: String {
            switch self {
            case .highestRated: return "Highest Rated"
            case .newest: return "Newest First"
            case .nameAscending: return "Name (A–Z)"
            }
        }

        func sort(_ items: [Series]) -> [Series] {
            switch self {
            case .highestRated:
                return items.sorted { ($0.normalizedRating ?? -1) > ($1.normalizedRating ?? -1) }
            case .newest:
                return items.sorted { ($0.year ?? Int.min) > ($1.year ?? Int.min) }
            case .nameAscending:
                return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }
    }

    @Published var movieMinimumRating: Double? { didSet { applyMovieFiltersIfChanged(oldValue, movieMinimumRating) } }
    @Published var movieMinimumYear: Int? { didSet { applyMovieFiltersIfChanged(oldValue, movieMinimumYear) } }
    @Published var movieSortOrder: MovieSortOrder = .recentlyAdded { didSet { applyMovieFiltersIfChanged(oldValue, movieSortOrder) } }

    @Published var seriesMinimumRating: Double? { didSet { applySeriesFiltersIfChanged(oldValue, seriesMinimumRating) } }
    @Published var seriesMinimumYear: Int? { didSet { applySeriesFiltersIfChanged(oldValue, seriesMinimumYear) } }
    @Published var selectedGenre: String? { didSet { applySeriesFiltersIfChanged(oldValue, selectedGenre) } }
    @Published var seriesSortOrder: SeriesSortOrder = .highestRated { didSet { applySeriesFiltersIfChanged(oldValue, seriesSortOrder) } }

    /// Filtering runs from didSet, not a Combine sink on the published value: a
    /// @Published publisher fires in willSet, so a sink would re-filter while
    /// the property still held its previous value.
    private func applyMovieFiltersIfChanged<T: Equatable>(_ old: T, _ new: T) {
        guard old != new else { return }
        displayedMovieLimit = 80
        applyMovieFilters()
    }

    private func applySeriesFiltersIfChanged<T: Equatable>(_ old: T, _ new: T) {
        guard old != new else { return }
        displayedSeriesLimit = 80
        applySeriesFilters()
    }

    var movieFiltersActive: Bool {
        movieMinimumRating != nil || movieMinimumYear != nil || movieSortOrder != .recentlyAdded
    }

    var seriesFiltersActive: Bool {
        seriesMinimumRating != nil || seriesMinimumYear != nil || selectedGenre != nil || seriesSortOrder != .highestRated
    }

    func resetMovieFilters() {
        movieMinimumRating = nil
        movieMinimumYear = nil
        movieSortOrder = .recentlyAdded
    }

    func resetSeriesFilters() {
        seriesMinimumRating = nil
        seriesMinimumYear = nil
        selectedGenre = nil
        seriesSortOrder = .highestRated
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
            self.movieCategories = cats
            self.persistence.saveVODCategories(cats, sourceID: source.id)

            // If movies haven't been loaded yet, load the first category or top movies
            if movies.isEmpty {
                await selectMovieCategory(cats.first)
            }
        } catch {
            print("Failed to fetch VOD categories: \(error.localizedDescription)")
        }
    }

    func selectMovieCategory(_ category: XtreamCategory?) async {
        selectedMovieCategory = category
        displayedMovieLimit = 80

        guard let source = sources.first,
              let serverURL = source.serverURL,
              let creds = KeychainService.shared.getCredentials(sourceID: source.id) else {
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

            self.moviesByCategory[catID] = converted
            self.movies = converted
            self.hasLoadedMovies = true
            self.applyMovieFilters()

            // Save cache if this is the all or main category
            if catID.isEmpty || category?.categoryID == movieCategories.first?.categoryID {
                self.persistence.saveCachedMovies(converted, sourceID: source.id)
            }
        } catch {
            print("Failed to fetch VOD streams: \(error.localizedDescription)")
        }
    }

    func loadMoreMovies() {
        if displayedMovieLimit < filteredMovies.count {
            displayedMovieLimit += 60
        }
    }

    private func applyMovieFilters() {
        var result = movies

        if !movieSearchText.isEmpty {
            let query = movieSearchText.lowercased()
            result = result.filter { $0.name.lowercased().contains(query) }
        }

        if let minimum = movieMinimumRating {
            // Unrated titles are excluded rather than treated as zero: ~13% of
            // this catalogue reports no rating, and they are not all bad films.
            result = result.filter { ($0.normalizedRating ?? -1) >= minimum }
        }

        if let minimum = movieMinimumYear {
            result = result.filter { ($0.year ?? Int.min) >= minimum }
        }

        result = movieSortOrder.sort(result)
        filteredMovies = result
    }

    // MARK: - Series Logic

    func loadSeriesCategoriesAndInitialContent() async {
        guard let source = sources.first,
              let serverURL = source.serverURL,
              let creds = KeychainService.shared.getCredentials(sourceID: source.id) else {
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
            self.seriesCategories = cats
            self.persistence.saveSeriesCategories(cats, sourceID: source.id)

            if series.isEmpty {
                await selectSeriesCategory(cats.first)
            }
        } catch {
            print("Failed to fetch Series categories: \(error.localizedDescription)")
        }
    }

    func selectSeriesCategory(_ category: XtreamCategory?) async {
        selectedSeriesCategory = category
        displayedSeriesLimit = 80

        guard let source = sources.first,
              let serverURL = source.serverURL,
              let creds = KeychainService.shared.getCredentials(sourceID: source.id) else {
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

            self.seriesByCategory[catID] = converted
            self.series = converted
            self.hasLoadedSeries = true
            self.applySeriesFilters()

            if catID.isEmpty || category?.categoryID == seriesCategories.first?.categoryID {
                self.persistence.saveCachedSeries(converted, sourceID: source.id)
            }
        } catch {
            print("Failed to fetch series items: \(error.localizedDescription)")
        }
    }

    func loadMoreSeries() {
        if displayedSeriesLimit < filteredSeries.count {
            displayedSeriesLimit += 60
        }
    }

    private func applySeriesFilters() {
        var result = series

        if !seriesSearchText.isEmpty {
            let query = seriesSearchText.lowercased()
            result = result.filter { $0.name.lowercased().contains(query) }
        }

        if let minimum = seriesMinimumRating {
            result = result.filter { ($0.normalizedRating ?? -1) >= minimum }
        }

        if let minimum = seriesMinimumYear {
            result = result.filter { ($0.year ?? Int.min) >= minimum }
        }

        if let genre = selectedGenre {
            result = result.filter { $0.genreList.contains(genre) }
        }

        result = seriesSortOrder.sort(result)
        filteredSeries = result
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
