import Foundation

// MARK: - Profile

/// An independent user profile with its own sources, favorites, and history.
struct Profile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    // Optional so profiles written before these existed still decode.

    /// Swatch id from `AvatarPalette`; nil falls back to the first swatch.
    var avatarColorID: String?

    /// Kids profiles are captioned "Restricted" and hide adult categories.
    var isKids: Bool?

    var isRestricted: Bool { isKids == true }

    init(
        id: UUID = UUID(),
        name: String,
        avatarColorID: String? = nil,
        isKids: Bool = false
    ) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.avatarColorID = avatarColorID
        self.isKids = isKids
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Profile, rhs: Profile) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Restricted Content

/// Category screening for kids profiles.
///
/// Providers do not flag adult content in any structured way, so matching is on
/// the category name. Erring toward hiding: a false positive hides a category
/// from a child, a false negative shows them something it should not.
enum ContentRestriction {
    private static let blockedTerms = [
        "adult", "xxx", "porn", "erotic", "18+", "+18", "sex", "playboy", "hot "
    ]

    static func isRestricted(category: String?) -> Bool {
        guard let category = category?.lowercased() else { return false }
        return blockedTerms.contains { category.contains($0) }
    }
}
