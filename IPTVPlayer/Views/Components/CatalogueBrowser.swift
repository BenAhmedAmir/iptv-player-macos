import SwiftUI

// MARK: - Catalogue Browser

/// Shared layout for Movies and TV Shows: category sidebar, content header with
/// filters and sort, and a poster grid.
///
/// Both tabs differ only in their data and their card, so the chrome lives here
/// rather than being written twice and drifting apart.
struct CatalogueBrowser<Item: Identifiable, Card: View>: View {
    @EnvironmentObject var vodVM: VODViewModel

    let tab: CatalogueTab
    let categories: [XtreamCategory]
    let counts: [String: Int]
    let totalCount: Int
    let continueWatchingCount: Int
    let isLoading: Bool
    let searchText: String
    let items: [Item]
    /// TV shows have no added date; the filter row is disabled for them.
    let supportsAddedDate: Bool
    let onClearSearch: () -> Void
    let onOpenSources: () -> Void
    @ViewBuilder let card: (Item) -> Card

    private var preferences: CataloguePreferences { vodVM.preferences(for: tab) }

    private var filtersBinding: Binding<CatalogueFilters> {
        Binding(
            get: { vodVM.preferences(for: tab).filters },
            set: { vodVM.setFilters($0, in: tab) }
        )
    }

    private var sortBinding: Binding<CatalogueSort> {
        Binding(
            get: { vodVM.preferences(for: tab).filters.sort },
            set: { vodVM.setSort($0, in: tab) }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            CategorySidebar(
                tab: tab,
                categories: categories,
                counts: counts,
                totalCount: totalCount,
                continueWatchingCount: continueWatchingCount,
                selection: preferences.selection,
                pinnedIDs: preferences.pinnedCategoryIDs,
                isGroupExpanded: { vodVM.isGroupExpanded($0, in: tab) },
                onSelect: { vodVM.select($0, in: tab) },
                onTogglePin: { vodVM.togglePin(categoryID: $0, in: tab) },
                onToggleGroup: { vodVM.toggleGroup($0, in: tab) }
            )

            Divider().overlay(Theme.separator)

            VStack(spacing: 0) {
                contentHeader
                Divider().overlay(Theme.separator)

                if let error = vodVM.error(for: tab) {
                    ErrorBanner(
                        title: title(for: error),
                        message: message(for: error),
                        actionTitle: isCredentialProblem(error) ? "Open Sources" : nil,
                        action: isCredentialProblem(error) ? { onOpenSources() } : nil,
                        onRetry: { Task { await vodVM.refreshCatalogue(tab) } },
                        onDismiss: { vodVM.clearError(for: tab) },
                        isRetrying: vodVM.isRefreshing(tab)
                    )
                }

                content
            }
            .frame(maxWidth: .infinity)
        }
        .background(Theme.surface)
        .onAppear {
            let groups = Set(categories.map { CategoryNaming.group(of: $0.categoryName) })
            vodVM.seedExpandedGroupIfNeeded(groups: Array(groups), in: tab)
        }
    }

    // MARK: - Header

    private var contentHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(selectionTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                Text(subtitleLine)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            FilterTokenRow(filters: filtersBinding)

            refreshButton

            CatalogueFilterMenu(
                filters: filtersBinding,
                resultCount: items.count,
                supportsAddedDate: supportsAddedDate,
                onReset: { vodVM.resetFilters(in: tab) }
            )

            CatalogueSortMenu(sort: sortBinding)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    /// Count plus how stale the catalogue is, so a missing title has an
    /// obvious next step.
    private var subtitleLine: String {
        let count = "\(items.count) \(items.count == 1 ? "title" : "titles")"
        guard let refreshed = preferences.lastRefreshedAt else { return count }
        return "\(count) · Updated \(refreshed.formatted(.relative(presentation: .named)))"
    }

    private var refreshButton: some View {
        Button {
            Task { await vodVM.refreshCatalogue(tab) }
        } label: {
            Group {
                if vodVM.isRefreshing(tab) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(Theme.textPrimary)
        .disabled(vodVM.isRefreshing(tab))
        .help("Reload categories and titles from your provider (⌘R)")
        .keyboardShortcut("r", modifiers: .command)
    }

    // MARK: - Error Presentation

    private func isCredentialProblem(_ error: IPTVError) -> Bool {
        switch error {
        case .invalidCredentials, .expiredAccount: return true
        default: return false
        }
    }

    /// Headline chosen by cause — "expired" and "unreachable" need different
    /// responses from the viewer.
    private func title(for error: IPTVError) -> String {
        switch error {
        case .expiredAccount: return "Your subscription has expired"
        case .invalidCredentials: return "Your provider rejected the sign-in"
        case .networkUnavailable: return "No internet connection"
        case .timeout: return "Your provider timed out"
        default: return "Couldn’t reach your provider"
        }
    }

    /// Says plainly whether what is on screen is stale or simply absent.
    private func message(for error: IPTVError) -> String {
        let reason = error.localizedDescription
        return items.isEmpty
            ? reason
            : "\(reason) Showing the titles from the last successful update."
    }

    private var selectionTitle: String {
        switch preferences.selection {
        case .all: return tab.allLabel
        case .continueWatching: return "Continue Watching"
        case .recentlyAdded: return "Recently Added"
        case .category(let id):
            return categories.first { $0.categoryID == id }?.categoryName ?? tab.allLabel
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ScrollView { PosterGridSkeleton() }
                .allowsHitTesting(false)
        } else if items.isEmpty {
            emptyState
        } else {
            // Continuous scrolling: LazyVGrid realises only visible rows.
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Theme.Metrics.posterMinWidth), spacing: 16)],
                    spacing: 22
                ) {
                    ForEach(items) { item in
                        card(item)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            EmptyStateView(
                kind: .noSearchResults(query: searchText),
                actionTitle: "Clear Search",
                action: onClearSearch
            )
        } else if preferences.filters.isActive {
            EmptyStateView(
                kind: .empty(
                    title: "No titles match these filters",
                    message: "Nothing in this category passes the filters you have set."
                ),
                actionTitle: "Reset Filters"
            ) {
                vodVM.resetFilters(in: tab)
            }
        } else if categories.isEmpty {
            EmptyStateView(kind: .noSources)
        } else if preferences.selection == .continueWatching {
            EmptyStateView(
                kind: .empty(
                    title: "Nothing in progress",
                    message: "Titles you start but do not finish appear here."
                )
            )
        } else {
            EmptyStateView(
                kind: .empty(
                    title: "Nothing here yet",
                    message: "This category is empty. Pick another from the list on the left."
                )
            )
        }
    }
}

// MARK: - Previews

struct CatalogueBrowserStates_Previews: PreviewProvider {
    private static let categories: [XtreamCategory] = (1...8).map {
        XtreamCategory(
            categoryID: "\($0)",
            categoryName: ["FR | Comedy", "FR | Action", "FR | Drame", "EN | Action",
                           "EN | Sci-Fi", "EN | Horror", "AR | دراما", "Documentaries"][$0 - 1],
            parentID: 0
        )
    }

    /// Sidebar with its filter field populated — the flat "N MATCHES" list.
    private static var sidebarSearching: some View {
        CategorySidebar(
            tab: .movies,
            categories: categories,
            counts: ["1": 128, "2": 340, "4": 512],
            totalCount: 1347,
            continueWatchingCount: 2,
            selection: .all,
            pinnedIDs: ["4"],
            isGroupExpanded: { _ in true },
            onSelect: { _ in }, onTogglePin: { _ in }, onToggleGroup: { _ in }
        )
        .frame(height: 520)
    }

    static var previews: some View {
        Group {
            sidebarSearching
                .previewDisplayName("Sidebar search — Dark")
                .preferredColorScheme(.dark)

            sidebarSearching
                .previewDisplayName("Sidebar search — Light")
                .preferredColorScheme(.light)

            EmptyStateView(
                kind: .empty(
                    title: "No titles match these filters",
                    message: "Nothing in this category passes the filters you have set."
                ),
                actionTitle: "Reset Filters"
            ) {}
            .frame(width: 620, height: 380)
            .background(Theme.surface)
            .previewDisplayName("Empty — filters, Dark")
            .preferredColorScheme(.dark)

            EmptyStateView(
                kind: .noSearchResults(query: "zzz"),
                actionTitle: "Clear Search"
            ) {}
            .frame(width: 620, height: 380)
            .background(Theme.surface)
            .previewDisplayName("Empty — search, Light")
            .preferredColorScheme(.light)
        }
    }
}
