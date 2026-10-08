import SwiftUI
import AppKit

// MARK: - Poster Image View

/// Asynchronously loads and renders 2:3 movie/series poster art with caching and fallback.
struct PosterImageView: View {
    let url: URL?
    var fallbackIcon: String = "film"

    @State private var image: NSImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            // Background placeholder
            LinearGradient(
                colors: [Color(nsColor: .controlBackgroundColor), Color(nsColor: .windowBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: fallbackIcon)
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
        }
        .clipped()
        .task(id: url) {
            guard let url = url else {
                image = nil
                isLoading = false
                return
            }

            isLoading = true
            image = await ImageCacheService.shared.loadImage(from: url)
            isLoading = false
        }
    }
}
