import SwiftUI

// MARK: - Logo Tile

/// Rounded square showing a channel's logo, falling back to its initials on a
/// colour derived from the name — the design never leaves an empty square.
struct LogoTile: View {
    let name: String
    let logoURL: URL?
    var size: CGFloat = 38
    var cornerRadius: CGFloat = Theme.Radius.tile

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(IdentityColor.tile(for: name))

            if let logoURL {
                CachedImageView(url: logoURL)
                    .padding(size * 0.12)
            } else {
                Text(IdentityColor.initials(for: name))
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Progress Bar

/// Thin watch-progress bar. Hidden entirely at zero rather than drawn empty,
/// which is how the design distinguishes "unwatched" from "just started".
struct WatchProgressBar: View {
    let fraction: Double
    var height: CGFloat = 3
    var tint: Color = Theme.accent
    var trackColor: Color = Theme.track

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Badge

/// Small uppercase tag — LIVE, MOVIE, EPISODE.
struct DesignBadge: View {
    let text: String
    var background: Color = Theme.live
    var foreground: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .foregroundColor(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(background))
    }
}

// MARK: - Filter Chip

/// Pill used for genre and category filters.
struct FilterChip: View {
    let label: String
    var count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                if let count {
                    Text("\(count)")
                        .opacity(0.65)
                }
            }
            .font(.system(size: 12))
            .foregroundColor(isSelected ? Theme.surface : Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isSelected ? Theme.textPrimary : Theme.fill)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search Field

/// Header search box: magnifier, borderless field, clear button.
struct DesignSearchField: View {
    let placeholder: String
    @Binding var text: String
    var width: CGFloat? = Theme.Metrics.searchWidth

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textTertiary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(Theme.textPrimary)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(width: width, height: Theme.Metrics.fieldHeight)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.field).fill(Theme.fill))
    }
}

// MARK: - Buttons

/// Filled blue action button.
struct DesignPrimaryButtonStyle: ButtonStyle {
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 5

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Theme.textOnAccent)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .fill(Theme.accent.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .contentShape(Rectangle())
    }
}

/// Translucent neutral button.
struct DesignSecondaryButtonStyle: ButtonStyle {
    var horizontalPadding: CGFloat = 11
    var verticalPadding: CGFloat = 5

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundColor(Theme.textPrimary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .fill(Theme.fillStrong.opacity(configuration.isPressed ? 0.5 : 1))
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Section Heading

/// "Continue Watching" style heading, optionally with a trailing link.
struct SectionHeading: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.textPrimary)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.accent)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Hover Highlight

/// Applies the design's hover fill to rows and cards.
struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.card
    var color: Color = Theme.surfaceHover
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? color : .clear)
            )
            .onHover { isHovered = $0 }
    }
}

extension View {
    func hoverHighlight(
        cornerRadius: CGFloat = Theme.Radius.card,
        color: Color = Theme.surfaceHover
    ) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, color: color))
    }
}

// MARK: - Skeletons

/// Shimmering placeholder block.
///
/// Browsing screens show these rather than a lone spinner: the layout is known
/// before the data is, so the page can hold its shape while it loads.
struct SkeletonBlock: View {
    var cornerRadius: CGFloat = Theme.Radius.tile
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.skeleton)
            .opacity(shimmer ? 0.55 : 1)
            .animation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: shimmer
            )
            .onAppear { shimmer = true }
    }
}

/// Poster-grid placeholder, matching the real grid's geometry.
struct PosterGridSkeleton: View {
    var count: Int = 14

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: Theme.Metrics.posterMinWidth), spacing: 16)],
            spacing: 22
        ) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 7) {
                    SkeletonBlock()
                        .aspectRatio(2 / 3, contentMode: .fit)
                    SkeletonBlock(cornerRadius: 4)
                        .frame(height: 11)
                        .padding(.trailing, 24)
                    SkeletonBlock(cornerRadius: 4)
                        .frame(height: 9)
                        .padding(.trailing, 60)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }
}

/// Channel-list placeholder rows.
struct ChannelListSkeleton: View {
    var count: Int = 12

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 12) {
                    SkeletonBlock(cornerRadius: 4)
                        .frame(width: 18, height: 11)
                    SkeletonBlock()
                        .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBlock(cornerRadius: 4)
                            .frame(width: 160, height: 11)
                        SkeletonBlock(cornerRadius: 4)
                            .frame(width: 100, height: 9)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }
        }
    }
}

/// Episode-row placeholder for the series sheet.
struct EpisodeListSkeleton: View {
    var count: Int = 5

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 14) {
                    SkeletonBlock(cornerRadius: 4)
                        .frame(width: 16, height: 11)
                    SkeletonBlock(cornerRadius: Theme.Radius.small)
                        .frame(width: 120, height: 68)
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBlock(cornerRadius: 4)
                            .frame(width: 180, height: 11)
                        SkeletonBlock(cornerRadius: 4)
                            .frame(height: 9)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
    }
}

// MARK: - Empty States

/// Shared empty state so every browsing screen explains itself the same way.
struct EmptyStateView: View {
    enum Kind {
        /// Nothing is configured yet.
        case noSources
        /// Filters are hiding everything.
        case filtersActive
        /// A search returned nothing.
        case noSearchResults(query: String)
        /// Genuinely empty.
        case empty(title: String, message: String)
    }

    let kind: Kind
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundColor(Theme.textTertiary)
                .padding(.bottom, 2)

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.textPrimary)

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(DesignPrimaryButtonStyle(horizontalPadding: 16, verticalPadding: 7))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var icon: String {
        switch kind {
        case .noSources: return "antenna.radiowaves.left.and.right"
        case .filtersActive: return "line.3.horizontal.decrease.circle"
        case .noSearchResults: return "magnifyingglass"
        case .empty: return "tray"
        }
    }

    private var title: String {
        switch kind {
        case .noSources: return "No sources yet"
        case .filtersActive: return "No results — filters are active"
        case .noSearchResults: return "No matches"
        case .empty(let title, _): return title
        }
    }

    private var message: String {
        switch kind {
        case .noSources:
            return "Add an M3U playlist or Xtream Codes login to start browsing."
        case .filtersActive:
            return "Nothing matches the current filters. Reset them to see everything again."
        case .noSearchResults(let query):
            return "Nothing matches “\(query)”. Try a shorter search, or clear it."
        case .empty(_, let message):
            return message
        }
    }
}

// MARK: - Error Banner

/// Inline failure notice for a screen whose content could not be refreshed.
///
/// A banner rather than an alert: the stale content underneath is still usable,
/// and a modal would have to be dismissed before the viewer could read it.
struct ErrorBanner: View {
    let title: String
    let message: String
    /// Shown when the cause is something the viewer can act on, such as
    /// credentials that need re-entering.
    var actionTitle: String?
    var action: (() -> Void)?
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?
    var isRetrying: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundColor(Theme.warning)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(DesignSecondaryButtonStyle())
            }

            if let onRetry {
                Button(action: onRetry) {
                    if isRetrying {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Retry")
                    }
                }
                .buttonStyle(DesignPrimaryButtonStyle())
                .disabled(isRetrying)
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Theme.warning.opacity(0.12))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.warning.opacity(0.3)).frame(height: 1)
        }
    }
}

// MARK: - Previews

struct ErrorBanner_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            VStack(spacing: 0) {
                ErrorBanner(
                    title: "Couldn’t reach your provider",
                    message: "The server is currently unavailable. Showing the last titles that loaded.",
                    onRetry: {},
                    onDismiss: {}
                )
                ErrorBanner(
                    title: "Your subscription has expired",
                    message: "Your account has expired. Please contact your provider.",
                    actionTitle: "Open Sources",
                    action: {},
                    onRetry: {}
                )
                ErrorBanner(
                    title: "Couldn’t reach your provider",
                    message: "The request timed out.",
                    onRetry: {},
                    isRetrying: true
                )
            }
            .frame(width: 760)
            .previewDisplayName("Error banners — Dark")
            .preferredColorScheme(.dark)

            ErrorBanner(
                title: "Couldn’t reach your provider",
                message: "The server is currently unavailable. Showing the last titles that loaded.",
                onRetry: {},
                onDismiss: {}
            )
            .frame(width: 760)
            .previewDisplayName("Error banner — Light")
            .preferredColorScheme(.light)
        }
    }
}
