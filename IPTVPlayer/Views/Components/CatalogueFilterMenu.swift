import SwiftUI

// MARK: - Filters Button

/// Toolbar "Filters" control and its popover.
struct CatalogueFilterMenu: View {
    @Binding var filters: CatalogueFilters
    /// Live count for the footer button, recomputed as the sheet is adjusted.
    let resultCount: Int
    /// TV shows carry no added date, so that row is disabled for them.
    let supportsAddedDate: Bool
    let onReset: () -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: filters.isActive
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                Text("Filters")

                if filters.isActive {
                    Text("\(filters.activeCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.textOnAccent)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Circle().fill(Theme.accent))
                }
            }
            .font(.system(size: 13))
            .foregroundColor(filters.isActive ? Theme.accent : Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .fill(filters.isActive ? Theme.accent.opacity(0.14) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Filter titles")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            FilterPopover(
                filters: $filters,
                resultCount: resultCount,
                supportsAddedDate: supportsAddedDate,
                onReset: onReset,
                onClose: { isPresented = false }
            )
        }
    }
}

// MARK: - Filter Popover

struct FilterPopover: View {
    @Binding var filters: CatalogueFilters
    let resultCount: Int
    let supportsAddedDate: Bool
    let onReset: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                label("Minimum rating", icon: "star")
                Picker("", selection: $filters.rating) {
                    ForEach(RatingFilter.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // A missing rating means the provider sent none, not that the
                // title is bad — so filtering on rating removes them entirely.
                if filters.rating != .any {
                    caption("Unrated titles are hidden.")
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                label("Release year", icon: "calendar")
                pillGrid(YearFilter.allCases, selection: $filters.year) { $0.label }
            }

            VStack(alignment: .leading, spacing: 7) {
                label("Date added", icon: "clock.arrow.circlepath")
                pillGrid(AddedFilter.allCases, selection: $filters.added) { $0.label }
                    .disabled(!supportsAddedDate)
                    .opacity(supportsAddedDate ? 1 : 0.45)

                if !supportsAddedDate {
                    caption("This provider does not report when shows were added.")
                }
            }

            Toggle(isOn: $filters.hideWatched) {
                Text("Hide watched")
                    .font(.system(size: 13))
            }
            .toggleStyle(.switch)

            Divider()

            HStack {
                Button("Reset all", action: onReset)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(filters.isActive ? Theme.accent : Theme.textTertiary)
                    .disabled(!filters.isActive)

                Spacer()

                Button("Show \(resultCount) \(resultCount == 1 ? "title" : "titles")") {
                    onClose()
                }
                .buttonStyle(DesignPrimaryButtonStyle(horizontalPadding: 14, verticalPadding: 6))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 320)
    }

    private func label(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Theme.textSecondary)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Wrapping pill row — the year and added options are too many for a
    /// segmented control at this width.
    private func pillGrid<Option: Hashable & Identifiable>(
        _ options: [Option],
        selection: Binding<Option>,
        title: @escaping (Option) -> String
    ) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(options) { option in
                FilterChip(
                    label: title(option),
                    isSelected: selection.wrappedValue == option
                ) {
                    selection.wrappedValue = option
                }
            }
        }
    }
}

// MARK: - Flow Layout

/// Wraps its children onto as many rows as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: totalHeight + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Filter Token

/// Removable capsule summarising one active filter.
struct FilterToken: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(Theme.accent)
        .padding(.leading, 9)
        .padding(.trailing, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.accent.opacity(0.15)))
    }
}

/// Builds the token row from whatever is active.
struct FilterTokenRow: View {
    @Binding var filters: CatalogueFilters

    var body: some View {
        HStack(spacing: 6) {
            if filters.rating != .any {
                FilterToken(label: "★ \(filters.rating.label)") { filters.rating = .any }
            }
            if filters.year != .any {
                FilterToken(label: filters.year.label) { filters.year = .any }
            }
            if filters.added != .any {
                FilterToken(label: "Added: \(filters.added.label)") { filters.added = .any }
            }
            if filters.hideWatched {
                FilterToken(label: "Unwatched") { filters.hideWatched = false }
            }
        }
    }
}

// MARK: - Sort Menu

struct CatalogueSortMenu: View {
    @Binding var sort: CatalogueSort

    var body: some View {
        Menu {
            ForEach(CatalogueSort.allCases) { option in
                Button {
                    sort = option
                } label: {
                    if option == sort {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("Sort: \(sort.label)")
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 13))
            .foregroundColor(Theme.textPrimary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Change sort order")
    }
}

// MARK: - Previews

struct CatalogueFilterMenu_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            FilterPopover(
                filters: .constant(.none),
                resultCount: 1347,
                supportsAddedDate: true,
                onReset: {},
                onClose: {}
            )
            .previewDisplayName("Filter popover — default, Dark")
            .preferredColorScheme(.dark)

            FilterPopover(
                filters: .constant(active),
                resultCount: 42,
                supportsAddedDate: true,
                onReset: {},
                onClose: {}
            )
            .previewDisplayName("Filter popover — active, Light")
            .preferredColorScheme(.light)

            FilterPopover(
                filters: .constant(.none),
                resultCount: 310,
                supportsAddedDate: false,
                onReset: {},
                onClose: {}
            )
            .previewDisplayName("Filter popover — no added date, Dark")
            .preferredColorScheme(.dark)

            HStack(spacing: 8) {
                FilterTokenRow(filters: .constant(active))
                CatalogueSortMenu(sort: .constant(.rating))
            }
            .padding()
            .previewDisplayName("Tokens + sort — Dark")
            .preferredColorScheme(.dark)
        }
    }

    private static var active: CatalogueFilters {
        var filters = CatalogueFilters.none
        filters.rating = .seven
        filters.year = .lastYear
        filters.added = .month
        filters.hideWatched = true
        return filters
    }
}
