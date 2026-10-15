import SwiftUI

// MARK: - Series View

/// TV show catalogue. Mirrors `MoviesView` so the two On Demand screens behave
/// identically; only the data and the card differ.
struct SeriesView: View {
    @EnvironmentObject var vodVM: VODViewModel
    @EnvironmentObject var playerVM: PlayerViewModel

    /// Jumps to Sources so expired credentials can be re-entered.
    var onOpenSources: () -> Void = {}

    var body: some View {
        CatalogueBrowser(
            tab: .series,
            categories: vodVM.seriesCategories,
            counts: vodVM.seriesCategoryCounts,
            totalCount: vodVM.series.count,
            continueWatchingCount: vodVM.continueWatchingCount(in: .series),
            isLoading: vodVM.isLoadingSeries && vodVM.series.isEmpty,
            searchText: vodVM.seriesSearchText,
            items: vodVM.filteredSeries,
            // The Xtream series endpoint reports no added date.
            supportsAddedDate: false,
            onClearSearch: { vodVM.seriesSearchText = "" },
            onOpenSources: { onOpenSources() }
        ) { show in
            PosterCard(
                title: show.name,
                meta: meta(for: show),
                artworkURL: show.coverURL,
                progress: 0
            ) {
                vodVM.openSeriesDetails(show)
            }
        }
        .sheet(item: $vodVM.selectedSeries) { show in
            SeriesDetailSheet(series: show)
                .environmentObject(vodVM)
                .environmentObject(playerVM)
        }
    }

    private func meta(for show: Series) -> String {
        var parts: [String] = []
        if let year = show.year { parts.append(String(year)) }
        if let genre = show.genreList.first { parts.append(genre) }
        if let rating = show.normalizedRating {
            parts.append("★ \(String(format: "%.1f", rating))")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Previews

struct SeriesView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SeriesView().previewDisplayName("TV Shows — Dark").preferredColorScheme(.dark)
            SeriesView().previewDisplayName("TV Shows — Light").preferredColorScheme(.light)
        }
        .environmentObject(VODViewModel())
        .environmentObject(PlayerViewModel())
        .frame(width: 1040, height: 640)
    }
}
