import SwiftUI
import AVKit

// MARK: - App Entry Point

@main
struct IPTVPlayerApp: App {
    @StateObject private var profileVM = ProfileViewModel()
    @StateObject private var sourcesVM = SourcesViewModel()
    @StateObject private var channelVM = ChannelViewModel()
    @StateObject private var vodVM = VODViewModel()
    @StateObject private var playerVM = PlayerViewModel()
    @StateObject private var settingsVM = SettingsViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(profileVM)
                .environmentObject(sourcesVM)
                .environmentObject(channelVM)
                .environmentObject(vodVM)
                .environmentObject(playerVM)
                .environmentObject(settingsVM)
                .preferredColorScheme(colorScheme)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Source...") {
                    sourcesVM.isShowingAddSource = true
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            CommandMenu("Playback") {
                Button("Play / Pause  (Space)") {
                    playerVM.togglePlayPause()
                }
                .disabled(!playerVM.showPlayer)

                Button("Mute / Unmute  (M)") {
                    playerVM.toggleMute()
                }
                .disabled(!playerVM.showPlayer)

                Divider()

                Button("Seek Backward 10s  (←)") {
                    playerVM.skip(by: -10)
                }
                .disabled(!playerVM.showPlayer || !playerVM.canSeek)

                Button("Seek Forward 10s  (→)") {
                    playerVM.skip(by: 10)
                }
                .disabled(!playerVM.showPlayer || !playerVM.canSeek)

                Divider()

                Button("Toggle Fullscreen  (F)") {
                    playerVM.toggleFullscreen()
                }
                .disabled(!playerVM.showPlayer)

                // Only active while fullscreen, so Esc keeps its normal
                // dismiss behaviour for the player sheet otherwise.
                Button("Exit Fullscreen  (Esc)") {
                    playerVM.exitFullscreen()
                }
                .disabled(!playerVM.showPlayer || !playerVM.isFullscreen)

                Divider()

                Button("Picture in Picture  (P)") {
                    playerVM.togglePictureInPicture()
                }
                .disabled(!playerVM.isPictureInPictureAvailable)
            }
        }
    }

    private var colorScheme: ColorScheme? {
        switch settingsVM.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
