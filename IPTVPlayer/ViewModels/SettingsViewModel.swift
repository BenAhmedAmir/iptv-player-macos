import Foundation
import SwiftUI

// MARK: - Settings View Model

/// Manages global application settings.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var appearance: AppAppearance
    @Published var defaultProfileID: UUID?

    private let persistence = PersistenceController.shared

    init() {
        let settings = persistence.loadSettings()
        self.appearance = settings.appearance
        self.defaultProfileID = settings.defaultProfileID
    }

    func saveAppearance(_ newAppearance: AppAppearance) {
        appearance = newAppearance
        var settings = persistence.loadSettings()
        settings.appearance = newAppearance
        persistence.saveSettings(settings)
    }

    func clearImageCache() {
        ImageCacheService.shared.clearCache()
    }
}
