import Foundation

// MARK: - Catalogue Item

/// The shape the catalogue pipeline needs, so Movies and TV Shows share one
/// filter and sort implementation instead of two that drift apart.
protocol CatalogueItem {
    var catalogueKey: String { get }
    var catalogueSourceID: UUID { get }
    var catalogueItemID: String { get }
    var catalogueTitle: String { get }
    var catalogueYear: Int? { get }
    var catalogueRating: Double? { get }
    /// Nil when the provider does not report one — TV shows never do.
    var catalogueAddedDate: Date? { get }
    var catalogueCategoryID: String? { get }
}

extension Movie: CatalogueItem {
    var catalogueKey: String { compoundID }
    var catalogueSourceID: UUID { sourceID }
    var catalogueItemID: String { id }
    var catalogueTitle: String { name }
    var catalogueYear: Int? { year }
    var catalogueRating: Double? { normalizedRating }
    var catalogueAddedDate: Date? { addedDate }
    var catalogueCategoryID: String? { categoryID }
}

extension Series: CatalogueItem {
    var catalogueKey: String { compoundID }
    var catalogueSourceID: UUID { sourceID }
    var catalogueItemID: String { id }
    var catalogueTitle: String { name }
    var catalogueYear: Int? { year }
    var catalogueRating: Double? { normalizedRating }
    /// The Xtream series endpoint reports no added date.
    var catalogueAddedDate: Date? { nil }
    var catalogueCategoryID: String? { categoryID }
}

// MARK: - Filtering

/// Pure filter + sort, callable off the main actor.
enum CatalogueFiltering {

    /// Playback keys, precomputed so the filter does not re-scan positions per item.
    struct WatchState {
        /// Items with any saved position — started or finished.
        let watchedKeys: Set<String>
        /// Items with a resumable position, used by Continue Watching.
        let inProgressKeys: Set<String>

        static let empty = WatchState(watchedKeys: [], inProgressKeys: [])

        static func make(from positions: [PlaybackPosition]) -> WatchState {
            var watched = Set<String>()
            var inProgress = Set<String>()
            for position in positions {
                let key = "\(position.sourceID.uuidString)_\(position.itemID)"
                watched.insert(key)
                if position.isResumable { inProgress.insert(key) }
            }
            return WatchState(watchedKeys: watched, inProgressKeys: inProgress)
        }
    }

    /// Applies selection, search and filters, then sorts.
    ///
    /// Every predicate is ANDed; an item must satisfy the category, the search
    /// and each active filter.
    static func apply<Item: CatalogueItem>(
        to items: [Item],
        selection: CategorySelection,
        search: String,
        filters: CatalogueFilters,
        watch: WatchState
    ) -> [Item] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ratingThreshold = filters.rating.threshold
        let yearRange = filters.year.range
        let addedCutoff = filters.added.cutoff

        var result = items.filter { item in
            // Category / virtual row
            switch selection {
            case .all, .recentlyAdded:
                break
            case .continueWatching:
                guard watch.inProgressKeys.contains(item.catalogueKey) else { return false }
            case .category(let id):
                guard item.catalogueCategoryID == id else { return false }
            }

            if !query.isEmpty, !item.catalogueTitle.lowercased().contains(query) {
                return false
            }

            // Unrated titles are dropped rather than treated as zero — a missing
            // rating means the provider sent none, not that the title is bad.
            if let ratingThreshold {
                guard let rating = item.catalogueRating, rating >= ratingThreshold else { return false }
            }

            if let yearRange {
                guard let year = item.catalogueYear, yearRange.contains(year) else { return false }
            }

            if let addedCutoff {
                guard let added = item.catalogueAddedDate, added >= addedCutoff else { return false }
            }

            if filters.hideWatched, watch.watchedKeys.contains(item.catalogueKey) {
                return false
            }

            return true
        }

        // "Recently Added" is a sort as much as a selection.
        let sort = selection == .recentlyAdded ? .dateAdded : filters.sort
        result = self.sort(result, by: sort)
        return result
    }

    static func sort<Item: CatalogueItem>(_ items: [Item], by order: CatalogueSort) -> [Item] {
        switch order {
        case .dateAdded:
            // Falls back to year for catalogues with no added dates (TV shows),
            // so the default order is still meaningful there.
            guard items.contains(where: { $0.catalogueAddedDate != nil }) else {
                return sort(items, by: .releaseYear)
            }
            return items.sorted {
                ($0.catalogueAddedDate ?? .distantPast) > ($1.catalogueAddedDate ?? .distantPast)
            }
        case .titleAscending:
            return items.sorted {
                $0.catalogueTitle.localizedCaseInsensitiveCompare($1.catalogueTitle) == .orderedAscending
            }
        case .releaseYear:
            return items.sorted { ($0.catalogueYear ?? Int.min) > ($1.catalogueYear ?? Int.min) }
        case .rating:
            return items.sorted { ($0.catalogueRating ?? -1) > ($1.catalogueRating ?? -1) }
        }
    }

    /// Item tally per category id, for the sidebar counts.
    static func counts<Item: CatalogueItem>(for items: [Item]) -> [String: Int] {
        items.reduce(into: [String: Int]()) { totals, item in
            guard let id = item.catalogueCategoryID else { return }
            totals[id, default: 0] += 1
        }
    }
}
