import Foundation

// MARK: - M3U Parser Service

/// Parses M3U/M3U8 playlists from local files or remote URLs.
/// Designed to handle large playlists (10,000+ entries) without blocking the UI.
final class M3UParserService {

    // MARK: - Public API

    /// Parses an M3U playlist from a local file path.
    func parseLocalFile(at path: String, sourceID: UUID) async throws -> [Channel] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw IPTVError.fileNotFound(path)
        }

        let url = URL(fileURLWithPath: path)
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            // Try Latin1 if UTF-8 fails
            do {
                content = try String(contentsOf: url, encoding: .isoLatin1)
            } catch {
                throw IPTVError.invalidM3U("Unable to read file encoding")
            }
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IPTVError.emptyM3U
        }

        return try await parseContent(content, sourceID: sourceID)
    }

    /// Parses an M3U playlist from a local file URL (with security-scoped access).
    func parseLocalFileURL(_ fileURL: URL, sourceID: UUID) async throws -> [Channel] {
        let gotAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if gotAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let content: String
        do {
            let data = try Data(contentsOf: fileURL)
            content = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
        } catch {
            throw IPTVError.fileNotFound(fileURL.path)
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IPTVError.emptyM3U
        }

        return try await parseContent(content, sourceID: sourceID)
    }

    /// Parses an M3U playlist from a remote URL.
    func parseRemoteURL(_ urlString: String, sourceID: UUID) async throws -> [Channel] {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            throw IPTVError.invalidM3U("Invalid URL")
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 180
        config.httpAdditionalHeaders = ["User-Agent": "IPTVSmartersPlayer"]
        let session = URLSession(configuration: config)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw IPTVError.networkUnavailable
            case .timedOut:
                throw IPTVError.timeout
            default:
                throw IPTVError.serverUnavailable
            }
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw IPTVError.serverUnavailable
        }

        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw IPTVError.invalidM3U("Unable to decode playlist content")
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IPTVError.emptyM3U
        }

        return try await parseContent(content, sourceID: sourceID)
    }

    // MARK: - Parser

    /// Parses M3U content into Channel objects. Runs on a background thread.
    func parseContent(_ content: String, sourceID: UUID) async throws -> [Channel] {
        return try await Task.detached(priority: .userInitiated) {
            try self.parseM3UString(content, sourceID: sourceID)
        }.value
    }

    private func parseM3UString(_ content: String, sourceID: UUID) throws -> [Channel] {
        let lines = content.components(separatedBy: .newlines)

        // Validate header (lenient—some playlists omit it)
        let hasHeader = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") ?? false

        var channels: [Channel] = []
        var currentInfo: String? = nil
        var channelIndex = 0
        var seenIDs = Set<String>()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty lines, the EXTM3U header, and other comments/directives
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#EXTM3U") { continue }

            if trimmed.hasPrefix("#EXTINF:") {
                currentInfo = trimmed
                continue
            }

            // Skip other M3U directives (#EXTVLCOPT, #EXTGRP, #KODIPROP, etc.)
            if trimmed.hasPrefix("#") {
                continue
            }

            // This is a URL/path line — try to parse it as a stream URL
            let streamURL: URL?
            if trimmed.contains("://") {
                // It's an absolute URL — need to handle special characters
                streamURL = parseStreamURL(trimmed)
            } else {
                // Could be a relative path — skip it for now
                currentInfo = nil
                continue
            }

            guard let url = streamURL else {
                currentInfo = nil
                continue
            }

            let attributes = currentInfo.map { parseExtInf($0) } ?? ExtInfAttributes()
            let name = attributes.name ?? "Channel \(channelIndex + 1)"

            // Generate deterministic ID so favorites/history survive playlist reloads
            let rawID: String
            if let tvgID = attributes.tvgID, !tvgID.isEmpty {
                rawID = tvgID
            } else {
                rawID = deterministicHash(url.absoluteString)
            }

            var channelID = rawID
            if seenIDs.contains(channelID) {
                channelID = "\(rawID)_\(channelIndex)"
            }
            seenIDs.insert(channelID)

            let channel = Channel(
                id: channelID,
                sourceID: sourceID,
                name: name,
                streamURL: url,
                logoURL: attributes.logoURL.flatMap { parseStreamURL($0) },
                group: attributes.groupTitle,
                tvgID: attributes.tvgID,
                language: attributes.tvgLanguage,
                country: attributes.tvgCountry
            )

            channels.append(channel)
            channelIndex += 1
            currentInfo = nil
        }

        if channels.isEmpty && hasHeader {
            // Valid M3U header but no parseable channels
            throw IPTVError.emptyChannelList
        } else if channels.isEmpty {
            throw IPTVError.invalidM3U("No valid channels found in playlist")
        }

        return channels
    }

    // MARK: - URL Parsing

    /// Parses a stream URL string, handling special characters and encoding issues.
    private func parseStreamURL(_ urlString: String) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // First, try direct URL creation
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        // If that failed, try percent-encoding only the characters that need it
        // (preserving already-encoded sequences)
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded), url.scheme != nil {
            return url
        }

        return nil
    }

    // MARK: - EXTINF Attribute Parser

    private struct ExtInfAttributes {
        var name: String?
        var tvgID: String?
        var tvgName: String?
        var tvgLogo: String?
        var tvgLanguage: String?
        var tvgCountry: String?
        var groupTitle: String?
        var logoURL: String?
    }

    private func parseExtInf(_ line: String) -> ExtInfAttributes {
        var attrs = ExtInfAttributes()

        // Extract the display name (after the last comma that's not inside quotes)
        attrs.name = extractDisplayName(from: line)

        // Extract attributes using parsing
        attrs.tvgID = extractAttribute(from: line, key: "tvg-id")
        attrs.tvgName = extractAttribute(from: line, key: "tvg-name")
        attrs.tvgLogo = extractAttribute(from: line, key: "tvg-logo")
        attrs.tvgLanguage = extractAttribute(from: line, key: "tvg-language")
        attrs.tvgCountry = extractAttribute(from: line, key: "tvg-country")
        attrs.groupTitle = extractAttribute(from: line, key: "group-title")

        // Use tvg-logo as logo URL
        attrs.logoURL = attrs.tvgLogo

        // Fallback: use tvg-name if no display name
        if attrs.name == nil || attrs.name?.isEmpty == true {
            attrs.name = attrs.tvgName
        }

        return attrs
    }

    /// Extracts the display name from an EXTINF line.
    /// The name is the text after the first comma that isn't inside attribute quotes.
    private func extractDisplayName(from line: String) -> String? {
        var inQuotes = false
        for index in line.indices {
            let char = line[index]
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                let afterComma = line[line.index(after: index)...]
                let name = afterComma.trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? nil : name
            }
        }
        return nil
    }

    private func extractAttribute(from line: String, key: String) -> String? {
        // Match: key="value"
        let pattern = "\(key)=\""
        guard let startRange = line.range(of: pattern, options: .caseInsensitive) else {
            return nil
        }

        let afterKey = line[startRange.upperBound...]
        guard let endQuote = afterKey.firstIndex(of: "\"") else {
            return nil
        }

        let value = String(afterKey[afterKey.startIndex..<endQuote])
        return value.isEmpty ? nil : value
    }

    /// Computes a stable, 64-bit FNV-1a hash string that is deterministic across app launches.
    private func deterministicHash(_ string: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(hash, radix: 16)
    }
}
