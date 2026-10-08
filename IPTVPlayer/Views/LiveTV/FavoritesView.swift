import SwiftUI

// MARK: - Favorites View

/// Shows favorited channels for the active profile.
struct FavoritesView: View {
    @EnvironmentObject var channelVM: ChannelViewModel
    @EnvironmentObject var playerVM: PlayerViewModel

    var body: some View {
        let favChannels = channelVM.favoriteChannels()

        Group {
            if favChannels.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(favChannels, id: \.compoundID) { channel in
                            ChannelGridItem(
                                channel: channel,
                                isFavorite: true
                            ) {
                                channelVM.recordWatch(channel)
                                playerVM.playChannel(channel)
                            } onFavorite: {
                                channelVM.toggleFavorite(channel)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Favorites")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "star")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No favorites yet")
                .font(.title2.bold())

            Text("Star channels to add them to your favorites.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
