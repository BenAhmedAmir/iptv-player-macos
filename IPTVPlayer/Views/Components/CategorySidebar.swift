import SwiftUI
import AppKit

// MARK: - Category Sidebar

/// Navigable category column for the VOD catalogues.
///
/// A provider ships 200+ categories, which a chip row or a `Picker` cannot
/// present. They are grouped by their namespace prefix ("FR | Comedy" → FR),
/// with pinning, collapse and a filter field that flattens to a match list.
struct CategorySidebar: View {
    let tab: CatalogueTab
    let categories: [XtreamCategory]
    let counts: [String: Int]
    let totalCount: Int
    let continueWatchingCount: Int
    let selection: CategorySelection
    let pinnedIDs: [String]
    let isGroupExpanded: (String) -> Bool

    let onSelect: (CategorySelection) -> Void
    let onTogglePin: (String) -> Void
    let onToggleGroup: (String) -> Void

    @State private var filterText = ""
    @State private var keyMonitor: Any?
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            filterField

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if isFiltering {
                        matchList
                    } else {
                        fixedRows
                        pinnedSection
                        groupedSections
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 240)
        .background(Theme.surfaceInspector)
        .background {
            // ⌘F focuses the filter field without claiming the shortcut globally.
            Button("") { filterFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
        }
        // onKeyPress is macOS 14+; this app targets 13, so arrow handling uses a
        // local monitor that only lives while the sidebar is on screen.
        .onAppear(perform: startKeyMonitor)
        .onDisappear(perform: stopKeyMonitor)
    }

    // MARK: - Filter Field

    private var isFiltering: Bool {
        !filterText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var filterField: some View {
        DesignSearchField(
            placeholder: "Filter \(categories.count) categories",
            text: $filterText,
            width: nil
        )
        .focused($filterFocused)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Rows

    private var fixedRows: some View {
        Group {
            CategoryRow(
                label: tab.allLabel,
                count: totalCount,
                isSelected: selection == .all,
                isPinned: false,
                showsPin: false,
                onSelect: { onSelect(.all) },
                onTogglePin: {}
            )

            CategoryRow(
                label: "Continue Watching",
                count: continueWatchingCount,
                isSelected: selection == .continueWatching,
                isPinned: false,
                showsPin: false,
                onSelect: { onSelect(.continueWatching) },
                onTogglePin: {}
            )

            CategoryRow(
                label: "Recently Added",
                count: nil,
                isSelected: selection == .recentlyAdded,
                isPinned: false,
                showsPin: false,
                onSelect: { onSelect(.recentlyAdded) },
                onTogglePin: {}
            )
        }
    }

    private var pinnedCategories: [XtreamCategory] {
        pinnedIDs.compactMap { id in categories.first { $0.categoryID == id } }
    }

    @ViewBuilder
    private var pinnedSection: some View {
        if !pinnedCategories.isEmpty {
            sectionLabel("PINNED")
            // Pinned rows show the full name: out of their group, "Comedy"
            // alone would not say which language it belongs to.
            ForEach(pinnedCategories, id: \.categoryID) { category in
                categoryRow(category, label: category.categoryName)
            }
        }
    }

    /// Categories bucketed by namespace prefix, groups in size order.
    private var groups: [(name: String, categories: [XtreamCategory])] {
        var buckets: [String: [XtreamCategory]] = [:]
        for category in categories {
            buckets[CategoryNaming.group(of: category.categoryName), default: []].append(category)
        }
        return buckets
            .map { (name: $0.key, categories: $0.value) }
            .sorted {
                $0.categories.count == $1.categories.count
                    ? $0.name < $1.name
                    : $0.categories.count > $1.categories.count
            }
    }

    private var groupedSections: some View {
        ForEach(groups, id: \.name) { group in
            let expanded = isGroupExpanded(group.name)

            Button {
                onToggleGroup(group.name)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Theme.textTertiary)
                        .frame(width: 10)
                    Text(group.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(group.categories.count)")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.horizontal, 9)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(group.categories, id: \.categoryID) { category in
                    categoryRow(category, label: CategoryNaming.label(of: category.categoryName))
                }
            }
        }
    }

    /// Flat result list while filtering — groups are irrelevant to a search.
    private var matchList: some View {
        let query = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        let matches = categories.filter { $0.categoryName.lowercased().contains(query) }

        return Group {
            sectionLabel("\(matches.count) MATCHES")
            ForEach(matches, id: \.categoryID) { category in
                categoryRow(category, label: category.categoryName)
            }
            if matches.isEmpty {
                Text("No categories match “\(filterText)”.")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 10)
            }
        }
    }

    private func categoryRow(_ category: XtreamCategory, label: String) -> some View {
        CategoryRow(
            label: label,
            count: counts[category.categoryID],
            isSelected: selection == .category(id: category.categoryID),
            isPinned: pinnedIDs.contains(category.categoryID),
            showsPin: true,
            onSelect: { onSelect(.category(id: category.categoryID)) },
            onTogglePin: { onTogglePin(category.categoryID) }
        )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Theme.textTertiary)
            .padding(.horizontal, 9)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Keyboard

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Never steal arrows from the filter field or any other text entry.
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
                return event
            }
            switch event.keyCode {
            case 126: moveSelection(-1); return nil
            case 125: moveSelection(1); return nil
            default: return event
            }
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// ↑/↓ walk the visible rows, including the fixed ones.
    private func moveSelection(_ offset: Int) {
        let order: [CategorySelection] = [.all, .continueWatching, .recentlyAdded]
            + visibleCategoryIDs.map { .category(id: $0) }

        guard let index = order.firstIndex(of: selection) else {
            onSelect(order.first ?? .all)
            return
        }
        let next = max(0, min(order.count - 1, index + offset))
        onSelect(order[next])
    }

    private var visibleCategoryIDs: [String] {
        if isFiltering {
            let query = filterText.trimmingCharacters(in: .whitespaces).lowercased()
            return categories
                .filter { $0.categoryName.lowercased().contains(query) }
                .map(\.categoryID)
        }
        return pinnedIDs + groups
            .filter { isGroupExpanded($0.name) }
            .flatMap { $0.categories.map(\.categoryID) }
    }
}

// MARK: - Category Row

struct CategoryRow: View {
    let label: String
    let count: Int?
    let isSelected: Bool
    let isPinned: Bool
    let showsPin: Bool
    let onSelect: () -> Void
    let onTogglePin: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .white : Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if let count {
                    Text("\(count)")
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : Theme.textTertiary)
                }

                // Pin stays hidden until hover unless it is already set, so the
                // column is not a field of stars.
                if showsPin && (isHovered || isPinned) {
                    Button(action: onTogglePin) {
                        Image(systemName: isPinned ? "star.fill" : "star")
                            .font(.system(size: 10))
                            .foregroundColor(isPinned ? Theme.star : (isSelected ? .white : Theme.textTertiary))
                    }
                    .buttonStyle(.plain)
                    .help(isPinned ? "Unpin category" : "Pin category")
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .fill(isSelected ? Theme.accent : (isHovered ? Theme.fill : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Previews

struct CategorySidebar_Previews: PreviewProvider {
    private static let categories: [XtreamCategory] = [
        .init(categoryID: "1", categoryName: "FR | Comedy", parentID: 0),
        .init(categoryID: "2", categoryName: "FR | Action", parentID: 0),
        .init(categoryID: "3", categoryName: "FR | Drame", parentID: 0),
        .init(categoryID: "4", categoryName: "EN | Action", parentID: 0),
        .init(categoryID: "5", categoryName: "EN | Sci-Fi", parentID: 0),
        .init(categoryID: "6", categoryName: "Documentaries", parentID: 0)
    ]

    private static func sidebar(selection: CategorySelection, pinned: [String]) -> some View {
        CategorySidebar(
            tab: .movies,
            categories: categories,
            counts: ["1": 128, "2": 340, "3": 92, "4": 512, "5": 211, "6": 64],
            totalCount: 1347,
            continueWatchingCount: 3,
            selection: selection,
            pinnedIDs: pinned,
            isGroupExpanded: { $0 == "FR" },
            onSelect: { _ in },
            onTogglePin: { _ in },
            onToggleGroup: { _ in }
        )
        .frame(height: 520)
    }

    static var previews: some View {
        Group {
            sidebar(selection: .all, pinned: ["4"])
                .previewDisplayName("Sidebar — Dark")
                .preferredColorScheme(.dark)

            sidebar(selection: .category(id: "2"), pinned: ["4"])
                .previewDisplayName("Sidebar — selected, Light")
                .preferredColorScheme(.light)
        }
    }
}
