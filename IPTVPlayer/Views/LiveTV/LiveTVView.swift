import SwiftUI

// MARK: - Live TV View

/// Three-column channel browser: categories, channel list, and a detail panel
/// for the highlighted channel.
///
/// The design also specifies a second "Guide" layout — a full EPG grid with a
/// now-line and programme cells. That is not built here because the app has no
/// programme data: EPG was explicitly out of scope for the MVP and `Channel`
/// carries no schedule. Everything the Guide needs (now/next titles, airtimes,
/// progress) would have to be invented.
struct LiveTVView: View {
    @EnvironmentObject var channelVM: ChannelViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var sourcesVM: SourcesViewModel

    @State private var categoryFilter = ""
    @State private var selectedChannelID: String?

    var body: some View {
        HStack(spacing: 0) {
            categoryColumn
            Divider().overlay(Theme.separator)
            channelList
            Divider().overlay(Theme.separator)
            inspector
        }
        .background(Theme.surface)
    }

    // MARK: - Categories

    private var filteredCategories: [String] {
        let query = categoryFilter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return channelVM.categories }
        return channelVM.categories.filter { $0.lowercased().contains(query) }
    }

    private var categoryColumn: some View {
        VStack(spacing: 0) {
            TextField("Filter \(channelVM.categories.count) categories", text: $categoryFilter)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.small).fill(Theme.fill))
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 1) {
                    categoryRow(label: "All Channels", count: channelVM.totalChannelCount, value: nil)
                    ForEach(filteredCategories, id: \.self) { category in
                        categoryRow(
                            label: category,
                            count: channelVM.channelCount(inCategory: category),
                            value: category
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .frame(width: Theme.Metrics.categoryColumnWidth)
    }

    private func categoryRow(label: String, count: Int, value: String?) -> some View {
        let isSelected = channelVM.selectedCategory == value
        return Button {
            channelVM.selectedCategory = value
        } label: {
            HStack(spacing: 8) {
                Text(label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.system(size: 11))
                    .opacity(0.7)
            }
            .font(.system(size: 13))
            .foregroundColor(isSelected ? .white : Theme.textPrimary)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .fill(isSelected ? Theme.accent : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Channel List

    private var selectedChannel: Channel? {
        channelVM.filteredChannels.first { $0.compoundID == selectedChannelID }
            ?? channelVM.filteredChannels.first
    }

    private var channelList: some View {
        Group {
            if channelVM.isLoading {
                ScrollView { ChannelListSkeleton() }
                    .allowsHitTesting(false)
            } else if channelVM.filteredChannels.isEmpty {
                emptyState
            } else {
                // Continuous scrolling: LazyVStack realises only visible rows,
                // so the whole filtered list can be rendered at once.
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(channelVM.filteredChannels.enumerated()), id: \.element.compoundID) { index, channel in
                            channelRow(channel, number: index + 1)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func channelRow(_ channel: Channel, number: Int) -> some View {
        let isSelected = selectedChannel?.compoundID == channel.compoundID
        return HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(Theme.textTertiary)
                .frame(width: 34, alignment: .trailing)

            LogoTile(name: channel.name, logoURL: channel.logoURL, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(channel.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    if channelVM.isFavorite(channel) {
                        Text("★")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.star)
                    }
                }
                // The design shows the current programme here; without EPG the
                // channel's group is the most useful thing we actually know.
                Text(channel.group ?? "Live TV")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(isSelected ? Theme.rowSelected : .clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separatorFaint).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedChannelID = channel.compoundID }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { play(channel) }
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        if !channelVM.searchText.isEmpty {
            EmptyStateView(
                kind: .noSearchResults(query: channelVM.searchText),
                actionTitle: "Clear Search"
            ) {
                channelVM.searchText = ""
            }
        } else if sourcesVM.sources.filter(\.isEnabled).isEmpty {
            EmptyStateView(kind: .noSources)
        } else {
            EmptyStateView(
                kind: .empty(
                    title: "No channels here",
                    message: "This category is empty. Pick another from the list on the left."
                )
            )
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        if let channel = selectedChannel {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        play(channel)
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.Radius.card)
                                .fill(IdentityColor.artwork(for: channel.name))
                            Circle()
                                .fill(Color.black.opacity(0.45))
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white)
                                )
                        }
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay(alignment: .topLeading) {
                            DesignBadge(text: "LIVE").padding(9)
                        }
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 10) {
                        LogoTile(name: channel.name, logoURL: channel.logoURL, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(channel.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                                .lineLimit(2)
                            Text(channel.group ?? "Live TV")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        Button("Watch") { play(channel) }
                            .buttonStyle(DesignPrimaryButtonStyle(horizontalPadding: 0, verticalPadding: 7))
                            .frame(maxWidth: .infinity)

                        Button(channelVM.isFavorite(channel) ? "★ Favorite" : "☆ Favorite") {
                            channelVM.toggleFavorite(channel)
                        }
                        .buttonStyle(DesignSecondaryButtonStyle(horizontalPadding: 0, verticalPadding: 7))
                        .frame(maxWidth: .infinity)
                    }

                    // The design's "ON NOW" and "UP NEXT" blocks need EPG data
                    // the app does not have; the stream's technical details are
                    // shown instead of inventing a schedule.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DETAILS")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.4)
                            .foregroundColor(Theme.textTertiary)

                        detailRow("Category", channel.group ?? "—")
                        if let language = channel.language, !language.isEmpty {
                            detailRow("Language", language)
                        }
                        if let country = channel.country, !country.isEmpty {
                            detailRow("Country", country)
                        }
                        detailRow("Source", sourceName(for: channel))
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .frame(width: Theme.Metrics.inspectorWidth)
            .background(Theme.surfaceInspector)
        } else {
            Color.clear.frame(width: Theme.Metrics.inspectorWidth)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Theme.textTertiary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func sourceName(for channel: Channel) -> String {
        sourcesVM.sources.first { $0.id == channel.sourceID }?.name ?? "Unknown"
    }

    private func play(_ channel: Channel) {
        channelVM.recordWatch(channel)
        // Hand over the list as filtered, so ↑/↓ in the player walks the same
        // channels in the same order the viewer is looking at.
        playerVM.channelLineup = channelVM.filteredChannels
        playerVM.lineupCategory = channelVM.selectedCategory ?? "All Channels"
        playerVM.playChannel(channel)
    }
}

// MARK: - Previews

struct LiveTVView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LiveTVView().previewDisplayName("Live TV — Dark").preferredColorScheme(.dark)
            LiveTVView().previewDisplayName("Live TV — Light").preferredColorScheme(.light)
        }
        .environmentObject(ChannelViewModel())
        .environmentObject(PlayerViewModel())
        .environmentObject(SourcesViewModel())
        .frame(width: 1000, height: 600)
    }
}

struct ChannelListSkeleton_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ChannelListSkeleton()
                .previewDisplayName("Channels loading — Dark")
                .preferredColorScheme(.dark)
            ChannelListSkeleton()
                .previewDisplayName("Channels loading — Light")
                .preferredColorScheme(.light)
        }
        .frame(width: 560, height: 420)
    }
}
