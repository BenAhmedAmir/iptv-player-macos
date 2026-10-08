import Foundation

// MARK: - Favorite

/// A favorited channel, scoped to a profile. Uses channel + source compound key.
struct Favorite: Identifiable, Codable, Hashable {
    let id: UUID
    let profileID: UUID
    let sourceID: UUID
    let channelID: String
    let channelName: String
    let addedAt: Date

    var compoundChannelID: String {
        "\(sourceID.uuidString)_\(channelID)"
    }

    init(profileID: UUID, sourceID: UUID, channelID: String, channelName: String) {
        self.id = UUID()
        self.profileID = profileID
        self.sourceID = sourceID
        self.channelID = channelID
        self.channelName = channelName
        self.addedAt = Date()
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Favorite, rhs: Favorite) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Recently Watched

/// A record of a recently played channel, scoped to a profile.
struct RecentlyWatched: Identifiable, Codable, Hashable {
    let id: UUID
    let profileID: UUID
    let sourceID: UUID
    let channelID: String
    let channelName: String
    var lastWatchedAt: Date

    var compoundChannelID: String {
        "\(sourceID.uuidString)_\(channelID)"
    }

    init(profileID: UUID, sourceID: UUID, channelID: String, channelName: String) {
        self.id = UUID()
        self.profileID = profileID
        self.sourceID = sourceID
        self.channelID = channelID
        self.channelName = channelName
        self.lastWatchedAt = Date()
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: RecentlyWatched, rhs: RecentlyWatched) -> Bool {
        lhs.id == rhs.id
    }
}
