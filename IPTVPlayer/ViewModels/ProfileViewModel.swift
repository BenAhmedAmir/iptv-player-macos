import Foundation
import SwiftUI

// MARK: - Profile View Model

/// Manages profile CRUD, selection, and profile-scoped data isolation.
@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var activeProfile: Profile?
    @Published var isShowingProfilePicker = false
    @Published var isShowingCreateProfile = false
    @Published var isShowingRenameProfile = false
    @Published var profileToRename: Profile?
    @Published var newProfileName = ""

    private let persistence = PersistenceController.shared

    init() {
        loadProfiles()
    }

    // MARK: - Load

    func loadProfiles() {
        profiles = persistence.loadProfiles()
        let settings = persistence.loadSettings()

        if let defaultID = settings.defaultProfileID,
           let defaultProfile = profiles.first(where: { $0.id == defaultID }) {
            activeProfile = defaultProfile
        } else if let first = profiles.first {
            activeProfile = first
        }

        isShowingProfilePicker = profiles.isEmpty
    }

    // MARK: - Create

    func createProfile(name: String, avatarColorID: String? = nil, isKids: Bool = false) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let profile = Profile(name: trimmed, avatarColorID: avatarColorID, isKids: isKids)
        profiles.append(profile)
        persistence.saveProfiles(profiles)

        // If this is the first profile, activate it
        if activeProfile == nil {
            selectProfile(profile)
        }
    }

    // MARK: - Rename

    func renameProfile(_ profile: Profile, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index].name = trimmed
            profiles[index].updatedAt = Date()
            persistence.saveProfiles(profiles)

            if activeProfile?.id == profile.id {
                activeProfile = profiles[index]
            }
        }
    }

    // MARK: - Delete

    func deleteProfile(_ profile: Profile) {
        // Delete associated data
        let sources = persistence.loadSources(profileID: profile.id)
        for source in sources {
            KeychainService.shared.deleteCredentials(sourceID: source.id)
            persistence.deleteCachedChannels(sourceID: source.id)
        }
        persistence.deleteProfileData(profileID: profile.id)

        profiles.removeAll { $0.id == profile.id }
        persistence.saveProfiles(profiles)

        // If deleted profile was active, switch to first available
        if activeProfile?.id == profile.id {
            activeProfile = profiles.first
            if let active = activeProfile {
                setDefaultProfile(active)
            }
        }

        if profiles.isEmpty {
            isShowingProfilePicker = true
        }
    }

    /// Number of sources configured for a profile, shown under its avatar on the
    /// picker. Read straight from disk because profiles other than the active
    /// one have nothing loaded in memory.
    func sourceCount(for profile: Profile) -> Int {
        persistence.loadSources(profileID: profile.id).count
    }

    // MARK: - Select

    func selectProfile(_ profile: Profile) {
        KeychainService.shared.clearCache()
        activeProfile = profile
        setDefaultProfile(profile)
        isShowingProfilePicker = false
    }

    // MARK: - Default

    func setDefaultProfile(_ profile: Profile) {
        var settings = persistence.loadSettings()
        settings.defaultProfileID = profile.id
        persistence.saveSettings(settings)
    }

    // MARK: - Helpers

    var hasProfiles: Bool {
        !profiles.isEmpty
    }
}
