import SwiftUI

// MARK: - Series Detail Sheet

/// Show details: backdrop header, resume action, season picker, episode list.
struct SeriesDetailSheet: View {
    let series: Series

    @EnvironmentObject var vodVM: VODViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isPlotExpanded = false

    private var episodes: [Episode] {
        vodVM.episodesBySeason[vodVM.selectedSeason] ?? []
    }

    private var naming: (badge: String?, title: String) {
        TitleCleaner.series(series.name)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            actionRow
            Divider().overlay(Theme.separator)
            episodeList
        }
        .frame(width: 780, height: 680)
        .background(Theme.surfaceSheet)
    }

    // MARK: - Header

    /// One bottom-anchored stack over the backdrop. Everything that used to be
    /// separate overlays now shares a single column, so nothing can overlap.
    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop

            // Blends the artwork into the sheet and keeps the text legible
            // whatever the image happens to be.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Theme.surfaceSheet.opacity(0.75), location: 0.55),
                    .init(color: Theme.surfaceSheet, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let badge = naming.badge {
                        DesignBadge(text: badge, background: Theme.accent)
                    }
                    Text(naming.title)
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.5)
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(metaLine)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)

                if let plot = series.plot, !plot.isEmpty {
                    plotBlock(plot)
                }

                if let cast = series.cast, !cast.isEmpty {
                    Text("Cast: \(cast)")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(height: 320)
        .clipped()
        .overlay(alignment: .topTrailing) {
            Button {
                vodVM.selectedSeries = nil
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.black.opacity(0.45)))
            }
            .buttonStyle(.plain)
            .padding(14)
        }
    }

    /// Two lines with an inline More/Less toggle.
    private func plotBlock(_ plot: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(plot)
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .lineSpacing(2)
                .lineLimit(isPlotExpanded ? 6 : 2)
                .fixedSize(horizontal: false, vertical: true)

            Button(isPlotExpanded ? "Less" : "More") {
                withAnimation(.easeInOut(duration: 0.15)) { isPlotExpanded.toggle() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Theme.accent)
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        if let url = series.backdropURL ?? series.coverURL {
            PosterImageView(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Rectangle().fill(IdentityColor.artwork(for: series.name))
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let year = series.year { parts.append(String(year)) }
        if let genre = series.genreList.first { parts.append(genre) }
        if !vodVM.availableSeasons.isEmpty {
            let count = vodVM.availableSeasons.count
            parts.append(count == 1 ? "1 season" : "\(count) seasons")
        }
        if let rating = series.normalizedRating {
            parts.append("★ \(String(format: "%.1f", rating))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Action Row

    /// Sits below the backdrop, never over it.
    private var actionRow: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Button(action: playPrimary) {
                    Label(resume.label, systemImage: "play.fill")
                }
                .buttonStyle(DesignPrimaryButtonStyle(horizontalPadding: 16, verticalPadding: 7))
                .disabled(resume.episode == nil)

                if let caption = resume.caption {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
            }

            if resume.isResuming {
                Button("Start Over") {
                    if let episode = resume.episode { play(episode, fromStart: true) }
                }
                .buttonStyle(DesignSecondaryButtonStyle(horizontalPadding: 12, verticalPadding: 7))
            }

            if vodVM.availableSeasons.count > 1 {
                Picker("", selection: $vodVM.selectedSeason) {
                    ForEach(vodVM.availableSeasons, id: \.self) { season in
                        Text("S\(season)").tag(season)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
    }

    // MARK: - Resume Logic

    private struct ResumeTarget {
        let episode: Episode?
        let label: String
        let caption: String?
        let isResuming: Bool
    }

    /// Picks what the primary button should do: continue a part-watched episode,
    /// move on to the one after a finished episode, or start the season.
    private var resume: ResumeTarget {
        guard !episodes.isEmpty else {
            return ResumeTarget(episode: nil, label: "Play", caption: nil, isResuming: false)
        }

        let positions = episodes.map { episode in
            (episode, playerVM.playbackPosition(sourceID: episode.sourceID, itemID: episode.id))
        }

        // In progress wins — that is literally where the viewer stopped.
        if let (episode, position) = positions.first(where: { $0.1?.isResumable == true }),
           let position {
            let remaining = max(0, Int((position.duration - position.seconds) / 60))
            return ResumeTarget(
                episode: episode,
                label: "Resume S\(episode.seasonNumber) · E\(episode.episodeNumber)",
                caption: position.duration > 0 ? "\(remaining) min left" : nil,
                isResuming: true
            )
        }

        // Otherwise continue after the last finished episode.
        if let lastWatchedIndex = positions.lastIndex(where: { $0.1 != nil }) {
            let next = positions.indices.contains(lastWatchedIndex + 1)
                ? positions[lastWatchedIndex + 1].0
                : positions[lastWatchedIndex].0
            return ResumeTarget(
                episode: next,
                label: "Play S\(next.seasonNumber) · E\(next.episodeNumber)",
                caption: nil,
                isResuming: false
            )
        }

        let first = episodes[0]
        return ResumeTarget(
            episode: first,
            label: "Play S\(first.seasonNumber) · E\(first.episodeNumber)",
            caption: nil,
            isResuming: false
        )
    }

    private func playPrimary() {
        guard let episode = resume.episode else { return }
        play(episode, fromStart: false)
    }

    private func play(_ episode: Episode, fromStart: Bool) {
        if fromStart {
            playerVM.clearSavedPosition(sourceID: episode.sourceID, itemID: episode.id)
        }
        playerVM.playEpisode(
            episode,
            seriesTitle: naming.title,
            seriesArtwork: series.coverURL
        )
    }

    // MARK: - Episodes

    @ViewBuilder
    private var episodeList: some View {
        if vodVM.isLoadingEpisodes {
            ScrollView {
                EpisodeListSkeleton()
                    .padding(.top, 4)
            }
            .allowsHitTesting(false)
            .overlay(alignment: .top) {
                Text("Loading episodes…")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.top, 10)
            }
        } else if episodes.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.stack.badge.minus")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(Theme.textTertiary)
                Text("No episodes available for this season.")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(episodes, id: \.compoundID) { episode in
                        EpisodeRow(
                            episode: episode,
                            seriesName: naming.title,
                            fallbackArtwork: series.backdropURL ?? series.coverURL,
                            position: playerVM.playbackPosition(
                                sourceID: episode.sourceID, itemID: episode.id
                            )
                        ) {
                            play(episode, fromStart: false)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Episode Row

struct EpisodeRow: View {
    let episode: Episode
    let seriesName: String
    let fallbackArtwork: URL?
    let position: PlaybackPosition?
    let onPlay: () -> Void

    @State private var isHovered = false

    private var isComplete: Bool {
        guard let position else { return false }
        return !position.isResumable && position.fractionComplete > 0
    }

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 14) {
                Text("\(episode.episodeNumber)")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundColor(Theme.textTertiary)
                    .frame(width: 22, alignment: .trailing)

                thumbnail

                VStack(alignment: .leading, spacing: 3) {
                    Text(TitleCleaner.episode(
                        episode.title,
                        seriesName: seriesName,
                        number: episode.episodeNumber
                    ))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                    if let plot = episode.plot, !plot.isEmpty {
                        Text(plot)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 8)

                Text(TitleCleaner.duration(
                    seconds: episode.durationSecs,
                    fallback: episode.formattedDuration
                ))
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(height: 96)
            .background(isHovered ? Theme.fill : .clear)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.separatorFaint).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    /// Episode still when the provider sends one; otherwise the show's backdrop
    /// blurred behind the episode number, so rows never read as broken images.
    private var thumbnail: some View {
        ZStack(alignment: .bottom) {
            if let url = episode.imageURL {
                PosterImageView(url: url)
            } else if let fallbackArtwork {
                PosterImageView(url: fallbackArtwork)
                    .blur(radius: 6)
                    .overlay(Color.black.opacity(0.35))
                    .overlay(
                        Text("E\(episode.episodeNumber)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                    )
            } else {
                Rectangle()
                    .fill(IdentityColor.artwork(for: episode.title))
                    .overlay(
                        Text("E\(episode.episodeNumber)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                    )
            }

            if let position, position.isResumable, position.duration > 0 {
                WatchProgressBar(
                    fraction: position.fractionComplete,
                    height: 3,
                    tint: Theme.accent,
                    trackColor: Color.black.opacity(0.4)
                )
            }
        }
        .frame(width: 128, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small))
        .overlay(alignment: .topTrailing) {
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white, Theme.accent)
                    .padding(5)
            }
        }
    }
}

// MARK: - Previews

/// Episode rows are previewed directly: the full sheet needs a populated
/// VODViewModel with fetched episodes, which a canvas cannot provide.
struct EpisodeRow_Previews: PreviewProvider {
    private static let sourceID = UUID()

    private static func episode(
        _ number: Int,
        title: String,
        plot: String? = "A routine night turns when an unexpected call comes in.",
        duration: Int? = 4_860,
        image: URL? = nil
    ) -> Episode {
        Episode(
            id: "e\(number)",
            seriesID: "s1",
            sourceID: sourceID,
            seasonNumber: 1,
            episodeNumber: number,
            title: title,
            streamURL: URL(string: "http://example.com/series/\(number).mkv")!,
            containerExtension: "mkv",
            durationSecs: duration,
            formattedDuration: nil,
            plot: plot,
            imageURL: image
        )
    }

    private static func position(seconds: Double, duration: Double) -> PlaybackPosition {
        PlaybackPosition(
            profileID: UUID(),
            sourceID: sourceID,
            itemID: "e2",
            title: "Episode 2",
            seconds: seconds,
            duration: duration,
            updatedAt: Date()
        )
    }

    private static var rows: some View {
        VStack(spacing: 0) {
            // Fresh — never played, no episode still.
            EpisodeRow(
                episode: episode(1, title: "DE | Dark S01E01 The Crossing (2017)"),
                seriesName: "Dark",
                fallbackArtwork: nil,
                position: nil,
                onPlay: {}
            )

            // In progress — progress bar on the thumbnail.
            EpisodeRow(
                episode: episode(2, title: "Dark S01.E02"),
                seriesName: "Dark",
                fallbackArtwork: nil,
                position: position(seconds: 1_500, duration: 4_860),
                onPlay: {}
            )

            // Finished — checkmark, no bar.
            EpisodeRow(
                episode: episode(3, title: "Fault Lines", duration: 2_820),
                seriesName: "Dark",
                fallbackArtwork: nil,
                position: PlaybackPosition(
                    profileID: UUID(), sourceID: sourceID, itemID: "e3",
                    title: "Fault Lines", seconds: 2_800, duration: 2_820, updatedAt: Date()
                ),
                onPlay: {}
            )

            // Long title and plot, and no duration reported.
            EpisodeRow(
                episode: episode(
                    4,
                    title: "An Extremely Long Episode Title That Will Certainly Need Truncating Somewhere",
                    plot: "Everyone wants answers; nobody wants to give them, and the harbour keeps its own counsel while the tide turns against the family once more.",
                    duration: nil
                ),
                seriesName: "Dark",
                fallbackArtwork: nil,
                position: nil,
                onPlay: {}
            )
        }
        .frame(width: 780)
        .background(Theme.surfaceSheet)
    }

    static var previews: some View {
        Group {
            rows.previewDisplayName("Episodes — Dark").preferredColorScheme(.dark)
            rows.previewDisplayName("Episodes — Light").preferredColorScheme(.light)

            EpisodeListSkeleton()
                .frame(width: 780, height: 400)
                .background(Theme.surfaceSheet)
                .previewDisplayName("Episodes loading — Dark")
                .preferredColorScheme(.dark)

            VStack(spacing: 8) {
                Image(systemName: "rectangle.stack.badge.minus")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(Theme.textTertiary)
                Text("No episodes available for this season.")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
            }
            .frame(width: 780, height: 300)
            .background(Theme.surfaceSheet)
            .previewDisplayName("Episodes empty — Light")
            .preferredColorScheme(.light)
        }
    }
}
