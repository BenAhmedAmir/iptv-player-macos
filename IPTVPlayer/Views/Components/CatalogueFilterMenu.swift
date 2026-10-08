import SwiftUI

// MARK: - Catalogue Filter Menu

/// Rating / year / genre / sort controls for the Movies and TV Shows grids.
///
/// Built from a Button plus a popover rather than a `Menu`: an icon-only menu
/// collapses to zero width in these toolbars, and a popover holds grouped
/// controls far better than a flat menu would.
struct CatalogueFilterMenu<Content: View>: View {
    let isActive: Bool
    let onReset: () -> Void
    @ViewBuilder let content: Content

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isActive
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                Text("Filters")
            }
            .font(.subheadline)
            // Tinted when filters are on, so a surprising result count is
            // traceable to the filter rather than the catalogue.
            .foregroundColor(isActive ? .accentColor : .primary)
        }
        .buttonStyle(.borderless)
        .help("Filter and sort")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                content

                Divider()

                HStack {
                    Button("Reset", action: onReset)
                        .disabled(!isActive)
                    Spacer()
                    Button("Done") { isPresented = false }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(width: 290)
        }
    }
}

// MARK: - Rating Filter

/// Minimum-rating picker, on the provider's 0–10 scale.
struct RatingFilterRow: View {
    @Binding var minimumRating: Double?

    private static let thresholds: [Double] = [5, 6, 7, 8, 9]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Minimum rating", systemImage: "star")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            Picker("", selection: $minimumRating) {
                Text("Any").tag(nil as Double?)
                ForEach(Self.thresholds, id: \.self) { value in
                    Text("\(Int(value))+").tag(value as Double?)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Worth saying: a rating of 0 means "unrated" here, not "awful",
            // and filtering by rating drops those titles entirely.
            if minimumRating != nil {
                Text("Unrated titles are hidden.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Year Filter

struct YearFilterRow: View {
    @Binding var minimumYear: Int?
    let caption: String?

    private static let thresholds: [Int] = [2025, 2020, 2015, 2010, 2000]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Released since", systemImage: "calendar")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            Picker("", selection: $minimumYear) {
                Text("Any").tag(nil as Int?)
                ForEach(Self.thresholds, id: \.self) { year in
                    Text(String(year)).tag(year as Int?)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            if minimumYear != nil, let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
