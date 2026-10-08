import SwiftUI

// MARK: - Movie Card

/// Movie poster card with hover effects, rating tags, and quick-play button.
struct MovieCard: View {
    let movie: Movie
    let onPlay: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 8) {
                // Poster
                ZStack(alignment: .bottom) {
                    PosterImageView(url: movie.posterURL, fallbackIcon: "film")
                        .aspectRatio(2/3, contentMode: .fit)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isHovered ? Color.blue.opacity(0.6) : Color.white.opacity(0.1), lineWidth: isHovered ? 2 : 1)
                        )
                        .shadow(color: isHovered ? Color.blue.opacity(0.3) : Color.black.opacity(0.3), radius: isHovered ? 10 : 4, y: isHovered ? 4 : 2)

                    // Top badges
                    VStack {
                        HStack {
                            if let ext = movie.containerExtension?.uppercased(), !ext.isEmpty {
                                Text(ext)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(4)
                            }

                            Spacer()

                            if let rating = movie.rating, rating > 0 {
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

                    // Hover Play Button Overlay
                    if isHovered {
                        ZStack {
                            Color.black.opacity(0.4)
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 42))
                                .foregroundColor(.white)
                                .shadow(radius: 6)
                        }
                        .cornerRadius(10)
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)

                // Title and category
                VStack(alignment: .leading, spacing: 2) {
                    Text(movie.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)

                    if let cat = movie.categoryName, !cat.isEmpty {
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
