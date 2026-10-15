import Foundation

// MARK: - Xtream API Service

/// Handles all Xtream Codes API communication.
/// Credentials are never logged or exposed.
final class XtreamAPIService {
    private let session: URLSession
    private let timeout: TimeInterval = 15

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = ["User-Agent": "IPTVSmartersPlayer"]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Authentication

    /// Authenticates with an Xtream Codes server and returns account info.
    func authenticate(serverURL: String, username: String, password: String) async throws -> XtreamAuthResponse {
        let url = try buildAPIURL(
            serverURL: serverURL,
            username: username,
            password: password,
            action: nil
        )

        let (data, response) = try await performRequest(url: url)
        try validateHTTPResponse(response)

        do {
            let authResponse = try JSONDecoder().decode(XtreamAuthResponse.self, from: data)

            // Check account status
            if let userInfo = authResponse.userInfo {
                if !userInfo.isActive {
                    if userInfo.isExpired {
                        throw IPTVError.expiredAccount
                    }
                    throw IPTVError.invalidCredentials
                }
            }

            return authResponse
        } catch let error as IPTVError {
            throw error
        } catch {
            // Try to check if the response is HTML (wrong server URL)
            if let responseStr = String(data: data, encoding: .utf8),
               responseStr.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
                throw IPTVError.invalidResponse
            }
            throw IPTVError.invalidResponse
        }
    }

    // MARK: - Live Categories

    /// Fetches live TV categories from an Xtream Codes server.
    func getLiveCategories(serverURL: String, username: String, password: String) async throws -> [XtreamCategory] {
        let url = try buildAPIURL(
            serverURL: serverURL,
            username: username,
            password: password,
            action: "get_live_categories"
        )

        let (data, response) = try await performRequest(url: url)
        try validateHTTPResponse(response)

        do {
            return try JSONDecoder().decode([XtreamCategory].self, from: data)
        } catch {
            // Some servers return an empty object {} instead of []
            if let responseStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               responseStr == "{}" || responseStr.isEmpty {
                return []
            }
            throw IPTVError.invalidResponse
        }
    }

    // MARK: - Live Streams

    /// Fetches live TV streams from an Xtream Codes server.
    func getLiveStreams(serverURL: String, username: String, password: String) async throws -> [XtreamLiveStream] {
        let url = try buildAPIURL(
            serverURL: serverURL,
            username: username,
            password: password,
            action: "get_live_streams"
        )

        let (data, response) = try await performRequest(url: url)
        try validateHTTPResponse(response)

        do {
            return try JSONDecoder().decode([XtreamLiveStream].self, from: data)
        } catch {
            // Some servers return an empty object {} instead of []
            if let responseStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               responseStr == "{}" || responseStr.isEmpty {
                return []
            }
            throw IPTVError.invalidResponse
        }
    }

    // MARK: - Channel Conversion

    /// Converts Xtream live streams to unified Channel model.
    func convertToChannels(
        streams: [XtreamLiveStream],
        categories: [XtreamCategory],
        serverURL: String,
        username: String,
        password: String,
        sourceID: UUID
    ) -> [Channel] {
        let baseURL = normalizeServerURL(serverURL)
        let categoryMap = Dictionary(categories.map { ($0.categoryID, $0.categoryName) }, uniquingKeysWith: { first, _ in first })

        // Percent-encode username/password for URL path segments
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? password

        return streams.compactMap { stream -> Channel? in
            guard let streamID = stream.streamID,
                  let name = stream.name, !name.isEmpty else {
                return nil
            }

            // Determine the stream extension. Use container_extension if available,
            // fall back to .ts which is more widely compatible than .m3u8 for live streams.
            let ext: String
            if let containerExt = stream.containerExtension, !containerExt.isEmpty {
                ext = containerExt
            } else {
                ext = "m3u8"
            }

            let streamURLString = "\(baseURL)/live/\(encodedUsername)/\(encodedPassword)/\(streamID).\(ext)"
            guard let streamURL = URL(string: streamURLString) else { return nil }

            let logoURL: URL? = {
                guard let icon = stream.streamIcon, !icon.isEmpty else { return nil }
                // Clean up the icon URL - some servers return malformed URLs
                let cleaned = icon.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { return nil }
                return URL(string: cleaned)
            }()

            let group = stream.categoryID.flatMap { categoryMap[$0] }

            return Channel(
                id: String(streamID),
                sourceID: sourceID,
                name: name,
                streamURL: streamURL,
                logoURL: logoURL,
                group: group,
                tvgID: stream.epgChannelID,
                language: nil,
                country: nil
            )
        }
    }

    // MARK: - VOD Categories & Streams

    /// Fetches VOD / Movies categories from an Xtream Codes server.
    func getVODCategories(serverURL: String, username: String, password: String) async throws -> [XtreamCategory] {
        let url = try buildAPIURL(
            serverURL: serverURL,
            username: username,
            password: password,
            action: "get_vod_categories"
        )

        let (data, response) = try await performRequest(url: url)
        try validateHTTPResponse(response)

        do {
            return try JSONDecoder().decode([XtreamCategory].self, from: data)
        } catch {
            if let responseStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               responseStr == "{}" || responseStr.isEmpty {
                return []
            }
            throw IPTVError.invalidResponse
        }
    }

    /// Fetches VOD / Movies streams (optionally filtered by category).
    func getVODStreams(serverURL: String, username: String, password: String, categoryID: String? = nil) async throws -> [XtreamVODStream] {
        var extra: [String: String]? = nil
        if let catID = categoryID, !catID.isEmpty {
            extra = ["category_id": catID]
        }

        let url = try buildAPIURL(
            serverURL: serverURL,
            username: username,
            password: password,
            action: "get_vod_streams",
            extraParams: extra
        )

        let (data, response) = try await performRequest(url: url)
        try validateHTTPResponse(response)

        do {
            return try JSONDecoder().decode([XtreamVODStream].self, from: data)
        } catch {
            if let responseStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               responseStr == "{}" || responseStr.isEmpty {
                return []
            }
            throw IPTVError.invalidResponse
        }
    }

    /// Converts Xtream VOD streams to unified Movie model.
    func convertToMovies(
        streams: [XtreamVODStream],
        categories: [XtreamCategory],
        serverURL: String,
        username: String,
        password: String,
        sourceID: UUID
    ) -> [Movie] {
        let baseURL = normalizeServerURL(serverURL)
        let categoryMap = Dictionary(categories.map { ($0.categoryID, $0.categoryName) }, uniquingKeysWith: { first, _ in first })

        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? password

        return streams.compactMap { stream -> Movie? in
            guard let streamID = stream.streamID,
                  let name = stream.name, !name.isEmpty else {
                return nil
            }

            let ext = stream.containerExtension?.isEmpty == false ? stream.containerExtension! : "mp4"
            let streamURLString = "\(baseURL)/movie/\(encodedUsername)/\(encodedPassword)/\(streamID).\(ext)"
            guard let streamURL = URL(string: streamURLString) else { return nil }

            let posterURL: URL? = {
                guard let icon = stream.streamIcon, !icon.isEmpty else { return nil }
                let cleaned = icon.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { return nil }
                return URL(string: cleaned)
            }()

            let catName = stream.categoryID.flatMap { categoryMap[$0] }

            return Movie(
                id: String(streamID),
                sourceID: sourceID,
                name: name,
                streamURL: streamURL,
                posterURL: posterURL,
                rating: stream.rating ?? (stream.rating5based.map { $0 * 2.0 }),
                categoryID: stream.categoryID,
                categoryName: catName,
                containerExtension: ext,
                added: stream.added
            )
        }
    }

    // MARK: - Series (TV Shows)

    /// Fetches TV Show / Series categories from an Xtream Codes server.
    func getSeriesCategories(serverURL: String, username: String, password: String) async throws -> [XtreamCategory] {
        let url = try buildAPIURL(
            serverURL: serverURL,
            username: username,
            password: password,
            action: "get_series_categories"
        )

        let (data, response) = try await performRequest(url: url)
        try validateHTTPResponse(response)

        do {
            return try JSONDecoder().decode([XtreamCategory].self, from: data)
        } catch {
            if let responseStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               responseStr == "{}" || responseStr.isEmpty {
                return []
            }
            throw IPTVError.invalidResponse
        }
    }

    /// Fetches Series items (optionally filtered by category).
    func getSeries(serverURL: String, username: String, password: String, categoryID: String? = nil) async throws -> [XtreamSeriesItem] {
        var extra: [String: String]? = nil
        if let catID = categoryID, !catID.isEmpty {
            extra = ["category_id": catID]
        }

        let url = try buildAPIURL(
            serverURL: serverURL,
            username: username,
            password: password,
            action: "get_series",
            extraParams: extra
        )

        let (data, response) = try await performRequest(url: url)
        try validateHTTPResponse(response)

        do {
            return try JSONDecoder().decode([XtreamSeriesItem].self, from: data)
        } catch {
            if let responseStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               responseStr == "{}" || responseStr.isEmpty {
                return []
            }
            throw IPTVError.invalidResponse
        }
    }

    /// Converts Xtream Series items to unified Series model.
    func convertToSeries(
        items: [XtreamSeriesItem],
        categories: [XtreamCategory],
        serverURL: String,
        username: String,
        password: String,
        sourceID: UUID
    ) -> [Series] {
        let categoryMap = Dictionary(categories.map { ($0.categoryID, $0.categoryName) }, uniquingKeysWith: { first, _ in first })

        return items.compactMap { item -> Series? in
            guard let seriesID = item.seriesID,
                  let name = item.name, !name.isEmpty else {
                return nil
            }

            let coverURL = item.cover.flatMap { str -> URL? in
                let cleaned = str.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? nil : URL(string: cleaned)
            }

            let backdropURL = item.backdropPath?.first.flatMap { str -> URL? in
                let cleaned = str.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? nil : URL(string: cleaned)
            }

            let catName = item.categoryID.flatMap { categoryMap[$0] }

            return Series(
                id: String(seriesID),
                sourceID: sourceID,
                name: name,
                coverURL: coverURL,
                backdropURL: backdropURL,
                plot: item.plot,
                cast: item.cast,
                director: item.director,
                genre: item.genre,
                releaseDate: item.releaseDate,
                rating: item.rating ?? (item.rating5based.map { $0 * 2.0 }),
                episodeRunTime: item.episodeRunTime,
                categoryID: item.categoryID,
                categoryName: catName
            )
        }
    }

    /// Fetches series information and episodes.
    func getSeriesInfo(serverURL: String, username: String, password: String, seriesID: String) async throws -> XtreamSeriesInfoResponse {
        let url = try buildAPIURL(
            serverURL: serverURL,
            username: username,
            password: password,
            action: "get_series_info",
            extraParams: ["series_id": seriesID]
        )

        let (data, response) = try await performRequest(url: url)
        try validateHTTPResponse(response)

        do {
            return try JSONDecoder().decode(XtreamSeriesInfoResponse.self, from: data)
        } catch {
            throw IPTVError.invalidResponse
        }
    }

    /// Converts Xtream Series Info episodes into unified Episode models.
    func convertToEpisodes(
        response: XtreamSeriesInfoResponse,
        seriesID: String,
        serverURL: String,
        username: String,
        password: String,
        sourceID: UUID
    ) -> [Episode] {
        guard let episodesDict = response.episodes else { return [] }

        let baseURL = normalizeServerURL(serverURL)
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? password

        var result: [Episode] = []

        for (seasonKey, episodeList) in episodesDict {
            let seasonNum = Int(seasonKey) ?? 1

            for ep in episodeList {
                guard let epID = ep.id, !epID.isEmpty else { continue }

                let ext = ep.containerExtension?.isEmpty == false ? ep.containerExtension! : "mp4"
                let streamURLString = "\(baseURL)/series/\(encodedUsername)/\(encodedPassword)/\(epID).\(ext)"
                guard let streamURL = URL(string: streamURLString) else { continue }

                let epNum = ep.episodeNum ?? (result.count + 1)
                let title = ep.title?.isEmpty == false ? ep.title! : "Episode \(epNum)"

                let episode = Episode(
                    id: epID,
                    seriesID: seriesID,
                    sourceID: sourceID,
                    seasonNumber: ep.season ?? seasonNum,
                    episodeNumber: epNum,
                    title: title,
                    streamURL: streamURL,
                    containerExtension: ext,
                    durationSecs: ep.info?.durationSecs,
                    formattedDuration: ep.info?.duration,
                    plot: ep.info?.plot,
                    imageURL: ep.info?.movieImage.flatMap { URL(string: $0) }
                )
                result.append(episode)
            }
        }

        // Sort by season number, then episode number
        return result.sorted {
            if $0.seasonNumber != $1.seasonNumber {
                return $0.seasonNumber < $1.seasonNumber
            }
            return $0.episodeNumber < $1.episodeNumber
        }
    }

    // MARK: - Private Helpers

    /// Builds a properly encoded API URL for the Xtream Codes API.
    private func buildAPIURL(
        serverURL: String,
        username: String,
        password: String,
        action: String?,
        extraParams: [String: String]? = nil
    ) throws -> URL {
        let baseURL = normalizeServerURL(serverURL)
        let apiPath = "\(baseURL)/player_api.php"

        guard var components = URLComponents(string: apiPath) else {
            throw IPTVError.serverUnavailable
        }

        var queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password)
        ]
        if let action = action {
            queryItems.append(URLQueryItem(name: "action", value: action))
        }
        if let extra = extraParams {
            for (key, val) in extra {
                queryItems.append(URLQueryItem(name: key, value: val))
            }
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw IPTVError.serverUnavailable
        }
        return url
    }

    private func normalizeServerURL(_ url: String) -> String {
        var normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove trailing slash
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        // Remove trailing /player_api.php if user pasted the full API URL
        if normalized.hasSuffix("/player_api.php") {
            normalized = String(normalized.dropLast("/player_api.php".count))
        }
        // Ensure protocol
        if !normalized.hasPrefix("http://") && !normalized.hasPrefix("https://") {
            normalized = "http://\(normalized)"
        }
        return normalized
    }

    private func performRequest(url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(from: url)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw IPTVError.networkUnavailable
            case .timedOut:
                throw IPTVError.timeout
            case .cannotConnectToHost, .cannotFindHost:
                throw IPTVError.serverUnavailable
            default:
                throw IPTVError.serverUnavailable
            }
        } catch {
            throw IPTVError.serverUnavailable
        }
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw IPTVError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw IPTVError.invalidCredentials
        case 404:
            throw IPTVError.serverUnavailable
        case 500...599:
            throw IPTVError.serverUnavailable
        default:
            throw IPTVError.invalidResponse
        }
    }
}
