import SwiftUI

// MARK: - Movies View

/// Movie catalogue: category sidebar beside a filtered poster grid.
struct MoviesView: View {
    @EnvironmentObject var vodVM: VODViewModel
    @EnvironmentObject var playerVM: PlayerViewModel

    /// Jumps to Sources so expired credentials can be re-entered.
    var onOpenSources: () -> Void = {}

    var body: some View {
        CatalogueBrowser(
            tab: .movies,
            categories: vodVM.movieCategories,
            counts: vodVM.movieCategoryCounts,
            totalCount: vodVM.movies.count,
            continueWatchingCount: vodVM.continueWatchingCount(in: .movies),
            isLoading: vodVM.isLoadingMovies && vodVM.movies.isEmpty,
            searchText: vodVM.movieSearchText,
            items: vodVM.filteredMovies,
            supportsAddedDate: true,
            onClearSearch: { vodVM.movieSearchText = "" },
            onOpenSources: { onOpenSources() }
        ) { movie in
            PosterCard(
                title: movie.name,
                meta: meta(for: movie),
                artworkURL: movie.posterURL,
                progress: playerVM.savedProgress(sourceID: movie.sourceID, itemID: movie.id) ?? 0
            ) {
                playerVM.playMovie(movie)
            }
        }
    }

    private func meta(for movie: Movie) -> String {
        var parts: [String] = []
        if let year = movie.year { parts.append(String(year)) }
        if let rating = movie.normalizedRating {
            parts.append("★ \(String(format: "%.1f", rating))")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Previews

struct MoviesView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MoviesView().previewDisplayName("Movies — Dark").preferredColorScheme(.dark)
            MoviesView().previewDisplayName("Movies — Light").preferredColorScheme(.light)
        }
        .environmentObject(VODViewModel())
        .environmentObject(PlayerViewModel())
        .frame(width: 1040, height: 640)
    }
}
