import SwiftUI
import AVKit
import UniformTypeIdentifiers

// MARK: - Player View

/// Video player with controls, timeline scrubber (for Movies & TV Shows), fullscreen, error handling.
struct PlayerView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var channelVM: ChannelViewModel

    @State private var showControls = true
    @State private var controlsTimer: Task<Void, Never>?
    @State private var mouseMonitor: Any?
    @State private var showAudioPicker = false
    @State private var showSubtitlePicker = false
    @State private var showSpeedPicker = false
    @State private var lastControlsWake = Date.distantPast
    @State private var keyMonitor: Any?
    @State private var subtitleLoadFailure: String?
    @State private var showChannelDrawer = false

    private var speedLabel: String {
        playerVM.playbackSpeed == 1 ? "1×" : "\(playerVM.playbackSpeed.formatted())×"
    }

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            // Live TV renders through AVPlayer; movies and episodes through libVLC,
            // which handles the containers AVFoundation cannot demux.
            switch playerVM.engineKind {
            case .avFoundation:
                // Kept in the hierarchy so AVPlayer decodes frames smoothly.
                NativePlayerView(player: playerVM.player) { layer in
                    playerVM.registerPictureInPicture(layer: layer)
                }
                .ignoresSafeArea()
            case .vlc:
                VLCVideoSurface(engine: playerVM.vlcEngine)
                    .ignoresSafeArea()
            }

            if playerVM.pendingResumeSeconds != nil {
                resumePromptOverlay
            }

            if playerVM.isLoading && !playerVM.hasError {
                loadingOverlay
            }

            if playerVM.hasError {
                errorOverlay
            }

            if controlsVisible {
                controlsOverlay
            }

            if showChannelDrawer && playerVM.canSwitchChannel && controlsVisible {
                HStack(spacing: 0) {
                    Spacer()
                    channelDrawer
                }
                .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        // onHover alone only fires on enter/exit, so once the timer hid the
        // controls, moving the mouse inside the player would not bring them back.
        // onContinuousHover reports every movement, which is what reveals them.
        .onContinuousHover(coordinateSpace: .local) { phase in
            if case .active = phase { wakeControls() }
        }
        .onTapGesture {
            showControls.toggle()
            if showControls {
                resetControlsTimer()
            }
        }
        .onAppear {
            resetControlsTimer()
            startMouseTracking()
            startKeyTracking()
        }
        .onDisappear {
            controlsTimer?.cancel()
            stopMouseTracking()
            stopKeyTracking()
            // An open popover whose anchor disappears can linger as an orphan
            // window and keep swallowing clicks.
            showAudioPicker = false
            showSubtitlePicker = false
            showSpeedPicker = false
        }
    }

    /// Outside fullscreen the controls stay put. Auto-hiding them in a windowed
    /// player left no reliable way to get them back: the video surfaces are
    /// AppKit views (AVPlayerLayer host, VLCVideoView) which swallow mouse-moved
    /// events, so SwiftUI's hover modifiers never fired over them.
    /// Controls auto-hide everywhere after 3s of stillness, and stay up while
    /// paused, erroring, or waiting on the resume prompt.
    private var controlsVisible: Bool {
        guard playerVM.pendingResumeSeconds == nil else { return false }
        guard !playerVM.hasError, !playerVM.isLoading else { return false }
        return showControls || !playerVM.isPlaying
    }

    /// A local event monitor sees mouse movement regardless of which AppKit view
    /// is under the pointer, which is what makes reveal-on-move work in
    /// fullscreen over the video surface.
    private func startMouseTracking() {
        // Replace rather than skip: if the view is rebuilt while a monitor is
        // live, @State may have been reset and the old one would leak. A leaked
        // local monitor runs for the whole app, on every event.
        stopMouseTracking()
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            wakeControls()
            return event
        }
    }

    /// Reveals the controls on pointer movement, cheaply.
    ///
    /// Only fullscreen auto-hides, so everywhere else this returns immediately.
    /// The throttle matters: mouse-moved fires ~100 times a second and this used
    /// to cancel and allocate a Task on every one of them.
    private func wakeControls() {
        if !showControls {
            showControls = true
            NSCursor.unhide()
        }

        let now = Date()
        guard now.timeIntervalSince(lastControlsWake) > 0.5 else { return }
        lastControlsWake = now
        resetControlsTimer()
    }

    private func stopMouseTracking() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        mouseMonitor = nil
    }

    // MARK: - Keyboard

    /// Bare-key shortcuts, scoped to the player.
    ///
    /// These were menu key equivalents, which AppKit matches *before* the
    /// focused responder — so Space/M/F/P and the arrows were swallowed app-wide
    /// and never reached text fields. Typing "film" into search lost its "f" and
    /// "m". A monitor that only lives while the player is on screen cannot do
    /// that, and it still bails out if a text view holds focus.
    private func startKeyTracking() {
        stopKeyTracking()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }

            // Let anything with a modifier through to the normal menu handling.
            let modifiers = event.modifierFlags.intersection([.command, .option, .control])
            guard modifiers.isEmpty else { return event }

            // While the resume prompt is up, nothing is playing yet — leave the
            // keys to its buttons (Return resumes, Esc cancels).
            if playerVM.pendingResumeSeconds != nil {
                if event.keyCode == 53 { playerVM.stop(); return nil }
                return event
            }

            switch event.keyCode {
            case 126:                                           // ↑
                if playerVM.isLive { playerVM.switchChannel(by: -1) } else { return event }
            case 125:                                           // ↓
                if playerVM.isLive { playerVM.switchChannel(by: 1) } else { return event }
            case 49: playerVM.togglePlayPause()                 // space
            case 3:  playerVM.toggleFullscreen()                // f
            case 46: playerVM.toggleMute()                      // m
            case 35: playerVM.togglePictureInPicture()          // p
            case 123: if playerVM.canSeek { playerVM.skip(by: -10) }   // ←
            case 124: if playerVM.canSeek { playerVM.skip(by: 10) }    // →
            case 53:                                            // esc
                if playerVM.isFullscreen { playerVM.exitFullscreen() } else { playerVM.stop() }
            default:
                return event
            }
            return nil  // handled
        }
    }

    private func stopKeyTracking() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = nil
    }

    // MARK: - External Subtitles

    /// Common sidecar subtitle formats. `.srt` and friends have no registered
    /// system type, so these are resolved from their extensions; anything that
    /// does not resolve is simply left out of the filter.
    private static let subtitleExtensions = ["srt", "ass", "ssa", "vtt", "sub", "idx", "smi", "txt"]

    private func loadExternalSubtitle() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Subtitle File"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        let types = Self.subtitleExtensions.compactMap { UTType(filenameExtension: $0) }
        if !types.isEmpty {
            panel.allowedContentTypes = types
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if playerVM.addExternalSubtitle(url) {
            subtitleLoadFailure = nil
        } else {
            subtitleLoadFailure = "Could not load that subtitle file."
        }
    }

    // MARK: - Loading

    private var loadingOverlay: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text(playerVM.isReconnecting
                     ? "Reconnecting… (attempt \(playerVM.reconnectAttempt) of 3)"
                     : "Loading stream...")
                    .font(.headline)
                    .foregroundColor(.white)

                if !playerVM.currentTitle.isEmpty {
                    Text(playerVM.currentTitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }

                if let resumeAt = playerVM.resumedFromSeconds {
                    Label(
                        "Resuming from \(playerVM.formatTime(resumeAt))",
                        systemImage: "arrow.clockwise.circle"
                    )
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                playerVM.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Circle().fill(.black.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .padding(20)
        }
    }

    // MARK: - Resume Prompt

    /// Shown before playback starts when the title has a saved position.
    ///
    /// Presented as a card with the cover art, mirroring the TV-show sheet, so
    /// the viewer recognises what they are about to resume rather than reading a
    /// title on a black screen.
    private var resumePromptOverlay: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            HStack(alignment: .top, spacing: 22) {
                PosterImageView(url: playerVM.pendingResumeArtwork)
                    .frame(width: 150, height: 225)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 6)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Continue watching")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.55))
                        .textCase(.uppercase)

                    Text(playerVM.currentTitle)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if !playerVM.currentSubtitle.isEmpty {
                        Text(playerVM.currentSubtitle)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(2)
                    }

                    if let seconds = playerVM.pendingResumeSeconds {
                        VStack(alignment: .leading, spacing: 6) {
                            // The bar only appears when a runtime was recorded;
                            // some titles never report one.
                            if let progress = playerVM.pendingResumeProgress {
                                ProgressView(value: progress)
                                    .progressViewStyle(.linear)
                                    .tint(.accentColor)
                                    .frame(width: 260)
                            }

                            Text("Continue watching from \(playerVM.formatTime(seconds))?")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.65))
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            playerVM.resumeFromSavedPosition()
                        } label: {
                            Label("Resume", systemImage: "play.fill")
                                .frame(minWidth: 86)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)

                        Button {
                            playerVM.startFromBeginning()
                        } label: {
                            Label("Start Over", systemImage: "backward.end.fill")
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)

                        Button("Cancel") {
                            playerVM.stop()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: 360, alignment: .leading)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(40)
        }
    }

    // MARK: - Error

    private var errorOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(Theme.warning)

            Text("Unable to play stream")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)

            if !playerVM.currentTitle.isEmpty {
                Text(playerVM.currentTitle)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
            }

            Text(playerVM.errorMessage)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button { playerVM.retry() } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(DesignPrimaryButtonStyle(horizontalPadding: 16, verticalPadding: 7))

                // Retrying a dead channel rarely helps; moving on usually does.
                if playerVM.canSwitchChannel {
                    Button { playerVM.playNextChannel() } label: {
                        Label("Try Next Channel", systemImage: "forward.fill")
                    }
                    .buttonStyle(DesignSecondaryButtonStyle(horizontalPadding: 14, verticalPadding: 7))
                }

                Button("Back") { playerVM.stop() }
                    .buttonStyle(DesignSecondaryButtonStyle(horizontalPadding: 14, verticalPadding: 7))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85).ignoresSafeArea())
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        VStack {
            // Top bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(playerVM.currentTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                    if !playerVM.currentSubtitle.isEmpty {
                        Text(playerVM.currentSubtitle)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()

                // Close button
                Button {
                    playerVM.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(.black.opacity(0.5)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            // Bottom controls
            VStack(spacing: 12) {
                // Scrubber for VOD (Movies & Episodes)
                if playerVM.canSeek && playerVM.duration > 0 {
                    HStack(spacing: 12) {
                        Text(playerVM.formattedCurrentTime)
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.white.opacity(0.8))

                        Slider(
                            value: Binding(
                                get: { playerVM.currentTime },
                                set: { newValue in
                                    playerVM.seek(to: newValue)
                                }
                            ),
                            in: 0...max(playerVM.duration, 1),
                            onEditingChanged: { editing in
                                playerVM.isScrubbing = editing
                            }
                        )
                        .tint(.blue)

                        Text(playerVM.formattedDuration)
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 4)
                }

                HStack(spacing: 20) {
                    // Skip backward 10s (for VOD)
                    if !playerVM.isLive {
                        Button {
                            playerVM.skip(by: -10)
                        } label: {
                            Image(systemName: "gobackward.10")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .help("Skip back 10 seconds (Left Arrow)")
                    }

                    // Play/Pause
                    Button {
                        playerVM.togglePlayPause()
                    } label: {
                        Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.space, modifiers: [])

                    // Skip forward 10s (for VOD)
                    if !playerVM.isLive {
                        Button {
                            playerVM.skip(by: 10)
                        } label: {
                            Image(systemName: "goforward.10")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .help("Skip forward 10 seconds (Right Arrow)")
                    }

                    // Volume
                    HStack(spacing: 8) {
                        Button {
                            playerVM.toggleMute()
                        } label: {
                            Image(systemName: playerVM.isMuted ? "speaker.slash.fill" : volumeIcon)
                                .font(.title3)
                                .foregroundColor(.white)
                                .frame(width: 24)
                        }
                        .buttonStyle(.plain)

                        Slider(value: Binding(
                            get: { Double(playerVM.volume) },
                            set: { playerVM.setVolume(Float($0)) }
                        ), in: 0...1)
                        .frame(width: 100)
                        .tint(.white)
                    }

                    Spacer()

                    // Live badge
                    if playerVM.isLive {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("LIVE")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.red.opacity(0.3)))
                    }

                    // Favorite (if live channel)
                    if let channel = playerVM.currentChannel {
                        Button {
                            channelVM.toggleFavorite(channel)
                        } label: {
                            Image(systemName: channelVM.isFavorite(channel) ? "star.fill" : "star")
                                .font(.title3)
                                .foregroundColor(channelVM.isFavorite(channel) ? .yellow : .white)
                        }
                        .buttonStyle(.plain)
                    }

                    // Both menus are always present, dimmed when the file offers no
                    // choice. Hiding them made a working feature look missing: most
                    // titles carry a single audio track and no subtitles, so the
                    // buttons simply never appeared.
                    trackButton(
                        systemImage: "waveform",
                        title: "Audio",
                        help: playerVM.audioTracks.isEmpty
                            ? "No selectable audio tracks in this title"
                            : "Audio track",
                        tracks: playerVM.audioTracks,
                        selectedID: playerVM.currentAudioTrackID,
                        isPresented: $showAudioPicker,
                        onSelect: playerVM.selectAudioTrack
                    )

                    // The subtitle list already carries an explicit "Off" entry.
                    trackButton(
                        systemImage: subtitlesEnabled ? "captions.bubble.fill" : "captions.bubble",
                        title: "Subtitles",
                        help: playerVM.subtitleTracks.isEmpty
                            ? "No subtitles in this title"
                            : "Subtitles",
                        tracks: playerVM.subtitleTracks,
                        selectedID: playerVM.currentSubtitleTrackID,
                        isPresented: $showSubtitlePicker,
                        showsSizeControl: true,
                        onSelect: playerVM.selectSubtitleTrack
                    )

                    // Playback speed (VOD only — meaningless on a live stream)
                    if !playerVM.isLive {
                        Button {
                            showSpeedPicker.toggle()
                        } label: {
                            Text(speedLabel)
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundColor(.white)
                                .frame(minWidth: 34, minHeight: 24)
                        }
                        .buttonStyle(.plain)
                        .help("Playback speed")
                        .popover(isPresented: $showSpeedPicker, arrowEdge: .top) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(PlayerViewModel.availableSpeeds, id: \.self) { speed in
                                    Button {
                                        playerVM.setPlaybackSpeed(speed)
                                        showSpeedPicker = false
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .opacity(speed == playerVM.playbackSpeed ? 1 : 0)
                                            Text(speed == 1 ? "Normal" : "\(speed.formatted())×")
                                            Spacer(minLength: 0)
                                        }
                                        .contentShape(Rectangle())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 8)
                            .frame(width: 150)
                        }
                    }

                    // Channel drawer, live only.
                    if playerVM.canSwitchChannel {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { showChannelDrawer.toggle() }
                        } label: {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.title3)
                                .foregroundColor(showChannelDrawer ? Theme.accent : .white)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help("Channels")
                    }

                    // Picture-in-Picture (live only — libVLC has no PiP equivalent)
                    if playerVM.isPictureInPictureAvailable {
                        Button {
                            playerVM.togglePictureInPicture()
                        } label: {
                            Image(systemName: playerVM.isPictureInPictureActive
                                  ? "pip.exit" : "pip.enter")
                                .font(.title3)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .help("Picture in Picture")
                    }

                    // Fullscreen
                    Button {
                        playerVM.toggleFullscreen()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .help("Fullscreen (F)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: showControls)
    }

    // MARK: - Channel Drawer

    /// Slide-over channel list for live playback.
    ///
    /// The design pairs each row with its current programme; without EPG the
    /// category stands in. ‹ › step through categories, matching the spec.
    private var channelDrawer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { stepCategory(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.small).fill(Theme.fillStrong))
                }
                .buttonStyle(.plain)
                .disabled(drawerCategories.count < 2)

                Text(playerVM.lineupCategory ?? "All Channels")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                Button { stepCategory(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.small).fill(Theme.fillStrong))
                }
                .buttonStyle(.plain)
                .disabled(drawerCategories.count < 2)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.top, 46)
            .padding(.bottom, 12)

            Divider().overlay(Color.white.opacity(0.08))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(playerVM.channelLineup.enumerated()), id: \.element.compoundID) { index, channel in
                        let isCurrent = playerVM.currentChannel?.compoundID == channel.compoundID
                        Button {
                            playerVM.playChannel(channel)
                        } label: {
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundColor(.white.opacity(0.55))
                                    .frame(width: 24, alignment: .trailing)

                                LogoTile(name: channel.name, logoURL: channel.logoURL, size: 34)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(channel.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text(channel.group ?? "Live TV")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.65))
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(isCurrent ? Theme.accent.opacity(0.35) : .clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.08))

            Text("↑ ↓ to switch · ‹ › to change category")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: Theme.Metrics.inspectorWidth)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
        }
    }

    /// Categories available to step through, drawn from the lineup itself.
    private var drawerCategories: [String] {
        var seen = Set<String>()
        return playerVM.channelLineup.compactMap { channel in
            guard let group = channel.group, seen.insert(group).inserted else { return nil }
            return group
        }
    }

    private func stepCategory(_ offset: Int) {
        let categories = drawerCategories
        guard categories.count > 1 else { return }
        let current = categories.firstIndex { $0 == playerVM.lineupCategory } ?? 0
        let next = ((current + offset) % categories.count + categories.count) % categories.count
        playerVM.lineupCategory = categories[next]
    }

    // MARK: - Track Picker

    /// Shared picker for audio and subtitle tracks. Both engines expose tracks as
    /// `MediaTrack`, so this does not need to know which one is playing.
    ///
    /// Built from a plain Button plus a popover rather than a `Menu`: an
    /// icon-only `Menu` with `.menuStyle(.borderlessButton)` collapsed to zero
    /// width in this control bar and drew nothing, while the neighbouring plain
    /// buttons rendered. A popover also suits long lists — some titles carry
    /// fifty subtitle tracks, which is unusable as a flat menu.
    private func trackButton(
        systemImage: String,
        title: String,
        help: String,
        tracks: [MediaTrack],
        selectedID: Int?,
        isPresented: Binding<Bool>,
        showsSizeControl: Bool = false,
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        Button {
            isPresented.wrappedValue.toggle()
        } label: {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundColor(tracks.isEmpty ? .white.opacity(0.35) : .white)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help(help)
        .popover(isPresented: isPresented, arrowEdge: .top) {
            trackList(
                title: title,
                tracks: tracks,
                selectedID: selectedID,
                showsSizeControl: showsSizeControl
            ) { id in
                onSelect(id)
                isPresented.wrappedValue = false
            }
        }
    }

    private func trackList(
        title: String,
        tracks: [MediaTrack],
        selectedID: Int?,
        showsSizeControl: Bool,
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)

            if showsSizeControl {
                // Stays available even with no subtitle tracks: the size applies
                // to whatever plays next, and it is persisted.
                Picker("", selection: Binding(
                    get: { playerVM.subtitleSize },
                    set: { playerVM.setSubtitleSize($0) }
                )) {
                    ForEach(PlayerViewModel.SubtitleSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)

                Text("Text size")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)

                if playerVM.canAddExternalSubtitles {
                    Divider().padding(.vertical, 4)

                    Button {
                        showSubtitlePicker = false
                        loadExternalSubtitle()
                    } label: {
                        Label("Add Subtitle File…", systemImage: "doc.badge.plus")
                            .contentShape(Rectangle())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)

                    if let failure = subtitleLoadFailure {
                        Text(failure)
                            .font(.caption2)
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider().padding(.vertical, 4)
            }

            if tracks.isEmpty {
                Text("None available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(tracks) { track in
                            Button {
                                onSelect(track.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .opacity(track.id == selectedID ? 1 : 0)
                                    Text(track.name)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 8)
                }
                // Tall lists scroll rather than running off the screen.
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 280)
    }

    private var subtitlesEnabled: Bool {
        guard let current = playerVM.currentSubtitleTrackID else { return false }
        return current != MediaTrack.offID
    }

    // MARK: - Helpers

    private var volumeIcon: String {
        if playerVM.volume == 0 { return "speaker.fill" }
        if playerVM.volume < 0.33 { return "speaker.wave.1.fill" }
        if playerVM.volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func resetControlsTimer() {
        controlsTimer?.cancel()
        controlsTimer = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // Only hide while something is actually playing — a paused or
                // errored player keeps its controls.
                guard playerVM.isPlaying, !playerVM.hasError else { return }
                withAnimation { showControls = false }
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }
}

// MARK: - Native AVPlayer Surface (macOS)

/// Hosts an `AVPlayerLayer` for live playback.
///
/// This renders through a layer rather than `AVPlayerView` because
/// `AVPictureInPictureController` requires an `AVPlayerLayer`, and the app drives
/// PiP from its own controls instead of AVPlayerView's built-in control bar.
/// The layer still renders HLS subtitle tracks natively.
struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer
    let onLayerReady: (AVPlayerLayer) -> Void

    final class PlayerLayerHostView: NSView {
        let playerLayer = AVPlayerLayer()

        init(player: AVPlayer) {
            super.init(frame: .zero)
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspect

            // Layer-hosting view: assign the backing layer *before* wantsLayer,
            // which is the order AppKit documents for hosting custom layers.
            let hostLayer = CALayer()
            hostLayer.backgroundColor = NSColor.black.cgColor
            hostLayer.addSublayer(playerLayer)
            self.layer = hostLayer
            self.wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }
    }

    func makeNSView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView(player: player)
        onLayerReady(view.playerLayer)
        return view
    }

    func updateNSView(_ nsView: PlayerLayerHostView, context: Context) {
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
        }
        onLayerReady(nsView.playerLayer)
    }
}

// MARK: - Previews

/// Player states are previewed as their own overlays: the live player needs an
/// AVPlayer and libVLC surface that cannot render in a canvas.
struct PlayerStates_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            errorState
                .previewDisplayName("Player error — Dark")
                .preferredColorScheme(.dark)

            errorState
                .previewDisplayName("Player error — Light")
                .preferredColorScheme(.light)
        }
        .frame(width: 760, height: 460)
    }

    private static var errorState: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(Theme.warning)
            Text("Unable to play stream")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            Text("BBC News HD")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.75))
            Text("The server is currently unavailable. Please try again later.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
            HStack(spacing: 12) {
                Button { } label: { Label("Retry", systemImage: "arrow.clockwise") }
                    .buttonStyle(DesignPrimaryButtonStyle(horizontalPadding: 16, verticalPadding: 7))
                Button { } label: { Label("Try Next Channel", systemImage: "forward.fill") }
                    .buttonStyle(DesignSecondaryButtonStyle(horizontalPadding: 14, verticalPadding: 7))
                Button("Back") { }
                    .buttonStyle(DesignSecondaryButtonStyle(horizontalPadding: 14, verticalPadding: 7))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
    }
}
