import SwiftUI

// MARK: - Series Card

/// Poster card for TV Series / Shows with hover animations and episode preview.
struct SeriesCard: View {
    let series: Series
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                // Cover Poster
                ZStack(alignment: .bottom) {
                    PosterImageView(url: series.coverURL, fallbackIcon: "tv")
                        .aspectRatio(2/3, contentMode: .fit)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isHovered ? Color.purple.opacity(0.6) : Color.white.opacity(0.1), lineWidth: isHovered ? 2 : 1)
                        )
                        .shadow(color: isHovered ? Color.purple.opacity(0.3) : Color.black.opacity(0.3), radius: isHovered ? 10 : 4, y: isHovered ? 4 : 2)

                    // Top badges
                    VStack {
                        HStack {
                            if let release = series.releaseDate, !release.isEmpty {
                                Text(release.prefix(4))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(4)
                            }

                            Spacer()

                            if let rating = series.rating, rating > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(.yellow)
                                    Text(String(format: "%.1f", rating))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(4)
                            }
                        }
                        .padding(6)

                        Spacer()
                    }

                    // Hover Details Overlay
                    if isHovered {
                        ZStack {
                            Color.black.opacity(0.4)
                            VStack(spacing: 4) {
                                Image(systemName: "list.bullet.circle.fill")
                                    .font(.system(size: 38))
                                    .foregroundColor(.white)
                                Text("Episodes")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                            }
                        }
                        .cornerRadius(10)
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)

                // Title and genre
                VStack(alignment: .leading, spacing: 2) {
                    Text(series.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)

                    if let genre = series.genre, !genre.isEmpty {
                        Text(genre)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else if let cat = series.categoryName, !cat.isEmpty {
                        Text(cat)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(height: 38, alignment: .topLeading)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.18), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
