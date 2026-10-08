import SwiftUI

// MARK: - Content View

/// Root view that shows profile picker or main navigation.
struct ContentView: View {
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var sourcesVM: SourcesViewModel
    @EnvironmentObject var channelVM: ChannelViewModel
    @EnvironmentObject var vodVM: VODViewModel
    @EnvironmentObject var playerVM: PlayerViewModel

    var body: some View {
        Group {
            if profileVM.isShowingProfilePicker || profileVM.activeProfile == nil {
                ProfileSelectionView()
                    .transition(.opacity)
            } else {
                MainNavigationView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: profileVM.isShowingProfilePicker)
        .animation(.easeInOut(duration: 0.3), value: profileVM.activeProfile?.id)
        .onChange(of: profileVM.activeProfile?.id) { _ in
            loadProfileData()
        }
        .onAppear {
            loadProfileData()
        }
        // The player covers the whole window rather than being a sheet. A sheet is
        // an attached child window, and AppKit refuses to take those fullscreen —
        // toggleFullScreen() on a sheet is a silent no-op. As an overlay it shares
        // the main window, so fullscreen (and the F shortcut) actually work.
        .overlay {
            if playerVM.showPlayer {
                PlayerView()
                    .ignoresSafeArea()
                    .zIndex(1)
                    // Belt and braces: even if this view somehow outlives
                    // showPlayer, it must never absorb clicks meant for the
                    // library underneath.
                    .allowsHitTesting(playerVM.showPlayer)
            }
        }
        // Deliberately no transition or animation on showPlayer. A view caught
        // mid-removal sits at opacity 0 — invisible but still hit-testable —
        // which silently swallowed every click after the player was closed.
        // Hide the window toolbar (profile chip, sidebar toggle, Add Source)
        // while the player is up — it has no bearing on playback and in
        // fullscreen it sat as a bar above the video.
        .toolbar(playerVM.showPlayer ? .hidden : .visible, for: .windowToolbar)
    }

    private func loadProfileData() {
        if let profile = profileVM.activeProfile {
            // Resume positions are per-profile; the player records nothing without this.
            playerVM.activeProfileID = profile.id
            sourcesVM.loadSources(profileID: profile.id)
            // Small delay to ensure sources are loaded from disk before loading channels
            DispatchQueue.main.async {
                Task { await channelVM.loadChannels(profileID: profile.id, sources: sourcesVM.sources) }
                vodVM.loadData(sources: sourcesVM.sources)
            }
        }
    }
}
