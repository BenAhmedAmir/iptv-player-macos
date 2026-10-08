import Foundation
import SwiftUI

// MARK: - Sources View Model

/// Manages IPTV sources for the active profile.
@MainActor
final class SourcesViewModel: ObservableObject {
    @Published var sources: [IPTVSource] = []
    @Published var isLoading = false
    @Published var error: IPTVError?
    @Published var showError = false
    @Published var isShowingAddSource = false
    @Published var loadingSourceID: UUID?

    private let persistence = PersistenceController.shared
    private let xtreamService = XtreamAPIService()
    private let m3uParser = M3UParserService()

    var profileID: UUID?

    // MARK: - Load Sources

    func loadSources(profileID: UUID) {
        self.profileID = profileID
        sources = persistence.loadSources(profileID: profileID)
    }

    // MARK: - Add Xtream Source

    func addXtreamSource(
        name: String,
        serverURL: String,
        username: String,
        password: String
    ) async {
        guard let profileID = profileID else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            // Validate credentials
            _ = try await xtreamService.authenticate(
                serverURL: serverURL,
                username: username,
                password: password
            )

            // Create source
            var source = IPTVSource(
                profileID: profileID,
                name: name.isEmpty ? "Xtream Source" : name,
                type: .xtreamCodes,
                serverURL: serverURL
            )

            // Fetch categories and live streams
            let categories = try await xtreamService.getLiveCategories(
                serverURL: serverURL, username: username, password: password
            )
            let streams = try await xtreamService.getLiveStreams(
                serverURL: serverURL, username: username, password: password
            )

            let channels = xtreamService.convertToChannels(
                streams: streams, categories: categories,
                serverURL: serverURL, username: username, password: password,
                sourceID: source.id
            )

            source.channelCount = channels.count
            source.lastRefreshedAt = Date()

            // Store credentials securely
            try KeychainService.shared.storeCredentials(
                sourceID: source.id,
                username: username,
                password: password
            )

            // Cache channels FIRST so they are available when sources publish updates
            let cached = channels.map(CachedChannel.init)
            persistence.saveCachedChannels(cached, sourceID: source.id)

            sources.append(source)
            persistence.saveSources(sources, profileID: profileID)

        } catch let iptvError as IPTVError {
            self.error = iptvError
            self.showError = true
        } catch {
            self.error = .unknown(error.localizedDescription)
            self.showError = true
        }
    }

    // MARK: - Add M3U File Source

    func addM3UFileSource(name: String, fileURL: URL) async {
        guard let profileID = profileID else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            // Create a security-scoped bookmark so we can re-access the file later
            let bookmarkData: Data?
            do {
                bookmarkData = try fileURL.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                // If bookmark creation fails, still try to read the file
                bookmarkData = nil
            }

            var source = IPTVSource(
                profileID: profileID,
                name: name.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : name,
                type: .m3uFile,
                localFilePath: fileURL.path,
                fileBookmark: bookmarkData
            )

            let channels = try await m3uParser.parseLocalFileURL(fileURL, sourceID: source.id)
            source.channelCount = channels.count
            source.lastRefreshedAt = Date()

            // Cache channels
            let cached = channels.map(CachedChannel.init)
            persistence.saveCachedChannels(cached, sourceID: source.id)

            sources.append(source)
            persistence.saveSources(sources, profileID: profileID)

        } catch let iptvError as IPTVError {
            self.error = iptvError
            self.showError = true
        } catch {
            self.error = .unknown(error.localizedDescription)
            self.showError = true
        }
    }

    // MARK: - Add M3U URL Source

    func addM3UURLSource(name: String, url: String) async {
        guard let profileID = profileID else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            var source = IPTVSource(
                profileID: profileID,
                name: name.isEmpty ? "M3U URL" : name,
                type: .m3uURL,
                remoteURL: url
            )

            let channels = try await m3uParser.parseRemoteURL(url, sourceID: source.id)
            source.channelCount = channels.count
            source.lastRefreshedAt = Date()

            // Cache channels
            let cached = channels.map(CachedChannel.init)
            persistence.saveCachedChannels(cached, sourceID: source.id)

            sources.append(source)
            persistence.saveSources(sources, profileID: profileID)

        } catch let iptvError as IPTVError {
            self.error = iptvError
            self.showError = true
        } catch {
            self.error = .unknown(error.localizedDescription)
            self.showError = true
        }
    }

    // MARK: - Refresh Source

    // MARK: - Re-authenticate Xtream Source

    /// Replaces the stored credentials for an existing Xtream source.
    ///
    /// Deleting and re-adding the source would mint a new `sourceID`, orphaning the
    /// favorites and watch history that key off it, so re-authentication has to
    /// happen in place. Needed whenever the Keychain entry is lost or the provider
    /// rotates a password.
    func updateXtreamCredentials(
        _ source: IPTVSource,
        username: String,
        password: String
    ) async -> Bool {
        guard let serverURL = source.serverURL else {
            error = .invalidStreamURL
            showError = true
            return false
        }

        loadingSourceID = source.id
        defer { loadingSourceID = nil }

        do {
            // Verify before storing, so a typo cannot overwrite working credentials.
            _ = try await xtreamService.authenticate(
                serverURL: serverURL,
                username: username,
                password: password
            )

            try KeychainService.shared.storeCredentials(
                sourceID: source.id,
                username: username,
                password: password
            )

            await refreshSource(source)
            return true

        } catch let iptvError as IPTVError {
            self.error = iptvError
            self.showError = true
        } catch {
            self.error = .unknown(error.localizedDescription)
            self.showError = true
        }
        return false
    }

    /// True when an Xtream source has no usable Keychain entry, so the UI can
    /// prompt for re-authentication instead of failing every refresh.
    func needsCredentials(_ source: IPTVSource) -> Bool {
        guard source.type == .xtreamCodes else { return false }
        return KeychainService.shared.getCredentials(sourceID: source.id) == nil
    }

    func refreshSource(_ source: IPTVSource) async {
        guard let profileID = profileID else { return }
        loadingSourceID = source.id

        defer { loadingSourceID = nil }

        do {
            var channels: [Channel] = []

            switch source.type {
            case .xtreamCodes:
                guard let serverURL = source.serverURL,
                      let creds = KeychainService.shared.getCredentials(sourceID: source.id) else {
                    throw IPTVError.invalidCredentials
                }

                let categories = try await xtreamService.getLiveCategories(
                    serverURL: serverURL, username: creds.username, password: creds.password
                )
                let streams = try await xtreamService.getLiveStreams(
                    serverURL: serverURL, username: creds.username, password: creds.password
                )

                channels = xtreamService.convertToChannels(
                    streams: streams, categories: categories,
                    serverURL: serverURL, username: creds.username, password: creds.password,
                    sourceID: source.id
                )

            case .m3uFile:
                // Try using the security-scoped bookmark first
                if let bookmark = source.fileBookmark {
                    var isStale = false
                    if let fileURL = try? URL(
                        resolvingBookmarkData: bookmark,
                        options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    ) {
                        channels = try await m3uParser.parseLocalFileURL(fileURL, sourceID: source.id)
                    } else if let path = source.localFilePath {
                        channels = try await m3uParser.parseLocalFile(at: path, sourceID: source.id)
                    } else {
                        throw IPTVError.fileNotFound("No file path")
                    }
                } else if let path = source.localFilePath {
                    channels = try await m3uParser.parseLocalFile(at: path, sourceID: source.id)
                } else {
                    throw IPTVError.fileNotFound("No file path")
                }

            case .m3uURL:
                guard let url = source.remoteURL else {
                    throw IPTVError.invalidM3U("No URL")
                }
                channels = try await m3uParser.parseRemoteURL(url, sourceID: source.id)
            }

            // Cache channels FIRST before updating source state
            let cached = channels.map(CachedChannel.init)
            persistence.saveCachedChannels(cached, sourceID: source.id)

            // Update source
            if let index = sources.firstIndex(where: { $0.id == source.id }) {
                sources[index].channelCount = channels.count
                sources[index].lastRefreshedAt = Date()
                sources[index].updatedAt = Date()
                persistence.saveSources(sources, profileID: profileID)
            }

        } catch let iptvError as IPTVError {
            self.error = iptvError
            self.showError = true
        } catch {
            self.error = .unknown(error.localizedDescription)
            self.showError = true
        }
    }

    // MARK: - Delete Source

    func deleteSource(_ source: IPTVSource) {
        guard let profileID = profileID else { return }

        KeychainService.shared.deleteCredentials(sourceID: source.id)
        persistence.deleteCachedChannels(sourceID: source.id)
        sources.removeAll { $0.id == source.id }
        persistence.saveSources(sources, profileID: profileID)
    }

    // MARK: - Toggle Source

    func toggleSource(_ source: IPTVSource) {
        guard let profileID = profileID else { return }

        if let index = sources.firstIndex(where: { $0.id == source.id }) {
            sources[index].isEnabled.toggle()
            sources[index].updatedAt = Date()
            persistence.saveSources(sources, profileID: profileID)
        }
    }

    // MARK: - Rename Source

    func renameSource(_ source: IPTVSource, to newName: String) {
        guard let profileID = profileID else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let index = sources.firstIndex(where: { $0.id == source.id }) {
            sources[index].name = trimmed
            sources[index].updatedAt = Date()
            persistence.saveSources(sources, profileID: profileID)
        }
    }
}
