import Foundation

// MARK: - Catalogue Tab

/// Movies and TV Shows keep separate browsing state.
enum CatalogueTab: String, Codable {
    case movies, series

    var allLabel: String {
        self == .movies ? "All Movies" : "All TV Shows"
    }

    var itemNoun: String {
        self == .movies ? "titles" : "shows"
    }
}

// MARK: - Category Selection

/// What the sidebar currently has selected.
///
/// The three virtual rows sit alongside real provider categories, so selection
/// is one value rather than a category plus a set of mode flags.
enum CategorySelection: Codable, Hashable {
    case all
    case continueWatching
    case recentlyAdded
    case category(id: String)

    var categoryID: String? {
        if case .category(let id) = self { return id }
        return nil
    }
}

// MARK: - Filters

/// Minimum provider rating, on the 0–10 scale.
enum RatingFilter: String, Codable, CaseIterable, Identifiable {
    case any, six, seven, eight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: return "Any"
        case .six: return "6+"
        case .seven: return "7+"
        case .eight: return "8+"
        }
    }

    var threshold: Double? {
        switch self {
        case .any: return nil
        case .six: return 6
        case .seven: return 7
        case .eight: return 8
        }
    }
}

/// Release-year buckets, rolling off the current year so they never go stale.
enum YearFilter: String, Codable, CaseIterable, Identifiable {
    case any, thisYear, lastYear, twoYearsAgo, midRange, older

    var id: String { rawValue }

    private static var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    var label: String {
        let year = Self.currentYear
        switch self {
        case .any: return "Any"
        case .thisYear: return String(year)
        case .lastYear: return String(year - 1)
        case .twoYearsAgo: return String(year - 2)
        case .midRange: return "\(year - 5)–\(year - 3)"
        case .older: return "Before \(year - 5)"
        }
    }

    /// Inclusive range a title's year must fall within, or nil for "Any".
    var range: ClosedRange<Int>? {
        let year = Self.currentYear
        switch self {
        case .any: return nil
        case .thisYear: return year...year
        case .lastYear: return (year - 1)...(year - 1)
        case .twoYearsAgo: return (year - 2)...(year - 2)
        case .midRange: return (year - 5)...(year - 3)
        case .older: return Int.min...(year - 6)
        }
    }
}

/// How recently the provider added the title.
enum AddedFilter: String, Codable, CaseIterable, Identifiable {
    case any, week, month, quarter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: return "Any"
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        case .quarter: return "Last 3 months"
        }
    }

    var days: Int? {
        switch self {
        case .any: return nil
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        }
    }

    var cutoff: Date? {
        guard let days else { return nil }
        return Calendar.current.date(byAdding: .day, value: -days, to: Date())
    }
}

/// Sort orders offered for both tabs.
enum CatalogueSort: String, Codable, CaseIterable, Identifiable {
    case dateAdded, titleAscending, releaseYear, rating

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dateAdded: return "Date Added"
        case .titleAscending: return "Title A–Z"
        case .releaseYear: return "Release Year"
        case .rating: return "Rating"
        }
    }
}

/// The filter set applied on top of the selected category and search.
struct CatalogueFilters: Codable, Equatable {
    var rating: RatingFilter = .any
    var year: YearFilter = .any
    var added: AddedFilter = .any
    var hideWatched: Bool = false
    var sort: CatalogueSort = .dateAdded

    /// Sort is deliberately excluded: it is always set to something, so counting
    /// it would leave the badge permanently at one.
    var activeCount: Int {
        var count = 0
        if rating != .any { count += 1 }
        if year != .any { count += 1 }
        if added != .any { count += 1 }
        if hideWatched { count += 1 }
        return count
    }

    var isActive: Bool { activeCount > 0 }

    static let none = CatalogueFilters()
}

// MARK: - Persisted Preferences

/// Per-profile, per-tab browsing state.
struct CataloguePreferences: Codable {
    var selection: CategorySelection = .all
    var pinnedCategoryIDs: [String] = []
    var expandedGroups: [String] = []
    var filters: CatalogueFilters = .none
    /// When the catalogue was last pulled from the provider, so the header can
    /// say how stale it is.
    var lastRefreshedAt: Date?

    static let `default` = CataloguePreferences()
}

// MARK: - Category Grouping

/// Splits a provider category name into a group prefix and a short label.
///
/// Providers namespace categories like "FR | Comedy", "EN - Action" or
/// "VOD:Drama". Grouping on that prefix turns a flat list of 200+ into
/// something navigable; anything without one lands in OTHER.
enum CategoryNaming {
    private static let separators = [" | ", " - ", " — ", ":", "|", "-"]

    static let fallbackGroup = "OTHER"

    /// ("FR", "Comedy") for "FR | Comedy"; (OTHER, name) when there is no prefix.
    static func split(_ fullName: String) -> (group: String, label: String) {
        let trimmed = fullName.trimmingCharacters(in: .whitespaces)

        for separator in separators {
            guard let range = trimmed.range(of: separator) else { continue }
            let prefix = trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let remainder = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)

            // A long prefix is a title, not a namespace — "Documentary - The Deep"
            // should not become its own group.
            guard !prefix.isEmpty, !remainder.isEmpty, prefix.count <= 12 else { continue }
            return (prefix.uppercased(), remainder)
        }
        return (fallbackGroup, trimmed)
    }

    static func group(of fullName: String) -> String { split(fullName).group }
    static func label(of fullName: String) -> String { split(fullName).label }

    /// Group expanded by default: the one matching the system language, else EN,
    /// else the largest.
    static func defaultExpandedGroup(from groups: [String]) -> String? {
        guard !groups.isEmpty else { return nil }

        let language = (Locale.current.language.languageCode?.identifier ?? "en").uppercased()
        if groups.contains(language) { return language }
        if groups.contains("EN") { return "EN" }
        return groups.first
    }
}

// MARK: - Title Cleaning

/// Strips provider bookkeeping out of series and episode titles.
///
/// Panels prefix and suffix titles with language tags, year ranges and SxxExx
/// markers that are already shown elsewhere in the UI. Removing them leaves the
/// part a viewer actually reads.
enum TitleCleaner {

    /// `(?i)s\d{1,2}\s*[.\-]?\s*e\d{1,3}` — S01E03, s1.e3, S1 - E12.
    private static let episodeMarker = try? NSRegularExpression(
        pattern: "s\\d{1,2}\\s*[.\\-]?\\s*e\\d{1,3}",
        options: .caseInsensitive
    )

    /// "(2019-2023)", "(2021)" and bare "(EN)" / "(4K)" style tags.
    private static let parenthetical = try? NSRegularExpression(
        pattern: "\\((?:19|20)\\d{2}(?:\\s*-\\s*(?:19|20)\\d{2})?\\)|\\([A-Za-z0-9]{1,4}\\)",
        options: .caseInsensitive
    )

    /// Language or quality markers providers bolt onto names.
    private static let knownTags: Set<String> = [
        "EN", "FR", "DE", "ES", "IT", "AR", "PT", "NL", "RU", "TR", "PL",
        "VF", "VO", "VOSTFR", "MULTI", "4K", "HD", "FHD", "UHD", "SD"
    ]

    // MARK: Series

    /// Splits a series name into an optional badge and the display title.
    ///
    /// "DE | Dark (2017-2020)" → (badge "DE", title "Dark").
    static func series(_ raw: String) -> (badge: String?, title: String) {
        var working = raw.trimmingCharacters(in: .whitespaces)
        var badge: String?

        // Leading namespace, e.g. "DE | Dark" or "FR - Lupin".
        let split = CategoryNaming.split(working)
        if split.group != CategoryNaming.fallbackGroup, knownTags.contains(split.group) {
            badge = split.group
            working = split.label
        }

        // Trailing "(EN)" style tag, if no prefix supplied one.
        if badge == nil,
           let match = working.range(of: "\\(([A-Za-z0-9]{1,6})\\)\\s*$", options: .regularExpression) {
            let inner = working[match]
                .trimmingCharacters(in: CharacterSet(charactersIn: "() "))
                .uppercased()
            if knownTags.contains(inner) {
                badge = inner
                working.removeSubrange(match)
            }
        }

        working = removeMatches(of: parenthetical, in: working)
        return (badge, tidy(working, fallback: raw))
    }

    // MARK: Episodes

    /// Cleans an episode title, falling back to "Episode N".
    ///
    /// Many panels name every episode after the show, which reads as a column of
    /// identical rows once the number is already shown beside it.
    static func episode(_ raw: String?, seriesName: String, number: Int) -> String {
        let fallback = "Episode \(number)"
        guard var working = raw?.trimmingCharacters(in: .whitespaces), !working.isEmpty else {
            return fallback
        }

        working = removeMatches(of: episodeMarker, in: working)
        working = removeMatches(of: parenthetical, in: working)

        // Drop the series name wherever it appears.
        let (_, cleanSeries) = series(seriesName)
        for candidate in [cleanSeries, seriesName] where !candidate.isEmpty {
            working = working.replacingOccurrences(
                of: candidate, with: "", options: [.caseInsensitive]
            )
        }

        // Any remaining standalone tag word.
        let words = working
            .components(separatedBy: CharacterSet(charactersIn: " _"))
            .filter { !knownTags.contains($0.uppercased()) }
        working = words.joined(separator: " ")

        let cleaned = tidy(working, fallback: "")
        // A bare number left behind is the episode number repeating itself.
        if cleaned.isEmpty || Int(cleaned) != nil { return fallback }
        return cleaned
    }

    // MARK: Duration

    /// "1h 21m", or "47m" under an hour.
    static func duration(seconds: Int?, fallback: String?) -> String {
        guard let seconds, seconds > 0 else {
            return fallback?.trimmingCharacters(in: .whitespaces) ?? ""
        }
        let minutes = seconds / 60
        guard minutes >= 60 else { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    // MARK: Helpers

    private static func removeMatches(of regex: NSRegularExpression?, in text: String) -> String {
        guard let regex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
    }

    /// Collapses whitespace and trims leftover separators.
    private static func tidy(_ text: String, fallback: String) -> String {
        var result = text.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        )
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: " -–—_|:·.,"))
        return result.isEmpty ? fallback : result
    }
}
