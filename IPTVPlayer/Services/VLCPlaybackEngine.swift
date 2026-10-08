import Foundation
import VLCKit
import VLCBridge
import AppKit

// MARK: - VLC Playback Engine

/// Wraps `VLCMediaPlayer` for VOD playback (movies and episodes).
///
/// AVFoundation has no Matroska or AVI demuxer on macOS, and roughly half of a
/// typical Xtream catalogue ships in those containers — AVPlayer fails them with
/// error -11828 ("Cannot Open"). libVLC handles every container the providers
/// serve, so all VOD is routed here. Live TV stays on AVPlayer, where native HLS
/// playback brings hardware decoding and Picture-in-Picture.
@MainActor
final class VLCPlaybackEngine: NSObject {

    /// Normalised playback state, insulating callers from libVLC's finer-grained enum.
    enum State {
        case idle
        case loading
        case playing
        case paused
        case ended
        case failed
    }

    let mediaPlayer = VLCMediaPlayer()

    /// Fires on every state transition, already hopped to the main actor.
    var onStateChange: ((State) -> Void)?
    /// Fires roughly every 250ms with (currentSeconds, durationSeconds).
    var onTimeChange: ((Double, Double) -> Void)?
    /// Fires when elementary streams appear, so track menus can repopulate.
    var onTracksChanged: (() -> Void)?

    private let userAgent: String
    private(set) var state: State = .idle

    init(userAgent: String) {
        self.userAgent = userAgent
        super.init()
        mediaPlayer.delegate = self
    }

    // MARK: - Video Output

    /// Points libVLC at the view that should receive decoded frames. Safe to call
    /// repeatedly: SwiftUI may rebuild the representable while playback continues.
    func attach(to view: VLCVideoView) {
        if mediaPlayer.drawable as? VLCVideoView !== view {
            mediaPlayer.drawable = view
        }
    }

    // MARK: - Loading

    func load(url: URL, volume: Float, isMuted: Bool) {
        let media = VLCMedia(url: url)

        // Xtream servers reject the default libVLC agent, and VOD benefits from a
        // deeper buffer than the live defaults allow.
        media.addOption(":http-user-agent=\(userAgent)")
        media.addOption(":network-caching=1500")
        media.addOption(":http-reconnect")

        mediaPlayer.media = media

        apply(volume: volume)
        apply(muted: isMuted)

        transition(to: .loading)
        mediaPlayer.play()
    }

    // MARK: - Controls

    func play() {
        mediaPlayer.play()
    }

    func pause() {
        // Unlike AVPlayer, -pause toggles in some libVLC builds; gate on state.
        if mediaPlayer.isPlaying {
            mediaPlayer.pause()
        }
    }

    func stop() {
        mediaPlayer.stop()
        mediaPlayer.media = nil
        // Release the video view. libVLC holds the drawable strongly, and a
        // retained NSView can outlive the SwiftUI representable that made it.
        mediaPlayer.drawable = nil
        transition(to: .idle)
    }

    func apply(volume: Float) {
        // VLCAudio uses 0...200 where 100 is unity gain.
        mediaPlayer.audio?.volume = Int32(max(0, min(1, volume)) * 100)
    }

    func setRate(_ rate: Float) {
        mediaPlayer.rate = rate
    }

    func apply(muted: Bool) {
        mediaPlayer.audio?.isMuted = muted
    }

    /// Seeks to an absolute offset. No-ops on non-seekable inputs, which libVLC
    /// would otherwise ignore silently.
    func seek(toSeconds seconds: Double) {
        guard mediaPlayer.isSeekable else { return }
        let milliseconds = Int(max(0, seconds) * 1000)
        mediaPlayer.time = VLCTime(number: NSNumber(value: milliseconds))
    }

    var isSeekable: Bool {
        mediaPlayer.isSeekable
    }

    // MARK: - Track Selection

    /// Real audio tracks, excluding libVLC's synthetic "Disabled" entry. Matroska
    /// releases commonly carry several language dubs.
    var audioTracks: [MediaTrack] {
        zipTracks(names: mediaPlayer.audioTrackNames, ids: mediaPlayer.audioTrackIndexes)
            .filter { $0.id != Self.disabledTrackID }
    }

    /// Subtitle tracks with libVLC's "Disabled" entry relabelled as "Off", so
    /// turning subtitles off is a normal menu choice.
    var subtitleTracks: [MediaTrack] {
        let tracks = zipTracks(
            names: mediaPlayer.videoSubTitlesNames,
            ids: mediaPlayer.videoSubTitlesIndexes
        )
        guard !tracks.filter({ $0.id != Self.disabledTrackID }).isEmpty else { return [] }
        return tracks.map { track in
            track.id == Self.disabledTrackID ? MediaTrack(id: track.id, name: "Off") : track
        }
    }

    var currentAudioTrackID: Int {
        Int(mediaPlayer.currentAudioTrackIndex)
    }

    var currentSubtitleTrackID: Int {
        Int(mediaPlayer.currentVideoSubTitleIndex)
    }

    func selectAudioTrack(id: Int) {
        mediaPlayer.currentAudioTrackIndex = Int32(id)
    }

    func selectSubtitleTrack(id: Int) {
        mediaPlayer.currentVideoSubTitleIndex = Int32(id)
    }

    /// Attaches an external subtitle file to the playing media.
    ///
    /// libVLC calls these "playback slaves": the file is mixed into the current
    /// stream as an extra SPU track, so it appears in the subtitle menu like an
    /// embedded one. Half of a typical VOD catalogue ships with no subtitles at
    /// all, which is what makes this worth having.
    ///
    /// - Returns: whether libVLC accepted the file.
    @discardableResult
    func addSubtitleFile(_ url: URL) -> Bool {
        // enforce: selects the new track immediately — the viewer just asked for it.
        mediaPlayer.addPlaybackSlave(url, type: .subtitle, enforce: true) == 0
    }

    /// Sets libVLC's relative subtitle size — a divisor of the video height, so
    /// a *smaller* value renders *larger* text (its scale runs 20 down to 6).
    /// 0 restores automatic sizing. Goes through the Objective-C bridge because
    /// VLCKit exposes no public API for the text renderer.
    func setSubtitleFontSize(_ relativeSize: Int) {
        IPTVSetSubtitleFontSize(mediaPlayer, Int32(relativeSize))
    }

    /// libVLC's sentinel for "no track" — also what it reports for its synthetic
    /// "Disabled" menu entry.
    static let disabledTrackID = -1

    /// `audioTrackNames`/`audioTrackIndexes` are parallel `NSArray`s of names and
    /// track IDs. The IDs, not the array positions, are what the setters expect.
    private func zipTracks(names: [Any], ids: [Any]) -> [MediaTrack] {
        guard names.count == ids.count else { return [] }
        return zip(names, ids).compactMap { name, id in
            guard let title = name as? String,
                  let trackID = (id as? NSNumber)?.intValue else {
                return nil
            }
            return MediaTrack(id: trackID, name: title)
        }
    }

    /// Duration in seconds, or 0 while libVLC is still parsing the container.
    var durationSeconds: Double {
        guard let milliseconds = mediaPlayer.media?.length.value?.doubleValue,
              milliseconds > 0 else {
            return 0
        }
        return milliseconds / 1000
    }

    var currentSeconds: Double {
        guard let milliseconds = mediaPlayer.time.value?.doubleValue else { return 0 }
        return milliseconds / 1000
    }

    // MARK: - Private

    private func transition(to newState: State) {
        state = newState
        onStateChange?(newState)
    }

    private func mapped(_ vlcState: VLCMediaPlayerState) -> State {
        switch vlcState {
        case .opening, .buffering:
            return .loading
        case .playing:
            return .playing
        case .paused:
            return .paused
        case .ended:
            return .ended
        case .error:
            return .failed
        case .stopped:
            // Reached both on an explicit stop and after an aborted open. Treating
            // it as idle keeps a user-initiated stop from surfacing as an error.
            return .idle
        case .esAdded:
            return state
        @unknown default:
            return state
        }
    }
}

// MARK: - VLCMediaPlayerDelegate

extension VLCPlaybackEngine: VLCMediaPlayerDelegate {

    // libVLC posts these from its own threads, so both hop to the main actor
    // before touching engine state or invoking callbacks.

    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in
            let vlcState = self.mediaPlayer.state

            // Tracks only become enumerable once their elementary streams are
            // announced, which can lag the first decoded frame.
            if vlcState == .esAdded || vlcState == .playing {
                self.onTracksChanged?()
            }

            let mapped = self.mapped(vlcState)
            guard mapped != self.state else { return }
            self.transition(to: mapped)
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in
            // State notifications are not a reliable way to learn that playback
            // began: libVLC may coalesce the Playing transition, or advance past it
            // before this hop reads `state` back. Time moving forward is proof that
            // frames are flowing, so reconcile here rather than trusting the enum.
            if self.mediaPlayer.isPlaying, self.state != .playing {
                self.transition(to: .playing)
            }
            self.onTimeChange?(self.currentSeconds, self.durationSeconds)
        }
    }
}
