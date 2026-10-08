import SwiftUI

// MARK: - Series Detail Sheet

/// Full-featured series modal with backdrop, plot, cast, season picker, and playable episode list.
struct SeriesDetailSheet: View {
    let series: Series
    @EnvironmentObject var vodVM: VODViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Text("Series Details")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    vodVM.closeSeriesDetails()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .padding(6)
                        .background(Circle().fill(Color.secondary.opacity(0.2)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Hero Backdrop & Info
                    heroSection

                    Divider()

                    // Seasons & Episodes
                    episodesSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 720, idealWidth: 840, minHeight: 560, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        HStack(alignment: .top, spacing: 20) {
            // Poster
            PosterImageView(url: series.coverURL, fallbackIcon: "tv")
                .frame(width: 150, height: 225)
                .cornerRadius(12)
                .shadow(radius: 6)

            // Metadata & Plot
            VStack(alignment: .leading, spacing: 10) {
                Text(series.name)
                    .font(.title2.bold())
                    .foregroundColor(.primary)

                // Badges row
                HStack(spacing: 12) {
                    if let rating = series.rating, rating > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", rating))
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    if let year = series.releaseDate, !year.isEmpty {
                        Text(year)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let runtime = series.episodeRunTime, !runtime.isEmpty {
                        Text("\(runtime) min / ep")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let cat = series.categoryName, !cat.isEmpty {
                        Text(cat)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.purple.opacity(0.15)))
                            .foregroundColor(.purple)
                    }
                }

                if let genre = series.genre, !genre.isEmpty {
                    Text(genre)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let plot = series.plot, !plot.isEmpty {
                    Text(plot)
                        .font(.body)
                        .foregroundColor(.primary.opacity(0.9))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let cast = series.cast, !cast.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cast:")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Text(cast)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    // MARK: - Episodes Section

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Episodes")
                    .font(.title3.bold())

                Spacer()

                if vodVM.isLoadingEpisodes {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            // Season Selector
            if !vodVM.availableSeasons.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vodVM.availableSeasons, id: \.self) { seasonNum in
                            Button {
                                vodVM.selectedSeason = seasonNum
                            } label: {
                                Text("Season \(seasonNum)")
                                    .font(.subheadline.weight(vodVM.selectedSeason == seasonNum ? .bold : .regular))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(vodVM.selectedSeason == seasonNum ? Color.purple : Color(nsColor: .controlBackgroundColor))
                                    .foregroundColor(vodVM.selectedSeason == seasonNum ? .white : .primary)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Episodes List
            let currentEpisodes = vodVM.episodesBySeason[vodVM.selectedSeason] ?? []

            if vodVM.isLoadingEpisodes && currentEpisodes.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading episodes...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if currentEpisodes.isEmpty && !vodVM.isLoadingEpisodes {
                Text("No episodes available for this season.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(currentEpisodes) { episode in
                        episodeRow(episode)
                    }
                }
            }
        }
    }

    private func episodeRow(_ episode: Episode) -> some View {
        Button {
            // Episodes carry no artwork of their own, so the show's cover
            // stands in on the resume prompt.
            playerVM.playEpisode(
                episode,
                seriesTitle: series.name,
                seriesArtwork: series.coverURL
            )
        } label: {
            HStack(spacing: 14) {
                // Episode Number
                Text("\(episode.episodeNumber)")
                    .font(.headline.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .center)

                // Episode Title
                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)

                    if let duration = episode.formattedDuration, !duration.isEmpty {
                        Text(duration)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if let secs = episode.durationSecs, secs > 0 {
                        Text("\(secs / 60) min")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Play Button
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.purple)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
