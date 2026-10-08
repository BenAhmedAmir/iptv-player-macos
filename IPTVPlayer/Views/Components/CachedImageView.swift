import SwiftUI
import AppKit

// MARK: - Cached Image View

/// Async image loader with in-memory and disk caching.
/// Displays a placeholder when loading or on failure.
struct CachedImageView: View {
    let url: URL
    @State private var image: NSImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.5)
            } else {
                Image(systemName: "tv")
                    .foregroundColor(.secondary)
            }
        }
        .task(id: url) {
            isLoading = true
            image = await ImageCacheService.shared.loadImage(from: url)
            isLoading = false
        }
    }
}
