import Foundation

// MARK: - Source Type

/// The type of IPTV source.
enum IPTVSourceType: String, Codable, CaseIterable, Identifiable {
    case xtreamCodes = "xtream"
    case m3uFile = "m3u_file"
    case m3uURL = "m3u_url"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .xtreamCodes: return "Xtream Codes"
        case .m3uFile: return "M3U File"
        case .m3uURL: return "M3U URL"
        }
    }

    var iconName: String {
        switch self {
        case .xtreamCodes: return "server.rack"
        case .m3uFile: return "doc.text"
        case .m3uURL: return "link"
        }
    }
}

// MARK: - IPTV Source

/// Represents an IPTV source (Xtream, local M3U, or remote M3U).
struct IPTVSource: Identifiable, Codable, Hashable {
    let id: UUID
    let profileID: UUID
    var name: String
    var type: IPTVSourceType
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastRefreshedAt: Date?

    // Xtream Codes fields
    var serverURL: String?
    // Username/password stored in Keychain, keyed by source ID

    // M3U file path (local)
    var localFilePath: String?

    // M3U URL (remote)
    var remoteURL: String?

    // Cached channel count
    var channelCount: Int

    // Security-scoped bookmark for sandboxed file access
    var fileBookmark: Data?

    /// Optional XMLTV guide endpoint supplied when the source was added.
    /// Stored now so an EPG feature has it; nothing reads it yet.
    var epgURL: String?

    // Account facts captured at sign-in and on every refresh. Optional so
    // sources saved before these existed still decode.

    /// When the provider says the subscription lapses.
    var expiresAt: Date?
    /// Provider's own word for the account state, e.g. "Active".
    var accountStatus: String?
    /// Simultaneous streams the plan allows.
    var maxConnections: Int?
    var isTrialAccount: Bool?

    init(
        id: UUID = UUID(),
        profileID: UUID,
        name: String,
        type: IPTVSourceType,
        serverURL: String? = nil,
        localFilePath: String? = nil,
        remoteURL: String? = nil,
        fileBookmark: Data? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.name = name
        self.type = type
        self.isEnabled = true
        self.createdAt = Date()
        self.updatedAt = Date()
        self.lastRefreshedAt = nil
        self.serverURL = serverURL
        self.localFilePath = localFilePath
        self.remoteURL = remoteURL
        self.channelCount = 0
        self.fileBookmark = fileBookmark
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: IPTVSource, rhs: IPTVSource) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Flexible JSON Decoding Helpers

/// Many Xtream servers return inconsistent JSON types (e.g., numbers as strings,
/// booleans as "0"/"1" strings, etc.). These helpers handle all variants gracefully.
private struct FlexibleString: Codable {
    let value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            value = str
        } else if let intVal = try? container.decode(Int.self) {
            value = String(intVal)
        } else if let doubleVal = try? container.decode(Double.self) {
            value = String(doubleVal)
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal ? "1" : "0"
        } else if container.decodeNil() {
            value = nil
        } else {
            value = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

private struct FlexibleBool: Codable {
    let value: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let str = try? container.decode(String.self) {
            value = (str == "1" || str.lowercased() == "true")
        } else if let intVal = try? container.decode(Int.self) {
            value = intVal != 0
        } else {
            value = false
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

private struct FlexibleInt: Codable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let str = try? container.decode(String.self), let intVal = Int(str) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = Int(doubleVal)
        } else {
            value = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - Xtream Account Info

/// Account information returned by Xtream Codes API.
/// Uses flexible decoding to handle servers that return inconsistent types.
struct XtreamAccountInfo: Codable {
    let username: String?
    let password: String?
    let status: String?
    let expirationDate: String?
    let isTrial: Bool
    let activeCons: String?
    let maxConnections: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case username
        case password
        case status
        case expirationDate = "exp_date"
        case isTrial = "is_trial"
        case activeCons = "active_cons"
        case maxConnections = "max_connections"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // All string fields flexibly decoded
        username = try? container.decode(FlexibleString.self, forKey: .username).value
        password = try? container.decode(FlexibleString.self, forKey: .password).value
        status = try? container.decode(FlexibleString.self, forKey: .status).value
        expirationDate = try? container.decode(FlexibleString.self, forKey: .expirationDate).value
        activeCons = try? container.decode(FlexibleString.self, forKey: .activeCons).value
        maxConnections = try? container.decode(FlexibleString.self, forKey: .maxConnections).value
        createdAt = try? container.decode(FlexibleString.self, forKey: .createdAt).value

        // is_trial can be Bool, String ("0"/"1"), or Int (0/1)
        if let flexible = try? container.decode(FlexibleBool.self, forKey: .isTrial) {
            isTrial = flexible.value
        } else {
            isTrial = false
        }
    }

    var isActive: Bool {
        guard let status = status else { return false }
        return status.lowercased() == "active"
    }

    var isExpired: Bool {
        guard let expiry = expiryDate else { return false }
        return expiry < Date()
    }

    /// `exp_date` as a date. Providers send a Unix timestamp string, and some
    /// send nothing at all for lifetime accounts.
    var expiryDate: Date? {
        guard let expStr = expirationDate,
              let timestamp = TimeInterval(expStr),
              timestamp > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    var maxConnectionCount: Int? {
        guard let maxConnections, let value = Int(maxConnections), value > 0 else { return nil }
        return value
    }
}

// MARK: - Xtream API Response

/// Top-level response from Xtream Codes authentication.
struct XtreamAuthResponse: Codable {
    let userInfo: XtreamAccountInfo?
    let serverInfo: XtreamServerInfo?

    enum CodingKeys: String, CodingKey {
        case userInfo = "user_info"
        case serverInfo = "server_info"
    }
}

/// Server information from Xtream Codes.
struct XtreamServerInfo: Codable {
    let url: String?
    let port: String?
    let httpsPort: String?
    let serverProtocol: String?
    let rtmpPort: String?
    let timezone: String?
    let timestampNow: Int?
    let timeNow: String?

    enum CodingKeys: String, CodingKey {
        case url
        case port
        case httpsPort = "https_port"
        case serverProtocol = "server_protocol"
        case rtmpPort = "rtmp_port"
        case timezone
        case timestampNow = "timestamp_now"
        case timeNow = "time_now"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try? container.decode(FlexibleString.self, forKey: .url).value
        port = try? container.decode(FlexibleString.self, forKey: .port).value
        httpsPort = try? container.decode(FlexibleString.self, forKey: .httpsPort).value
        serverProtocol = try? container.decode(FlexibleString.self, forKey: .serverProtocol).value
        rtmpPort = try? container.decode(FlexibleString.self, forKey: .rtmpPort).value
        timezone = try? container.decode(FlexibleString.self, forKey: .timezone).value
        timeNow = try? container.decode(FlexibleString.self, forKey: .timeNow).value
        if let flexible = try? container.decode(FlexibleInt.self, forKey: .timestampNow) {
            timestampNow = flexible.value
        } else {
            timestampNow = nil
        }
    }
}

// MARK: - Xtream Category

/// A category from the Xtream Codes API.
struct XtreamCategory: Codable, Identifiable {
    let categoryID: String
    let categoryName: String
    let parentID: Int?

    enum CodingKeys: String, CodingKey {
        case categoryID = "category_id"
        case categoryName = "category_name"
        case parentID = "parent_id"
    }

    /// Memberwise init for previews and tests; decoding uses the one below.
    init(categoryID: String, categoryName: String, parentID: Int?) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.parentID = parentID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // category_id can be String or Int
        if let str = try? container.decode(String.self, forKey: .categoryID) {
            categoryID = str
        } else if let intVal = try? container.decode(Int.self, forKey: .categoryID) {
            categoryID = String(intVal)
        } else {
            categoryID = ""
        }

        categoryName = (try? container.decode(String.self, forKey: .categoryName)) ?? "Unknown"

        if let intVal = try? container.decode(Int.self, forKey: .parentID) {
            parentID = intVal
        } else if let str = try? container.decode(String.self, forKey: .parentID), let intVal = Int(str) {
            parentID = intVal
        } else {
            parentID = nil
        }
    }

    var id: String { categoryID }
}

// MARK: - Xtream Live Stream

/// A live stream entry from the Xtream Codes API.
/// Handles the many type inconsistencies across different Xtream server implementations.
struct XtreamLiveStream: Codable {
    let num: Int?
    let name: String?
    let streamType: String?
    let streamID: Int?
    let streamIcon: String?
    let epgChannelID: String?
    let added: String?
    let categoryID: String?
    let customSid: String?
    let tvArchive: Int?
    let directSource: String?
    let tvArchiveDuration: Int?
    let containerExtension: String?

    enum CodingKeys: String, CodingKey {
        case num
        case name
        case streamType = "stream_type"
        case streamID = "stream_id"
        case streamIcon = "stream_icon"
        case epgChannelID = "epg_channel_id"
        case added
        case categoryID = "category_id"
        case customSid = "custom_sid"
        case tvArchive = "tv_archive"
        case directSource = "direct_source"
        case tvArchiveDuration = "tv_archive_duration"
        case containerExtension = "container_extension"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // num can be Int or String
        if let intVal = try? container.decode(Int.self, forKey: .num) {
            num = intVal
        } else if let str = try? container.decode(String.self, forKey: .num), let intVal = Int(str) {
            num = intVal
        } else {
            num = nil
        }

        name = try? container.decode(String.self, forKey: .name)
        streamType = try? container.decode(String.self, forKey: .streamType)

        // streamID can be Int or String — critical field
        if let intVal = try? container.decode(Int.self, forKey: .streamID) {
            streamID = intVal
        } else if let str = try? container.decode(String.self, forKey: .streamID), let intVal = Int(str) {
            streamID = intVal
        } else {
            streamID = nil
        }

        streamIcon = try? container.decode(String.self, forKey: .streamIcon)

        // epg_channel_id can be String or null
        if let str = try? container.decode(String.self, forKey: .epgChannelID) {
            epgChannelID = str.isEmpty ? nil : str
        } else {
            epgChannelID = nil
        }

        added = try? container.decode(FlexibleString.self, forKey: .added).value

        // category_id can be String or Int
        if let str = try? container.decode(String.self, forKey: .categoryID) {
            categoryID = str
        } else if let intVal = try? container.decode(Int.self, forKey: .categoryID) {
            categoryID = String(intVal)
        } else {
            categoryID = nil
        }

        customSid = try? container.decode(FlexibleString.self, forKey: .customSid).value

        // tv_archive can be Int or String
        if let intVal = try? container.decode(Int.self, forKey: .tvArchive) {
            tvArchive = intVal
        } else if let str = try? container.decode(String.self, forKey: .tvArchive), let intVal = Int(str) {
            tvArchive = intVal
        } else {
            tvArchive = nil
        }

        directSource = try? container.decode(String.self, forKey: .directSource)

        if let intVal = try? container.decode(Int.self, forKey: .tvArchiveDuration) {
            tvArchiveDuration = intVal
        } else if let str = try? container.decode(String.self, forKey: .tvArchiveDuration), let intVal = Int(str) {
            tvArchiveDuration = intVal
        } else {
            tvArchiveDuration = nil
        }

        containerExtension = try? container.decode(String.self, forKey: .containerExtension)
    }
}
