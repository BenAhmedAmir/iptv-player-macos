import Foundation
import AVKit
import SwiftUI
import Combine

// MARK: - Player View Model

/// Manages AVPlayer lifecycle, playback state, seeking, and error handling for Channels, Movies, and Episodes.
@MainActor
final class PlayerViewModel: NSObject, ObservableObject {
    @Published var currentChannel: Channel?
    @Published var currentMovie: Movie?
    @Published var currentEpisode: Episode?
    @Published var currentTitle: String = ""
    @Published var currentSubtitle: String = ""
    @Published var currentLogoURL: URL? = nil
    @Published var isLive: Bool = true

    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var isMuted = false
    @Published var volume: Float = 1.0
    @Published var hasError = false
    @Published var errorMessage = ""
    @Published var isFullscreen = false

    @Published var showPlayer = false

    // Seeking & scrubber state (for Movies and Episodes)
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isScrubbing: Bool = false

    // Track selection — populated once the engine has parsed the stream.
    @Published var audioTracks: [MediaTrack] = []
    @Published var subtitleTracks: [MediaTrack] = []
    @Published var currentAudioTrackID: Int?
    @Published var currentSubtitleTrackID: Int?

    // Automatic reconnection
    @Published var isReconnecting = false
    @Published private(set) var reconnectAttempt = 0
    private let maxReconnectAttempts = 3
    private var reconnectTask: Task<Void, Never>?
    /// Offset to restore after a reconnect, so VOD resumes where it dropped.
    private var resumePosition: Double = 0

    // Picture-in-Picture (AVPlayer path only; libVLC has no PiP equivalent)
    @Published private(set) var isPictureInPictureActive = false
    @Published private(set) var isPictureInPicturePossible = false
    private var pipController: AVPictureInPictureController?
    private var pipPossibleObservation: NSKeyValueObservation?

    /// AVFoundation media selection, cached so menu ids map back to options.
    private var avAudibleGroup: AVMediaSelectionGroup?
    private var avLegibleGroup: AVMediaSelectionGroup?
    private var avAudibleOptions: [AVMediaSelectionOption] = []
    private var avLegibleOptions: [AVMediaSelectionOption] = []

    /// Which backend is driving the current item. Live TV uses AVPlayer for
    /// hardware-decoded HLS and Picture-in-Picture; movies and episodes use
    /// libVLC, because AVFoundation cannot demux the Matroska/AVI containers that
    /// make up roughly half of a typical Xtream VOD catalogue.
    enum EngineKind {
        case avFoundation
        case vlc
    }

    @Published private(set) var engineKind: EngineKind = .avFoundation

    let player = AVPlayer()

    /// Created on first VOD playback so live-only sessions never initialise libVLC.
    private var _vlcEngine: VLCPlaybackEngine?
    var vlcEngine: VLCPlaybackEngine {
        if let existing = _vlcEngine { return existing }
        let engine = VLCPlaybackEngine(userAgent: iptvUserAgent)
        engine.onStateChange = { [weak self] state in
            self?.handleVLCState(state)
        }
        engine.onTracksChanged = { [weak self] in
            self?.refreshVLCTracks()
        }
        engine.onTimeChange = { [weak self] current, duration in
            guard let self else { return }

            // Frames are flowing, so the loading overlay must come down even if the
            // state transition that normally clears it never arrived.
            if current > 0 && self.isLoading {
                self.vlcTimeoutTask?.cancel()
                self.isLoading = false
                self.isPlaying = true
            }

            guard !self.isScrubbing else { return }
            self.currentTime = current
            if duration > 0 { self.duration = duration }
            self.recordPosition()
        }
        _vlcEngine = engine
        return engine
    }

    private var vlcTimeoutTask: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var errorObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var itemFailedNotification: NSObjectProtocol?
    private var itemStalledNotification: NSObjectProtocol?
    private var enterFullscreenNotification: NSObjectProtocol?
    private var exitFullscreenNotification: NSObjectProtocol?
    private var timeObserverToken: Any?

    override init() {
        super.init()
        setupObservers()
        observeFullscreenChanges()
    }

    deinit {
        player.pause()
        statusObservation?.invalidate()
        errorObservation?.invalidate()
        timeControlObservation?.invalidate()
        pipPossibleObservation?.invalidate()
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        if let notif = itemFailedNotification {
            NotificationCenter.default.removeObserver(notif)
        }
        if let notif = itemStalledNotification {
            NotificationCenter.default.removeObserver(notif)
        }
        if let notif = enterFullscreenNotification {
            NotificationCenter.default.removeObserver(notif)
        }
        if let notif = exitFullscreenNotification {
            NotificationCenter.default.removeObserver(notif)
        }
    }

    // IPTV User-Agent accepted by IPTV servers and Cloudflare
    private let iptvUserAgent = "IPTVSmartersPlayer"

    // MARK: - Play Live Channel

    func playChannel(_ channel: Channel) {
        teardownVLC()
        engineKind = .avFoundation
        clearTracks()

        currentChannel = channel
        currentMovie = nil
        currentEpisode = nil
        currentTitle = channel.name
        currentSubtitle = channel.group ?? "Live TV"
        currentLogoURL = channel.logoURL
        isLive = true
        currentTime = 0
        duration = 0

        showPlayer = true
        hasError = false
        errorMessage = ""
        isLoading = true

        let primaryURL = resolvePlaybackURL(for: channel.streamURL)
        loadStream(url: primaryURL, fallbackURL: channel.streamURL != primaryURL ? channel.streamURL : nil, title: channel.name, isLive: true)
    }

    // MARK: - Play Movie (VOD)

    func playMovie(_ movie: Movie) {
        currentChannel = nil
        currentMovie = movie
        currentEpisode = nil
        currentTitle = movie.name
        currentSubtitle = movie.categoryName ?? "Movie"
        currentLogoURL = movie.posterURL
        isLive = false
        currentTime = 0
        duration = 0

        showPlayer = true
        hasError = false
        errorMessage = ""

        beginPlayback(
            saved: savedPosition(sourceID: movie.sourceID, itemID: movie.id),
            artwork: movie.posterURL
        ) { [weak self] resumeAt in
            self?.loadViaVLC(url: movie.streamURL, resumeAt: resumeAt)
        }
    }

    // MARK: - Play Episode (Series)

    func playEpisode(_ episode: Episode, seriesTitle: String, seriesArtwork: URL? = nil) {
        currentChannel = nil
        currentMovie = nil
        currentEpisode = episode
        currentTitle = episode.title
        currentSubtitle = "\(seriesTitle) • Season \(episode.seasonNumber), Ep \(episode.episodeNumber)"
        currentLogoURL = nil
        isLive = false
        currentTime = 0
        duration = Double(episode.durationSecs ?? 0)

        showPlayer = true
        hasError = false
        errorMessage = ""

        beginPlayback(
            saved: savedPosition(sourceID: episode.sourceID, itemID: episode.id),
            artwork: seriesArtwork
        ) { [weak self] resumeAt in
            self?.loadViaVLC(url: episode.streamURL, resumeAt: resumeAt)
        }
    }

    // MARK: - VLC Loading (VOD)

    private func loadViaVLC(url: URL, resumeAt: Double? = nil) {
        // The AVPlayer item must go quiet, or its audio keeps running underneath.
        player.pause()
        player.replaceCurrentItem(with: nil)
        engineKind = .vlc
        clearTracks()

        // Reuses the reconnect machinery: both need "seek here once playing".
        if let resumeAt {
            resumePosition = resumeAt
            resumedFromSeconds = resumeAt
        } else {
            resumedFromSeconds = nil
        }

        vlcEngine.load(url: url, volume: volume, isMuted: isMuted)

        vlcTimeoutTask?.cancel()
        vlcTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.isLoading && !self.hasError {
                self.hasError = true
                self.errorMessage = "The server did not start sending this title. It may be slow, offline, or the link may be dead."
                self.isLoading = false
            }
        }
    }

    private func handleVLCState(_ state: VLCPlaybackEngine.State) {
        switch state {
        case .loading:
            isLoading = true
            hasError = false
        case .playing:
            vlcTimeoutTask?.cancel()
            isLoading = false
            isPlaying = true
            hasError = false
            if duration == 0 {
                duration = vlcEngine.durationSeconds
            }
            refreshVLCTracks()
            applySubtitleSize()
            onPlaybackEstablished()
        case .paused:
            isLoading = false
            isPlaying = false
        case .ended:
            vlcTimeoutTask?.cancel()
            isPlaying = false
            isLoading = false
        case .failed:
            vlcTimeoutTask?.cancel()
            isPlaying = false
            scheduleReconnect(
                reason: "This title could not be opened. The link may be dead or the server may be refusing the request."
            )
        case .idle:
            isPlaying = false
        }
    }

    private func teardownVLC() {
        vlcTimeoutTask?.cancel()
        vlcTimeoutTask = nil
        _vlcEngine?.stop()
    }

    // MARK: - URL Resolution

    private func resolvePlaybackURL(for originalURL: URL) -> URL {
        var str = originalURL.absoluteString
        // For live streams, prefer .m3u8 for native macOS AVFoundation HLS playback
        if str.hasSuffix(".ts") {
            str = String(str.dropLast(3)) + ".m3u8"
            if let m3u8URL = URL(string: str) {
                return m3u8URL
            }
        }
        return originalURL
    }

    // MARK: - Stream Loading

    private func loadStream(url: URL, fallbackURL: URL?, title: String, isLive: Bool) {
        // Clean up previous observers
        statusObservation?.invalidate()
        errorObservation?.invalidate()
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let notif = itemFailedNotification {
            NotificationCenter.default.removeObserver(notif)
            itemFailedNotification = nil
        }
        if let notif = itemStalledNotification {
            NotificationCenter.default.removeObserver(notif)
            itemStalledNotification = nil
        }

        // Supply User-Agent via AVURLAssetHTTPHeaderFieldsKey to prevent 403 Forbidden
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": iptvUserAgent,
                "Accept": "*/*"
            ]
        ])
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = isLive ? 5 : 15

        player.replaceCurrentItem(with: playerItem)

        // Observe item status
        statusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self = self else { return }
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.player.play()
                    self.isPlaying = true
                    self.refreshAVTracks(for: item)
                    self.applySubtitleSize()
                    self.onPlaybackEstablished()

                    // Setup timeline time observer for non-live VOD
                    if !isLive {
                        let itemDuration = item.duration
                        if itemDuration.isNumeric && !itemDuration.isIndefinite {
                            self.duration = CMTimeGetSeconds(itemDuration)
                        }

                        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
                        self.timeObserverToken = self.player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                            Task { @MainActor [weak self] in
                                guard let self = self, !self.isScrubbing else { return }
                                self.currentTime = CMTimeGetSeconds(time)
                                if let curItem = self.player.currentItem {
                                    let d = curItem.duration
                                    if d.isNumeric && !d.isIndefinite {
                                        self.duration = CMTimeGetSeconds(d)
                                    }
                                }
                            }
                        }
                    }

                case .failed:
                    if let fallback = fallbackURL {
                        self.loadStream(url: fallback, fallbackURL: nil, title: title, isLive: isLive)
                    } else {
                        self.scheduleReconnect(
                            reason: item.error?.localizedDescription ?? "The stream stopped responding."
                        )
                    }
                default:
                    break
                }
            }
        }

        // Observe item error
        errorObservation = playerItem.observe(\.error, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self = self, let error = item.error else { return }
                if let fallback = fallbackURL {
                    self.loadStream(url: fallback, fallbackURL: nil, title: title, isLive: isLive)
                } else {
                    self.scheduleReconnect(reason: error.localizedDescription)
                }
            }
        }

        // Listen for playback failure notification
        itemFailedNotification = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self = self else { return }
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self.scheduleReconnect(
                    reason: error?.localizedDescription ?? "Playback was interrupted."
                )
            }
        }

        // A stall is the common failure for live IPTV: the connection survives but
        // the server stops feeding it, so AVPlayer reports neither error nor end.
        itemStalledNotification = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.scheduleReconnect(reason: "The stream stalled.")
            }
        }

        player.volume = volume
        player.isMuted = isMuted

        // Auto-retry play after short delay if stream doesn't respond
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if self.isLoading && !self.hasError && self.currentTitle == title {
                if let currentItem = self.player.currentItem, currentItem.status == .unknown {
                    // Still buffering
                } else if self.player.timeControlStatus == .paused && !self.isPlaying {
                    self.hasError = true
                    self.errorMessage = "Stream timed out. The server may be slow or unavailable."
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Controls

    func togglePlayPause() {
        switch engineKind {
        case .avFoundation:
            if isPlaying { player.pause() } else { player.play() }
            isPlaying.toggle()
        case .vlc:
            // Let the engine's state callback drive isPlaying so the UI cannot
            // drift out of sync with libVLC.
            if isPlaying { vlcEngine.pause() } else { vlcEngine.play() }
        }
    }

    func toggleMute() {
        isMuted.toggle()
        switch engineKind {
        case .avFoundation: player.isMuted = isMuted
        case .vlc: vlcEngine.apply(muted: isMuted)
        }
    }

    func setVolume(_ newVolume: Float) {
        volume = newVolume
        switch engineKind {
        case .avFoundation: player.volume = newVolume
        case .vlc: vlcEngine.apply(volume: newVolume)
        }
    }

    func seek(to seconds: Double) {
        let clamped = max(0, min(duration > 0 ? duration : seconds, seconds))
        currentTime = clamped
        switch engineKind {
        case .avFoundation:
            let target = CMTime(seconds: clamped, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        case .vlc:
            vlcEngine.seek(toSeconds: clamped)
        }
    }

    /// False for live inputs and for VOD that the server refuses to seek, so the
    /// scrubber can be hidden rather than offering a control that does nothing.
    var canSeek: Bool {
        switch engineKind {
        case .avFoundation: return !isLive
        case .vlc: return vlcEngine.isSeekable
        }
    }

    // MARK: - Resume Playback

    /// Set by the app when a profile becomes active. Resume positions are
    /// per-profile, so without it nothing is recorded.
    var activeProfileID: UUID?

    /// Where the current item resumed from, surfaced so the UI can say so.
    @Published private(set) var resumedFromSeconds: Double?

    /// Non-nil while the player is waiting for the viewer to choose between
    /// resuming and starting over. Playback has not begun yet.
    @Published private(set) var pendingResumeSeconds: Double?

    /// Runtime recorded alongside the saved position, so the prompt can show
    /// how far in it is. The stream has not been opened yet, so this is the only
    /// source of duration at that point.
    @Published private(set) var pendingResumeDuration: Double?

    /// Poster art for the title awaiting a resume decision.
    @Published private(set) var pendingResumeArtwork: URL?

    /// 0...1 through the title, or nil when the saved duration is unknown.
    var pendingResumeProgress: Double? {
        guard let seconds = pendingResumeSeconds,
              let duration = pendingResumeDuration,
              duration > 0 else {
            return nil
        }
        return min(1, max(0, seconds / duration))
    }

    /// Starts the item that is waiting on that choice. Takes the offset to
    /// resume from, or nil to start at the beginning.
    private var pendingStart: ((Double?) -> Void)?

    func resumeFromSavedPosition() {
        guard let seconds = pendingResumeSeconds, let start = pendingStart else { return }
        clearPendingResume()
        isLoading = true
        start(seconds)
    }

    func startFromBeginning() {
        guard let start = pendingStart else { return }
        clearPendingResume()
        isLoading = true
        start(nil)
    }

    private func clearPendingResume() {
        pendingResumeSeconds = nil
        pendingResumeDuration = nil
        pendingResumeArtwork = nil
        pendingStart = nil
    }

    /// Either asks first, or starts straight away when there is nothing to resume.
    private func beginPlayback(
        saved: PlaybackPosition?,
        artwork: URL?,
        start: @escaping (Double?) -> Void
    ) {
        guard let saved else {
            clearPendingResume()
            isLoading = true
            start(nil)
            return
        }
        // Hold off on loading: the choice decides where the stream opens, and
        // seeking afterwards would waste a buffer fill.
        pendingStart = start
        pendingResumeSeconds = saved.seconds
        pendingResumeDuration = saved.duration > 0 ? saved.duration : nil
        pendingResumeArtwork = artwork
        isLoading = false
    }

    private let persistence = PersistenceController.shared
    private var positions: [PlaybackPosition] = []
    private var positionsLoadedFor: UUID?
    private var lastPositionWrite: Date = .distantPast

    /// Identity and presentation of whatever is playing, or nil for live TV
    /// (not resumable).
    private struct ResumeKey {
        let sourceID: UUID
        let itemID: String
        let title: String
        let streamURL: URL
        let artworkURL: URL?
        let subtitle: String
        let isEpisode: Bool
    }

    private var currentResumeKey: ResumeKey? {
        if let movie = currentMovie {
            return ResumeKey(
                sourceID: movie.sourceID, itemID: movie.id, title: movie.name,
                streamURL: movie.streamURL, artworkURL: movie.posterURL,
                subtitle: movie.categoryName ?? "Movie", isEpisode: false
            )
        }
        if let episode = currentEpisode {
            return ResumeKey(
                sourceID: episode.sourceID, itemID: episode.id, title: episode.title,
                streamURL: episode.streamURL, artworkURL: pendingResumeArtwork ?? currentLogoURL,
                subtitle: currentSubtitle, isEpisode: true
            )
        }
        return nil
    }

    private func loadPositionsIfNeeded() {
        guard let profileID = activeProfileID, positionsLoadedFor != profileID else { return }
        positions = persistence.loadPlaybackPositions(profileID: profileID)
        positionsLoadedFor = profileID
    }

    /// The saved position for an item, or nil when there is nothing worth resuming.
    private func savedPosition(sourceID: UUID, itemID: String) -> PlaybackPosition? {
        loadPositionsIfNeeded()
        guard let match = positions.first(where: { $0.sourceID == sourceID && $0.itemID == itemID }),
              match.isResumable else {
            return nil
        }
        return match
    }

    /// Throttled to one write every 5s — this is driven by a 250ms time callback.
    private func recordPosition(force: Bool = false) {
        guard let profileID = activeProfileID,
              let key = currentResumeKey,
              currentTime > 0 else {
            return
        }
        guard force || Date().timeIntervalSince(lastPositionWrite) >= 5 else { return }
        lastPositionWrite = Date()

        loadPositionsIfNeeded()

        let entry = PlaybackPosition(
            profileID: profileID,
            sourceID: key.sourceID,
            itemID: key.itemID,
            title: key.title,
            seconds: currentTime,
            duration: duration,
            updatedAt: Date(),
            streamURL: key.streamURL.absoluteString,
            artworkURL: key.artworkURL?.absoluteString,
            subtitle: key.subtitle,
            isEpisode: key.isEpisode
        )

        positions.removeAll { $0.sourceID == key.sourceID && $0.itemID == key.itemID }
        // Finished titles are kept, not dropped. Knowing an episode was watched
        // is what lets the series sheet offer the *next* one, and what makes
        // "Hide watched" mean watched rather than merely in-progress. Resume
        // callers filter on `isResumable`, so a finished entry never auto-plays.
        positions.insert(entry, at: 0)
        // Bounded so the file cannot grow without limit.
        if positions.count > 200 {
            positions = Array(positions.prefix(200))
        }
        persistence.savePlaybackPositions(positions, profileID: profileID)
    }

    /// Saved progress for an episode as a 0...1 fraction, or nil when there is
    /// none worth showing. Lets episode rows draw a progress bar without the
    /// view touching persistence.
    func savedProgress(for episode: Episode) -> Double? {
        savedProgress(sourceID: episode.sourceID, itemID: episode.id)
    }

    /// Forgets an item's position, so "Start Over" genuinely starts over rather
    /// than hitting the resume prompt again.
    func clearSavedPosition(sourceID: UUID, itemID: String) {
        guard let profileID = activeProfileID else { return }
        loadPositionsIfNeeded()
        positions.removeAll { $0.sourceID == sourceID && $0.itemID == itemID }
        persistence.savePlaybackPositions(positions, profileID: profileID)
    }

    /// Raw saved position, including finished ones — the series sheet needs to
    /// tell "watched" from "never started".
    func playbackPosition(sourceID: UUID, itemID: String) -> PlaybackPosition? {
        loadPositionsIfNeeded()
        return positions.first { $0.sourceID == sourceID && $0.itemID == itemID }
    }

    /// Progress for any catalogue item, so poster cards can show a resume bar.
    func savedProgress(sourceID: UUID, itemID: String) -> Double? {
        loadPositionsIfNeeded()
        guard let match = positions.first(where: {
            $0.sourceID == sourceID && $0.itemID == itemID
        }), match.isResumable, match.duration > 0 else {
            return nil
        }
        return match.fractionComplete
    }

    /// Most recent resumable titles, newest first — drives Continue Watching.
    func resumableItems(limit: Int = 3) -> [PlaybackPosition] {
        loadPositionsIfNeeded()
        return positions
            .filter { $0.isResumable && $0.streamURL != nil }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    /// Reopens a saved position straight from the library, skipping the resume
    /// prompt — picking a Continue Watching card already expresses the intent.
    func resume(_ position: PlaybackPosition) {
        guard let raw = position.streamURL, let url = URL(string: raw) else { return }

        currentChannel = nil
        currentMovie = nil
        currentEpisode = nil
        currentTitle = position.title
        currentSubtitle = position.subtitle ?? ""
        currentLogoURL = position.artworkURL.flatMap(URL.init(string:))
        isLive = false
        currentTime = 0
        duration = position.duration

        showPlayer = true
        hasError = false
        errorMessage = ""
        clearPendingResume()
        isLoading = true

        loadViaVLC(url: url, resumeAt: position.seconds)
    }

    // MARK: - Live Channel Switching

    /// Channels the player can move between, in the order the browser shows
    /// them. Set when playback starts so ↑/↓ and "Try next channel" follow the
    /// list the viewer was actually looking at.
    var channelLineup: [Channel] = []

    /// Category name for the lineup, shown in the drawer header.
    var lineupCategory: String?

    private var currentLineupIndex: Int? {
        guard let current = currentChannel else { return nil }
        return channelLineup.firstIndex { $0.compoundID == current.compoundID }
    }

    var canSwitchChannel: Bool { channelLineup.count > 1 && currentChannel != nil }

    /// Moves `offset` places through the lineup, wrapping at both ends.
    func switchChannel(by offset: Int) {
        guard canSwitchChannel, let index = currentLineupIndex else { return }
        let count = channelLineup.count
        let next = ((index + offset) % count + count) % count
        playChannel(channelLineup[next])
    }

    /// Used by the error state: the stream is dead, so move on rather than
    /// retrying the same URL.
    func playNextChannel() {
        switchChannel(by: 1)
    }

    // MARK: - Playback Speed

    static let availableSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    @Published private(set) var playbackSpeed: Float = 1.0

    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        switch engineKind {
        case .vlc:
            vlcEngine.setRate(speed)
        case .avFoundation:
            // Assigning rate also resumes a paused player, so only apply it live.
            if isPlaying { player.rate = speed }
        }
    }

    // MARK: - Subtitle Size

    /// Subtitle text size, expressed once and mapped per engine.
    ///
    /// The two engines scale in opposite directions. AVFoundation takes a
    /// percentage of the default, so larger means larger. libVLC's text renderer
    /// takes a *relative* size that acts as a divisor of the video height
    /// (text height ≈ video height ÷ value), so there a **smaller number means
    /// bigger text**. Its scale runs 20 (smaller) to 6 (larger).
    enum SubtitleSize: String, CaseIterable, Identifiable {
        case small, medium, large, extraLarge

        var id: String { rawValue }

        var label: String {
            switch self {
            case .small: return "S"
            case .medium: return "M"
            case .large: return "L"
            case .extraLarge: return "XL"
            }
        }

        /// Spelled out for Settings, where there is room for words.
        var longLabel: String {
            switch self {
            case .small: return "Small"
            case .medium: return "Medium"
            case .large: return "Large"
            case .extraLarge: return "Extra Large"
            }
        }

        /// Relative size for libVLC's freetype renderer — a divisor of the video
        /// height, so this descends as the text grows. Being a ratio, it also
        /// keeps subtitles consistent across 720p and 4K sources.
        var vlcRelativeSize: Int {
            switch self {
            case .small: return 20
            case .medium: return 16
            case .large: return 11
            case .extraLarge: return 7
            }
        }

        /// Percentage of the default size for AVFoundation text style rules.
        var avRelativePercent: NSNumber {
            switch self {
            case .small: return 75
            case .medium: return 100
            case .large: return 140
            case .extraLarge: return 190
            }
        }
    }

    private static let subtitleSizeDefaultsKey = "subtitleSize"

    @Published private(set) var subtitleSize: SubtitleSize = {
        let stored = UserDefaults.standard.string(forKey: PlayerViewModel.subtitleSizeDefaultsKey)
        return stored.flatMap(SubtitleSize.init(rawValue:)) ?? .medium
    }()

    func setSubtitleSize(_ size: SubtitleSize) {
        subtitleSize = size
        UserDefaults.standard.set(size.rawValue, forKey: Self.subtitleSizeDefaultsKey)
        applySubtitleSize()
    }

    /// Re-applied whenever a new item starts, since both engines reset styling
    /// when the media changes.
    private func applySubtitleSize() {
        switch engineKind {
        case .vlc:
            _vlcEngine?.setSubtitleFontSize(subtitleSize.vlcRelativeSize)
        case .avFoundation:
            guard let item = player.currentItem else { return }
            let rule = AVTextStyleRule(textMarkupAttributes: [
                kCMTextMarkupAttribute_RelativeFontSize as String: subtitleSize.avRelativePercent
            ])
            item.textStyleRules = [rule].compactMap { $0 }
        }
    }

    // MARK: - Track Selection

    func selectAudioTrack(id: Int) {
        currentAudioTrackID = id
        switch engineKind {
        case .vlc:
            vlcEngine.selectAudioTrack(id: id)
        case .avFoundation:
            guard let group = avAudibleGroup,
                  avAudibleOptions.indices.contains(id) else { return }
            player.currentItem?.select(avAudibleOptions[id], in: group)
        }
    }

    func selectSubtitleTrack(id: Int) {
        currentSubtitleTrackID = id
        switch engineKind {
        case .vlc:
            vlcEngine.selectSubtitleTrack(id: id)
        case .avFoundation:
            guard let group = avLegibleGroup else { return }
            if id == MediaTrack.offID {
                player.currentItem?.select(nil, in: group)
            } else if avLegibleOptions.indices.contains(id) {
                player.currentItem?.select(avLegibleOptions[id], in: group)
            }
        }
    }

    /// True when an external subtitle file can be attached — libVLC only.
    /// AVFoundation cannot mix a sidecar file into a live HLS stream.
    var canAddExternalSubtitles: Bool {
        engineKind == .vlc && showPlayer
    }

    /// Loads a subtitle file alongside the playing title.
    @discardableResult
    func addExternalSubtitle(_ url: URL) -> Bool {
        guard engineKind == .vlc else { return false }
        let accepted = vlcEngine.addSubtitleFile(url)
        guard accepted else { return false }

        // libVLC announces the new track asynchronously, so the menu is
        // repopulated once it has caught up rather than immediately.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            self?.refreshVLCTracks()
            self?.applySubtitleSize()
        }
        return true
    }

    private func refreshVLCTracks() {
        let audio = vlcEngine.audioTracks
        let subtitles = vlcEngine.subtitleTracks

        // Avoid republishing identical lists; libVLC re-announces streams often.
        if audio != audioTracks { audioTracks = audio }
        if subtitles != subtitleTracks { subtitleTracks = subtitles }

        currentAudioTrackID = vlcEngine.currentAudioTrackID
        currentSubtitleTrackID = vlcEngine.currentSubtitleTrackID
    }

    /// Reads the HLS media selection groups. Safe to call once the item is ready
    /// to play, by which point the groups have loaded.
    private func refreshAVTracks(for item: AVPlayerItem) {
        let asset = item.asset

        avAudibleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible)
        avLegibleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .legible)

        avAudibleOptions = avAudibleGroup?.options ?? []
        avLegibleOptions = avLegibleGroup?.options ?? []

        audioTracks = avAudibleOptions.enumerated().map { index, option in
            MediaTrack(id: index, name: Self.displayName(for: option, fallback: "Audio \(index + 1)"))
        }

        // Only offer the menu when there is something to choose; "Off" alone is noise.
        if avLegibleOptions.isEmpty {
            subtitleTracks = []
        } else {
            subtitleTracks = [MediaTrack(id: MediaTrack.offID, name: "Off")]
                + avLegibleOptions.enumerated().map { index, option in
                    MediaTrack(id: index, name: Self.displayName(for: option, fallback: "Subtitle \(index + 1)"))
                }
        }

        let selection = item.currentMediaSelection
        currentAudioTrackID = avAudibleGroup
            .flatMap { selection.selectedMediaOption(in: $0) }
            .flatMap { avAudibleOptions.firstIndex(of: $0) }
        currentSubtitleTrackID = avLegibleGroup
            .flatMap { selection.selectedMediaOption(in: $0) }
            .flatMap { avLegibleOptions.firstIndex(of: $0) } ?? MediaTrack.offID
    }

    private static func displayName(for option: AVMediaSelectionOption, fallback: String) -> String {
        if !option.displayName.isEmpty { return option.displayName }
        if let tag = option.extendedLanguageTag,
           let localized = Locale.current.localizedString(forIdentifier: tag) {
            return localized
        }
        return fallback
    }

    private func clearTracks() {
        audioTracks = []
        subtitleTracks = []
        currentAudioTrackID = nil
        currentSubtitleTrackID = nil
        avAudibleGroup = nil
        avLegibleGroup = nil
        avAudibleOptions = []
        avLegibleOptions = []
    }

    // MARK: - Picture-in-Picture

    /// Called by the AVPlayer surface once its layer exists. PiP needs a layer,
    /// which is why the live path renders through AVPlayerLayer.
    func registerPictureInPicture(layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        guard pipController?.playerLayer !== layer else { return }

        let controller = AVPictureInPictureController(playerLayer: layer)
        controller?.delegate = self
        pipController = controller

        // `isPictureInPicturePossible` flips once the layer is ready. Observing it
        // is what lets the PiP button appear on its own; a computed property would
        // leave SwiftUI with nothing to invalidate on.
        pipPossibleObservation?.invalidate()
        pipPossibleObservation = controller?.observe(
            \.isPictureInPicturePossible,
            options: [.initial, .new]
        ) { [weak self] controller, _ in
            Task { @MainActor in
                self?.isPictureInPicturePossible = controller.isPictureInPicturePossible
            }
        }
    }

    /// Only the AVPlayer path can do PiP; libVLC renders into its own NSView and
    /// has no AVPictureInPicture equivalent.
    var isPictureInPictureAvailable: Bool {
        engineKind == .avFoundation && isPictureInPicturePossible
    }

    func togglePictureInPicture() {
        guard let pipController else { return }
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else {
            pipController.startPictureInPicture()
        }
    }

    // MARK: - Automatic Reconnection

    /// Retries a dropped stream with exponential backoff before surfacing an
    /// error. IPTV servers drop connections routinely, and a transient blip
    /// should not require the user to click Retry.
    private func scheduleReconnect(reason: String) {
        guard reconnectAttempt < maxReconnectAttempts else {
            isReconnecting = false
            isLoading = false
            hasError = true
            errorMessage = "\(reason) Reconnecting failed after \(maxReconnectAttempts) attempts."
            return
        }

        reconnectAttempt += 1
        isReconnecting = true
        isLoading = true
        hasError = false

        // Remember where VOD was so playback resumes rather than restarting.
        if !isLive && currentTime > 0 {
            resumePosition = currentTime
        }

        let backoff = UInt64(pow(2.0, Double(reconnectAttempt))) * 1_000_000_000

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: backoff)
            guard let self, !Task.isCancelled, self.showPlayer else { return }
            self.reload()
        }
    }

    /// Replays the current item without clearing the reconnect counter.
    private func reload() {
        if let channel = currentChannel {
            let primary = resolvePlaybackURL(for: channel.streamURL)
            loadStream(
                url: primary,
                fallbackURL: channel.streamURL != primary ? channel.streamURL : nil,
                title: channel.name,
                isLive: true
            )
        } else if let movie = currentMovie {
            loadViaVLC(url: movie.streamURL)
        } else if let episode = currentEpisode {
            loadViaVLC(url: episode.streamURL)
        }
    }

    private func onPlaybackEstablished() {
        reconnectAttempt = 0
        isReconnecting = false
        reconnectTask?.cancel()
        reconnectTask = nil

        if resumePosition > 0 {
            let target = resumePosition
            resumePosition = 0
            seek(to: target)
        }
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    /// User-initiated retry. Unlike an automatic reconnect this clears the attempt
    /// counter, so pressing Retry always gets a fresh set of tries.
    func retry() {
        reconnectTask?.cancel()
        reconnectAttempt = 0
        isReconnecting = false
        resumePosition = 0

        if let channel = currentChannel {
            playChannel(channel)
        } else if let movie = currentMovie {
            playMovie(movie)
        } else if let episode = currentEpisode {
            playEpisode(episode, seriesTitle: currentSubtitle)
        }
    }

    func stop() {
        // Persist before tearing down, or the last few seconds are lost.
        recordPosition(force: true)
        resumedFromSeconds = nil
        clearPendingResume()
        playbackSpeed = 1.0
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        isReconnecting = false
        resumePosition = 0
        clearTracks()
        if pipController?.isPictureInPictureActive == true {
            pipController?.stopPictureInPicture()
        }
        teardownVLC()
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        isPlaying = false
        isLoading = false
        currentChannel = nil
        currentMovie = nil
        currentEpisode = nil
        showPlayer = false
        hasError = false
        currentTime = 0
        duration = 0
    }

    /// The window hosting the player. The player is an overlay inside the main
    /// window rather than a sheet, because AppKit will not take a sheet fullscreen.
    private var hostWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible }
    }

    /// `isFullscreen` is driven by the window's own notifications rather than
    /// being set here, so it stays correct when the green button or the system
    /// gesture is used instead of our controls.
    func toggleFullscreen() {
        hostWindow?.toggleFullScreen(nil)
    }

    func exitFullscreen() {
        guard isFullscreen else { return }
        hostWindow?.toggleFullScreen(nil)
    }

    private func observeFullscreenChanges() {
        enterFullscreenNotification = NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isFullscreen = true }
        }

        exitFullscreenNotification = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isFullscreen = false }
        }
    }

    // MARK: - Helpers

    func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds >= 0 else { return "00:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    var formattedCurrentTime: String {
        formatTime(currentTime)
    }

    var formattedDuration: String {
        formatTime(duration)
    }

    // MARK: - Private

    private func setupObservers() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self = self else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.isPlaying = true
                    self.isLoading = false
                case .paused:
                    if !self.isLoading && !self.hasError {
                        self.isPlaying = false
                    }
                case .waitingToPlayAtSpecifiedRate:
                    self.isLoading = true
                @unknown default:
                    break
                }
            }
        }
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PlayerViewModel: AVPictureInPictureControllerDelegate {

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in self.isPictureInPictureActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in self.isPictureInPictureActive = false }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        // Non-fatal: playback continues inline, so only the PiP state is reset.
        Task { @MainActor in self.isPictureInPictureActive = false }
    }
}
