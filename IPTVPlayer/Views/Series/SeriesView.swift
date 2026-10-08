import SwiftUI

// MARK: - Series View

/// Displays TV Shows & Series catalog with category filtering, search, and details modal.
struct SeriesView: View {
    @EnvironmentObject var vodVM: VODViewModel
    @EnvironmentObject var playerVM: PlayerViewModel

    @State private var seriesDraft = ""
    @State private var seriesDraftSyncTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Header with search & category selector
            toolbarSection

            Divider()

            // Main Content Area
            if vodVM.isLoadingSeries && vodVM.series.isEmpty {
                loadingView
            } else if vodVM.filteredSeries.isEmpty && !vodVM.isLoadingSeries {
                emptyView
            } else {
                seriesGrid
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $vodVM.selectedSeries) { series in
            SeriesDetailSheet(series: series)
                .environmentObject(vodVM)
                .environmentObject(playerVM)
        }
    }

    // MARK: - Toolbar Section

    private var toolbarSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Category Picker
                Menu {
                    Button("All Categories") {
                        Task { await vodVM.selectSeriesCategory(nil) }
                    }

                    Divider()

                    ForEach(vodVM.seriesCategories) { cat in
                        Button(cat.categoryName) {
                            Task { await vodVM.selectSeriesCategory(cat) }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text(vodVM.selectedSeriesCategory?.categoryName ?? "All Categories")
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
                    TextField("Search TV shows...", text: $seriesDraft)
                        .textFieldStyle(.plain)
                        .onChange(of: seriesDraft) { newValue in
                            seriesDraftSyncTask?.cancel()
                            seriesDraftSyncTask = Task {
                                try? await Task.sleep(nanoseconds: 150_000_000)
                                guard !Task.isCancelled else { return }
                                vodVM.seriesSearchText = newValue
                            }
                        }

                    if !seriesDraft.isEmpty {
                        Button {
                            seriesDraft = ""
                            seriesDraftSyncTask?.cancel()
                            vodVM.seriesSearchText = ""
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
                    isActive: vodVM.seriesFiltersActive,
                    onReset: { vodVM.resetSeriesFilters() }
                ) {
                    RatingFilterRow(minimumRating: $vodVM.seriesMinimumRating)

                    YearFilterRow(
                        minimumYear: $vodVM.seriesMinimumYear,
                        caption: "Shows without a release date are hidden."
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Genre", systemImage: "theatermasks")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Picker("", selection: $vodVM.selectedGenre) {
                            Text("Any genre").tag(nil as String?)
                            ForEach(vodVM.availableGenres, id: \.self) { genre in
                                Text(genre).tag(genre as String?)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Sort by", systemImage: "arrow.up.arrow.down")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Picker("", selection: $vodVM.seriesSortOrder) {
                            ForEach(VODViewModel.SeriesSortOrder.allCases) { order in
                                Text(order.label).tag(order)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }

                Spacer()

                // Series Count
                Text("\(vodVM.filteredSeries.count) Shows")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Refresh Button
                Button {
                    Task {
                        await vodVM.selectSeriesCategory(vodVM.selectedSeriesCategory)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh TV shows")
                .disabled(vodVM.isLoadingSeries)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            // Category Chips
            if !vodVM.seriesCategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        categoryChip(
                            title: "All",
                            isSelected: vodVM.selectedSeriesCategory == nil
                        ) {
                            Task { await vodVM.selectSeriesCategory(nil) }
                        }

                        ForEach(vodVM.seriesCategories) { cat in
                            categoryChip(
                                title: cat.categoryName,
                                isSelected: vodVM.selectedSeriesCategory?.id == cat.id
                            ) {
                                Task { await vodVM.selectSeriesCategory(cat) }
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
                .background(isSelected ? Color.purple : Color(nsColor: .controlBackgroundColor))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color.clear : Color.primary.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Series Grid

    private var seriesGrid: some View {
        ScrollView {
            VStack(spacing: 20) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 18)],
                    spacing: 22
                ) {
                    ForEach(Array(vodVM.filteredSeries.prefix(vodVM.displayedSeriesLimit)), id: \.compoundID) { item in
                        SeriesCard(series: item) {
                            vodVM.openSeriesDetails(item)
                        }
                    }
                }
                .padding(20)

                // Load More Button / Indicator
                if vodVM.displayedSeriesLimit < vodVM.filteredSeries.count {
                    Button {
                        vodVM.loadMoreSeries()
                    } label: {
                        HStack(spacing: 8) {
                            Text("Load More TV Shows")
                            Text("(\(vodVM.displayedSeriesLimit) of \(vodVM.filteredSeries.count))")
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
            Text("Loading TV Shows...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tv.inset.filled")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No TV Shows Found")
                .font(.title3.bold())

            if !vodVM.seriesSearchText.isEmpty {
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
