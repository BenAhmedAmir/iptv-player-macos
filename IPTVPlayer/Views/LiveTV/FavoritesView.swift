import SwiftUI

// MARK: - Favorites View

/// Favorited channels, laid out as the design's channel cards.
///
/// The design folds Favorites into Live TV as a pseudo-category; here it stays a
/// separate destination (it already was) but adopts the card treatment used by
/// the Home screen's "Favorites · On Now" row, so the two read as one family.
struct FavoritesView: View {
    @EnvironmentObject var channelVM: ChannelViewModel
    @EnvironmentObject var playerVM: PlayerViewModel

    private var favoriteChannels: [Channel] {
        let query = channelVM.searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let channels = channelVM.favoriteChannels()
        guard !query.isEmpty else { return channels }
        return channels.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        Group {
            if favoriteChannels.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(favoriteChannels, id: \.compoundID) { channel in
                            ChannelTileCard(channel: channel) {
                                channelVM.recordWatch(channel)
                                playerVM.playChannel(channel)
                            } onToggleFavorite: {
                                channelVM.toggleFavorite(channel)
                            }
                        }
                    }
                    .padding(22)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "star")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(Theme.textTertiary)
            Text(channelVM.searchText.isEmpty ? "No favorites yet" : "No favorites match your search")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Text("Star a channel from Live TV to keep it here.")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Channel Card

/// Horizontal channel card: logo tile, category, name.
///
/// The design pairs this with the current programme and its progress; without
/// EPG the category takes the upper line and the progress bar is omitted rather
/// than drawn permanently empty.
struct ChannelTileCard: View {
    let channel: Channel
    let onPlay: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 11) {
                LogoTile(name: channel.name, logoURL: channel.logoURL, size: 40, cornerRadius: 9)

                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.group ?? "Live TV")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                    Text(channel.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button(action: onToggleFavorite) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.star)
                }
                .buttonStyle(.plain)
                .help("Remove from favorites")
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.surfaceRaised))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
