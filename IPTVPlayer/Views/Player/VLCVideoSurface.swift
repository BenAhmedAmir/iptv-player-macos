import SwiftUI
import VLCKit

// MARK: - VLC Video Surface

/// Hosts the `VLCVideoView` that libVLC renders VOD frames into.
///
/// The engine owns the player and outlives this view, so rebuilding the
/// representable re-points the drawable rather than restarting playback.
struct VLCVideoSurface: NSViewRepresentable {
    let engine: VLCPlaybackEngine

    func makeNSView(context: Context) -> VLCVideoView {
        let view = VLCVideoView()
        view.backColor = .black
        // Letterbox rather than crop, matching AVPlayer's .resizeAspect.
        view.fillScreen = false
        engine.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: VLCVideoView, context: Context) {
        engine.attach(to: nsView)
    }
}
