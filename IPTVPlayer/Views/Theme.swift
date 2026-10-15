import SwiftUI
import AppKit

// MARK: - Design Tokens

/// Colours, radii and metrics for the IPTVPlayer redesign.
///
/// Every colour resolves per appearance. The spec's values are the dark side;
/// each one carries a light counterpart so the same token works in both, rather
/// than the app pinning itself to dark. Accents are deliberately identical in
/// both appearances — there is one blue, and red is reserved for LIVE.
enum Theme {

    // MARK: Surfaces

    /// Page backdrop behind the window.
    static let backdrop = Color.adaptive(dark: 0x111214, light: 0xECECEE)
    /// Main content background.
    static let surface = Color.adaptive(dark: 0x1C1C1F, light: 0xFFFFFF)
    /// Sidebar and raised cards.
    static let surfaceRaised = Color.adaptive(dark: 0x26262A, light: 0xF4F4F6)
    /// Card hover state.
    static let surfaceHover = Color.adaptive(dark: 0x2E2E33, light: 0xE8E8EC)
    /// Inspector / detail column.
    static let surfaceInspector = Color.adaptive(dark: 0x202024, light: 0xFAFAFC)
    /// Modal sheets.
    static let surfaceSheet = Color.adaptive(dark: 0x252528, light: 0xFFFFFF)
    /// Elevated dialogs (Add Source).
    static let surfaceDialog = Color.adaptive(dark: 0x2A2A2E, light: 0xFFFFFF)
    /// Segmented-control selection.
    static let surfaceSelected = Color.adaptive(dark: 0x4A4A50, light: 0xD8D8DE)

    // MARK: Text

    static let textPrimary = Color.adaptive(dark: 0xF5F5F7, light: 0x1C1C1F)
    static let textSecondary = Color.adaptive(dark: 0xA1A1A6, light: 0x6E6E73)
    static let textTertiary = Color.adaptive(dark: 0x8E8E93, light: 0x8E8E93)
    static let textOnAccent = Color.white

    // MARK: Accents

    /// The single accent. Used for selection, primary actions and progress.
    static let accent = Color(hex: 0x0A84FF)
    /// LIVE badges and the "now" marker only — never for emphasis.
    static let live = Color(hex: 0xFF453A)
    static let star = Color(hex: 0xFFD60A)
    static let ok = Color(hex: 0x30D158)
    /// Warnings only.
    static let warning = Color(hex: 0xFF9F0A)
    static let destructive = Color.adaptive(dark: 0xFF6961, light: 0xD70015)

    // MARK: Hairlines and fills

    /// Divider between header and content, and between columns.
    static let separator = Color.adaptiveOpacity(dark: (.white, 0.07), light: (.black, 0.09))
    /// Lighter rule used between list rows.
    static let separatorFaint = Color.adaptiveOpacity(dark: (.white, 0.04), light: (.black, 0.05))
    /// Field and secondary-button fill.
    static let fill = Color.adaptiveOpacity(dark: (.white, 0.08), light: (.black, 0.05))
    static let fillStrong = Color.adaptiveOpacity(dark: (.white, 0.10), light: (.black, 0.08))
    /// Selected sidebar row.
    static let fillSelected = Color.adaptiveOpacity(dark: (.white, 0.12), light: (.black, 0.07))
    /// Hairline around artwork tiles.
    static let tileBorder = Color.adaptiveOpacity(dark: (.white, 0.06), light: (.black, 0.08))
    /// Selected channel row in the live list.
    static let rowSelected = Color(hex: 0x0A84FF).opacity(0.24)
    /// Progress track behind a filled bar.
    static let track = Color.adaptiveOpacity(dark: (.white, 0.12), light: (.black, 0.10))
    /// Skeleton placeholder fill.
    static let skeleton = Color.adaptiveOpacity(dark: (.white, 0.07), light: (.black, 0.06))

    // MARK: Metrics

    enum Metrics {
        static let sidebarWidth: CGFloat = 232
        static let headerHeight: CGFloat = 52
        static let categoryColumnWidth: CGFloat = 220
        static let inspectorWidth: CGFloat = 330
        static let navRowHeight: CGFloat = 30
        static let searchWidth: CGFloat = 240
        static let fieldHeight: CGFloat = 28
        /// Smallest poster column before the grid reflows.
        static let posterMinWidth: CGFloat = 140
    }

    /// Continuous corner radii, 8–12pt for containers.
    enum Radius {
        static let small: CGFloat = 6
        static let field: CGFloat = 7
        static let tile: CGFloat = 8
        static let card: CGFloat = 10
        static let panel: CGFloat = 12
        static let sheet: CGFloat = 14
        static let pill: CGFloat = 999
    }
}

// MARK: - Adaptive Colours

extension Color {
    /// Builds a colour from a 0xRRGGBB literal, so design values can be
    /// transcribed exactly as written in the spec.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Resolves per appearance via `NSColor`, so a single token is correct in
    /// both light and dark without the view needing to know which is active.
    static func adaptive(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }

    /// Appearance-dependent translucent fill — dark surfaces lift with white,
    /// light surfaces recede with black, and the opacities differ.
    static func adaptiveOpacity(
        dark: (base: Color, opacity: Double),
        light: (base: Color, opacity: Double)
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let pair = appearance.isDark ? dark : light
            return NSColor(pair.base).withAlphaComponent(pair.opacity)
        })
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Identity Colours

/// Deterministic per-item colours for logo tiles and artwork placeholders.
///
/// Hashing the name keeps a given channel the same colour between launches; the
/// design's index-based hue would re-colour everything whenever a list reorders.
enum IdentityColor {
    static func hue(for key: String) -> Double {
        var hash: UInt64 = 5381
        for byte in key.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return Double(hash % 360)
    }

    /// Flat tile fill, as used behind channel initials.
    static func tile(for key: String) -> Color {
        Color(hue: hue(for: key) / 360, saturation: 0.42, brightness: 0.62)
    }

    /// Diagonal gradient for poster and preview placeholders.
    static func artwork(for key: String) -> LinearGradient {
        let h = hue(for: key) / 360
        return LinearGradient(
            colors: [
                Color(hue: h, saturation: 0.38, brightness: 0.50),
                Color(hue: (h + 0.12).truncatingRemainder(dividingBy: 1),
                      saturation: 0.30, brightness: 0.20)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Up to three initials, matching the design's channel-logo treatment.
    static func initials(for name: String) -> String {
        let words = name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let letters = words.map { word -> String in
            word.rangeOfCharacter(from: .decimalDigits) != nil ? word : String(word.prefix(1))
        }
        return String(letters.joined().prefix(3)).uppercased()
    }
}

// MARK: - Avatar Palette

/// The six profile swatches offered when creating a profile.
enum AvatarPalette {
    static let swatches: [(id: String, color: Color)] = [
        ("blue", Color(hex: 0x0A84FF)),
        ("purple", Color(hex: 0xBF5AF2)),
        ("pink", Color(hex: 0xFF375F)),
        ("orange", Color(hex: 0xFF9F0A)),
        ("green", Color(hex: 0x30D158)),
        ("teal", Color(hex: 0x40C8E0))
    ]

    static func color(for id: String?) -> Color {
        swatches.first { $0.id == id }?.color ?? swatches[0].color
    }

    /// Gradient used on the large picker avatars.
    static func gradient(for id: String?) -> LinearGradient {
        let base = color(for: id)
        return LinearGradient(
            colors: [base.opacity(0.95), base.opacity(0.65)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
