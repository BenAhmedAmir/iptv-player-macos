import SwiftUI

// MARK: - Movies View

/// Displays VOD Movies catalog with category filtering, instant search, and poster grid.
struct MoviesView: View {
    @EnvironmentObject var vodVM: VODViewModel
    @EnvironmentObject var playerVM: PlayerViewModel

    @State private var movieDraft = ""
    @State private var movieDraftSyncTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Header with search & category selector
            toolbarSection

            Divider()

            // Main Content Area
            if vodVM.isLoadingMovies && vodVM.movies.isEmpty {
                loadingView
            } else if vodVM.filteredMovies.isEmpty && !vodVM.isLoadingMovies {
                emptyView
            } else {
                movieGrid
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Toolbar Section

    private var toolbarSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Category Picker
                Menu {
                    Button("All Categories") {
                        Task { await vodVM.selectMovieCategory(nil) }
                    }

                    Divider()

                    ForEach(vodVM.movieCategories) { cat in
                        Button(cat.categoryName) {
                            Task { await vodVM.selectMovieCategory(cat) }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text(vodVM.selectedMovieCategory?.categoryName ?? "All Categories")
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 220, alignment: .leading)
                }
                .menuStyle(.borderedButton)

                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    // Local draft, pushed to the view model on a short debounce. Writing
                    // the @Published property per keystroke invalidates this whole
                    // toolbar, rebuilding a category menu of hundreds of items.
                    TextField("Search movies...", text: $movieDraft)
                        .textFieldStyle(.plain)
                        .onChange(of: movieDraft) { newValue in
                            movieDraftSyncTask?.cancel()
                            movieDraftSyncTask = Task {
                                try? await Task.sleep(nanoseconds: 150_000_000)
                                guard !Task.isCancelled else { return }
                                vodVM.movieSearchText = newValue
                            }
                        }

                    if !movieDraft.isEmpty {
                        Button {
                            movieDraft = ""
                            movieDraftSyncTask?.cancel()
                            vodVM.movieSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(7)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                CatalogueFilterMenu(
                    isActive: vodVM.movieFiltersActive,
                    onReset: { vodVM.resetMovieFilters() }
                ) {
                    RatingFilterRow(minimumRating: $vodVM.movieMinimumRating)

                    YearFilterRow(
                        minimumYear: $vodVM.movieMinimumYear,
                        // Providers send no year field for movies, so it is read
                        // out of the title — about 62% of this catalogue has one.
                        caption: "Movies without a year in the title are hidden."
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Sort by", systemImage: "arrow.up.arrow.down")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Picker("", selection: $vodVM.movieSortOrder) {
                            ForEach(VODViewModel.MovieSortOrder.allCases) { order in
                                Text(order.label).tag(order)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }

                Spacer()

                // Movie Count
                Text("\(vodVM.filteredMovies.count) Movies")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Refresh Button
                Button {
                    Task {
                        await vodVM.selectMovieCategory(vodVM.selectedMovieCategory)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh movies")
                .disabled(vodVM.isLoadingMovies)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            // Category Chips (quick access horizontal scroll)
            if !vodVM.movieCategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        categoryChip(
                            title: "All",
                            isSelected: vodVM.selectedMovieCategory == nil
                        ) {
                            Task { await vodVM.selectMovieCategory(nil) }
                        }

                        ForEach(vodVM.movieCategories) { cat in
                            categoryChip(
                                title: cat.categoryName,
                                isSelected: vodVM.selectedMovieCategory?.id == cat.id
                            ) {
                                Task { await vodVM.selectMovieCategory(cat) }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    private func categoryChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(isSelected ? Color.blue : Color(nsColor: .controlBackgroundColor))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color.clear : Color.primary.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Movies Grid

    private var movieGrid: some View {
        ScrollView {
            VStack(spacing: 20) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 18)],
                    spacing: 22
                ) {
                    ForEach(Array(vodVM.filteredMovies.prefix(vodVM.displayedMovieLimit)), id: \.compoundID) { movie in
                        MovieCard(movie: movie) {
                            playerVM.playMovie(movie)
                        }
                    }
                }
                .padding(20)

                // Load More Button / Indicator
                if vodVM.displayedMovieLimit < vodVM.filteredMovies.count {
                    Button {
                        vodVM.loadMoreMovies()
                    } label: {
                        HStack(spacing: 8) {
                            Text("Load More Movies")
                            Text("(\(vodVM.displayedMovieLimit) of \(vodVM.filteredMovies.count))")
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - State Overlays

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
            Text("Loading Movies...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Movies Found")
                .font(.title3.bold())

            if !vodVM.movieSearchText.isEmpty {
                Text("Try adjusting your search query.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("Select a category or check your IPTV source.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
