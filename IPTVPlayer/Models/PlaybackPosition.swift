import Foundation

// MARK: - Playback Position

/// Where the viewer left off in a movie or episode, so reopening it resumes
/// rather than restarting.
///
/// Scoped per profile, and keyed by source as well as item: the same film can
/// exist in two providers' catalogues under the same stream id, and one
/// profile's progress must never leak into another's.
struct PlaybackPosition: Codable, Identifiable, Equatable {
    let profileID: UUID
    let sourceID: UUID
    /// Stream id of the movie, or of the individual episode.
    let itemID: String
    var title: String
    var seconds: Double
    var duration: Double
    var updatedAt: Date

    // Optional so files written before these existed still decode.

    /// Stream to reopen. Without it, Continue Watching could only navigate to
    /// the library rather than resume, because a saved position alone cannot be
    /// resolved back to a title that may not be in the loaded category.
    var streamURL: String?
    /// Poster or cover art for the Continue Watching card.
    var artworkURL: String?
    /// Secondary line — the category for a movie, "S1 · E4 · …" for an episode.
    var subtitle: String?
    /// Distinguishes a movie from an episode for the card's badge.
    var isEpisode: Bool?

    var id: String { "\(sourceID.uuidString):\(itemID)" }

    /// Below this, the viewer has barely started and resuming would be noise.
    static let minimumResumeSeconds: Double = 30

    /// At or past this fraction, treat the title as finished and start over.
    static let completionThreshold: Double = 0.95

    var isResumable: Bool {
        guard seconds >= Self.minimumResumeSeconds else { return false }
        guard duration > 0 else { return true }
        return seconds / duration < Self.completionThreshold
    }

    var fractionComplete: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, seconds / duration))
    }
}
