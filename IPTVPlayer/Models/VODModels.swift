import Foundation

// MARK: - Movie (VOD)

/// Unified Movie model for VOD content.
struct Movie: Identifiable, Hashable, Codable {
    let id: String
    let sourceID: UUID
    let name: String
    let streamURL: URL
    let posterURL: URL?
    let rating: Double?
    let categoryID: String?
    let categoryName: String?
    let containerExtension: String?
    let added: String?

    var compoundID: String {
        "\(sourceID.uuidString)_\(id)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(compoundID)
    }

    static func == (lhs: Movie, rhs: Movie) -> Bool {
        lhs.compoundID == rhs.compoundID
    }
}

// MARK: - Series (TV Show)

/// Unified Series / TV Show model.
struct Series: Identifiable, Hashable, Codable {
    let id: String
    let sourceID: UUID
    let name: String
    let coverURL: URL?
    let backdropURL: URL?
    let plot: String?
    let cast: String?
    let director: String?
    let genre: String?
    let releaseDate: String?
    let rating: Double?
    let episodeRunTime: String?
    let categoryID: String?
    let categoryName: String?

    var compoundID: String {
        "\(sourceID.uuidString)_\(id)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(compoundID)
    }

    static func == (lhs: Series, rhs: Series) -> Bool {
        lhs.compoundID == rhs.compoundID
    }
}

// MARK: - Episode

/// An episode belonging to a TV show season.
struct Episode: Identifiable, Hashable, Codable {
    let id: String
    let seriesID: String
    let sourceID: UUID
    let seasonNumber: Int
    let episodeNumber: Int
    let title: String
    let streamURL: URL
    let containerExtension: String?
    let durationSecs: Int?
    let formattedDuration: String?
    let plot: String?

    var compoundID: String {
        "\(sourceID.uuidString)_\(seriesID)_\(id)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(compoundID)
    }

    static func == (lhs: Episode, rhs: Episode) -> Bool {
        lhs.compoundID == rhs.compoundID
    }
}

// MARK: - Flexible Decoding Helpers for VOD

struct VODFlexibleString: Codable {
    let value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            value = str
        } else if let intVal = try? container.decode(Int.self) {
            value = String(intVal)
        } else if let dbl = try? container.decode(Double.self) {
            value = String(dbl)
        } else {
            value = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct VODFlexibleInt: Codable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let str = try? container.decode(String.self), let parsed = Int(str.trimmingCharacters(in: .whitespaces)) {
            value = parsed
        } else if let dbl = try? container.decode(Double.self) {
            value = Int(dbl)
        } else {
            value = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct VODFlexibleDouble: Codable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dbl = try? container.decode(Double.self) {
            value = dbl
        } else if let intVal = try? container.decode(Int.self) {
            value = Double(intVal)
        } else if let str = try? container.decode(String.self), let parsed = Double(str.trimmingCharacters(in: .whitespaces)) {
            value = parsed
        } else {
            value = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - Xtream API VOD Stream DTO

struct XtreamVODStream: Codable {
    let num: Int?
    let name: String?
    let streamType: String?
    let streamID: Int?
    let streamIcon: String?
    let rating: Double?
    let rating5based: Double?
    let added: String?
    let categoryID: String?
    let containerExtension: String?

    enum CodingKeys: String, CodingKey {
        case num
        case name
        case streamType = "stream_type"
        case streamID = "stream_id"
        case streamIcon = "stream_icon"
        case rating
        case rating5based = "rating_5based"
        case added
        case categoryID = "category_id"
        case containerExtension = "container_extension"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        num = (try? container.decode(VODFlexibleInt.self, forKey: .num))?.value
        name = try? container.decode(String.self, forKey: .name)
        streamType = try? container.decode(String.self, forKey: .streamType)
        streamID = (try? container.decode(VODFlexibleInt.self, forKey: .streamID))?.value
        streamIcon = try? container.decode(String.self, forKey: .streamIcon)
        rating = (try? container.decode(VODFlexibleDouble.self, forKey: .rating))?.value
        rating5based = (try? container.decode(VODFlexibleDouble.self, forKey: .rating5based))?.value
        added = (try? container.decode(VODFlexibleString.self, forKey: .added))?.value
        categoryID = (try? container.decode(VODFlexibleString.self, forKey: .categoryID))?.value
        containerExtension = try? container.decode(String.self, forKey: .containerExtension)
    }
}

// MARK: - Xtream API Series Item DTO

struct XtreamSeriesItem: Codable {
    let seriesID: Int?
    let name: String?
    let cover: String?
    let plot: String?
    let cast: String?
    let director: String?
    let genre: String?
    let releaseDate: String?
    let rating: Double?
    let rating5based: Double?
    let episodeRunTime: String?
    let categoryID: String?
    let backdropPath: [String]?

    enum CodingKeys: String, CodingKey {
        case seriesID = "series_id"
        case name
        case cover
        case plot
        case cast
        case director
        case genre
        case releaseDate = "releaseDate"
        case rating
        case rating5based = "rating_5based"
        case episodeRunTime = "episode_run_time"
        case categoryID = "category_id"
        case backdropPath = "backdrop_path"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        seriesID = (try? container.decode(VODFlexibleInt.self, forKey: .seriesID))?.value
        name = try? container.decode(String.self, forKey: .name)
        cover = try? container.decode(String.self, forKey: .cover)
        plot = try? container.decode(String.self, forKey: .plot)
        cast = try? container.decode(String.self, forKey: .cast)
        director = try? container.decode(String.self, forKey: .director)
        genre = try? container.decode(String.self, forKey: .genre)
        releaseDate = (try? container.decode(VODFlexibleString.self, forKey: .releaseDate))?.value
        rating = (try? container.decode(VODFlexibleDouble.self, forKey: .rating))?.value
        rating5based = (try? container.decode(VODFlexibleDouble.self, forKey: .rating5based))?.value
        episodeRunTime = (try? container.decode(VODFlexibleString.self, forKey: .episodeRunTime))?.value
        categoryID = (try? container.decode(VODFlexibleString.self, forKey: .categoryID))?.value

        // backdrop_path can be an array of strings, a single string, or null
        if let array = try? container.decode([String].self, forKey: .backdropPath) {
            backdropPath = array
        } else if let single = try? container.decode(String.self, forKey: .backdropPath), !single.isEmpty {
            backdropPath = [single]
        } else {
            backdropPath = nil
        }
    }
}

// MARK: - Xtream API Series Info & Episodes DTO

struct XtreamSeriesInfoResponse: Codable {
    let episodes: [String: [XtreamEpisodeItem]]?

    enum CodingKeys: String, CodingKey {
        case episodes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // episodes is typically {"1": [...], "2": [...]}
        // but if empty, some servers return []
        if let dict = try? container.decode([String: [XtreamEpisodeItem]].self, forKey: .episodes) {
            episodes = dict
        } else {
            episodes = nil
        }
    }
}

struct XtreamEpisodeItem: Codable {
    let id: String?
    let episodeNum: Int?
    let title: String?
    let containerExtension: String?
    let season: Int?
    let info: XtreamEpisodeInfo?

    enum CodingKeys: String, CodingKey {
        case id
        case episodeNum = "episode_num"
        case title
        case containerExtension = "container_extension"
        case season
        case info
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = (try? container.decode(VODFlexibleString.self, forKey: .id))?.value
        episodeNum = (try? container.decode(VODFlexibleInt.self, forKey: .episodeNum))?.value
        title = try? container.decode(String.self, forKey: .title)
        containerExtension = try? container.decode(String.self, forKey: .containerExtension)
        season = (try? container.decode(VODFlexibleInt.self, forKey: .season))?.value
        info = try? container.decode(XtreamEpisodeInfo.self, forKey: .info)
    }
}

struct XtreamEpisodeInfo: Codable {
    let durationSecs: Int?
    let duration: String?
    let plot: String?

    enum CodingKeys: String, CodingKey {
        case durationSecs = "duration_secs"
        case duration
        case plot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        durationSecs = (try? container.decode(VODFlexibleInt.self, forKey: .durationSecs))?.value
        duration = (try? container.decode(VODFlexibleString.self, forKey: .duration))?.value
        plot = try? container.decode(String.self, forKey: .plot)
    }
}

// MARK: - Catalogue Metadata Helpers

/// Year parsing, shared by movies (from the title) and series (from
/// `releaseDate`). Compiled once — these run across whole catalogues.
enum VODMetadata {
    /// Matches a plausible release year. Deliberately not anchored: movie titles
    /// carry the year inline, e.g. "Back in Action 2025 (Multi)".
    static let yearPattern = try? NSRegularExpression(pattern: "(19\\d{2}|20\\d{2})")

    /// Last 4-digit year in the string. Series `releaseDate` arrives in several
    /// shapes — "2026-03-27", "2024-2026", "1989-2011", "2021" — and for a range
    /// the later year is the more useful one to filter on.
    static func year(in text: String?) -> Int? {
        guard let text, let yearPattern else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = yearPattern.matches(in: text, range: range)
        guard let last = matches.last, let r = Range(last.range, in: text) else { return nil }
        return Int(text[r])
    }

    /// Clamps a provider rating onto 0...10, discarding the unusable.
    ///
    /// Ratings are nominally out of 10, but this catalogue contains values as
    /// high as 57 — and roughly 13% of titles report 0, meaning "unrated"
    /// rather than "terrible".
    static func normalizedRating(_ raw: Double?) -> Double? {
        guard let raw, raw > 0, raw <= 10 else { return nil }
        return raw
    }
}

extension Movie {
    /// Rating on 0...10, or nil when absent or out of range.
    var normalizedRating: Double? { VODMetadata.normalizedRating(rating) }

    /// Release year, parsed from the title — the provider sends no year field
    /// for movies. Present on roughly 62% of this catalogue.
    var year: Int? { VODMetadata.year(in: name) }

    /// When the provider added this title, from its Unix timestamp string.
    var addedDate: Date? {
        guard let added, let seconds = TimeInterval(added) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

extension Series {
    var normalizedRating: Double? { VODMetadata.normalizedRating(rating) }

    var year: Int? { VODMetadata.year(in: releaseDate) }

    /// Genres split from the provider's comma-separated list.
    var genreList: [String] {
        (genre ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
