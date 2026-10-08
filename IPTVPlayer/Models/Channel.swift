import Foundation

// MARK: - Channel

/// Unified channel model used by both Xtream and M3U sources.
/// The UI doesn't need to know the origin of the channel.
struct Channel: Identifiable, Hashable {
    let id: String           // Unique within source (streamID for Xtream, hash for M3U)
    let sourceID: UUID       // Which IPTVSource this came from
    let name: String
    let streamURL: URL
    let logoURL: URL?
    let group: String?
    let tvgID: String?
    let language: String?
    let country: String?

    /// A compound key for uniquely identifying this channel across sources.
    var compoundID: String {
        "\(sourceID.uuidString)_\(id)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(compoundID)
    }

    static func == (lhs: Channel, rhs: Channel) -> Bool {
        lhs.compoundID == rhs.compoundID
    }
}

// MARK: - Channel persistence (for favorites/history serialization)

/// A lightweight serializable reference to a channel.
struct ChannelReference: Codable, Hashable {
    let channelID: String
    let sourceID: UUID

    var compoundID: String {
        "\(sourceID.uuidString)_\(channelID)"
    }
}
