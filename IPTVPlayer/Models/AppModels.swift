import Foundation

// MARK: - App Settings

/// Global application settings persisted in UserDefaults.
struct AppSettings: Codable {
    var defaultProfileID: UUID?
    var appearance: AppAppearance

    init() {
        self.defaultProfileID = nil
        self.appearance = .system
    }
}

// MARK: - Appearance

/// Application appearance mode.
enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

// MARK: - Navigation

/// Sidebar navigation items.
enum NavigationItem: Hashable {
    case home
    case liveTV
    case favorites
    case movies
    case series
    case sources
    case settings
}

// MARK: - App Errors

/// Human-readable error types for the application.
enum IPTVError: LocalizedError {
    case invalidCredentials
    case expiredAccount
    case serverUnavailable
    case networkUnavailable
    case timeout
    case invalidResponse
    case emptyChannelList
    case invalidM3U(String)
    case emptyM3U
    case invalidStreamURL
    case playbackFailed(String)
    case keychainError(String)
    case fileNotFound(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid username or password. Please check your credentials."
        case .expiredAccount:
            return "Your account has expired. Please contact your provider."
        case .serverUnavailable:
            return "The server is currently unavailable. Please try again later."
        case .networkUnavailable:
            return "No network connection. Please check your internet connection."
        case .timeout:
            return "The request timed out. Please try again."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .emptyChannelList:
            return "No channels were found for this source."
        case .invalidM3U(let detail):
            return "Invalid M3U playlist: \(detail)"
        case .emptyM3U:
            return "The playlist file is empty."
        case .invalidStreamURL:
            return "The stream URL is invalid."
        case .playbackFailed(let detail):
            return "Playback failed: \(detail)"
        case .keychainError(let detail):
            return "Keychain error: \(detail)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .unknown(let detail):
            return "An unexpected error occurred: \(detail)"
        }
    }
}
