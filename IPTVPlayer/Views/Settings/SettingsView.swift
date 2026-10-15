import SwiftUI

// MARK: - Settings View

/// Grouped preferences: appearance, playback defaults, cache and about.
struct SettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var playerVM: PlayerViewModel

    @AppStorage("defaultAudioLanguage") private var defaultAudioLanguage = PlaybackLanguage.auto.rawValue
    @AppStorage("defaultSubtitleLanguage") private var defaultSubtitleLanguage = PlaybackLanguage.off.rawValue

    @State private var cacheBytes: Int64 = 0
    @State private var showClearCacheConfirm = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: appearanceBinding) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Playback") {
                Picker("Default audio language", selection: $defaultAudioLanguage) {
                    ForEach(PlaybackLanguage.audioOptions) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }

                Picker("Default subtitle language", selection: $defaultSubtitleLanguage) {
                    ForEach(PlaybackLanguage.subtitleOptions) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }

                Picker("Subtitle text size", selection: subtitleSizeBinding) {
                    ForEach(PlayerViewModel.SubtitleSize.allCases) { size in
                        Text(size.longLabel).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                Text("Applied when a title offers more than one track. Live TV uses the stream's own tracks.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }

            Section("Cache") {
                LabeledContent("Artwork on disk") {
                    Text(formattedCacheSize)
                        .foregroundColor(Theme.textSecondary)
                        .monospacedDigit()
                }

                Button("Clear Cache…") {
                    showClearCacheConfirm = true
                }
                .disabled(cacheBytes == 0)

                Text("Posters and channel logos are re-downloaded as you browse.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }

            Section("About") {
                LabeledContent("Application", value: "IPTV Player")
                LabeledContent("Version", value: appVersion)
                LabeledContent("Platform", value: platformDescription)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: refreshCacheSize)
        .confirmationDialog(
            "Clear cached artwork?",
            isPresented: $showClearCacheConfirm
        ) {
            Button("Clear Cache", role: .destructive) {
                ImageCacheService.shared.clearCache()
                refreshCacheSize()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes \(formattedCacheSize) of posters and logos. Nothing else is affected.")
        }
    }

    // MARK: - Bindings

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { settingsVM.appearance },
            set: { settingsVM.saveAppearance($0) }
        )
    }

    private var subtitleSizeBinding: Binding<PlayerViewModel.SubtitleSize> {
        Binding(
            get: { playerVM.subtitleSize },
            set: { playerVM.setSubtitleSize($0) }
        )
    }

    // MARK: - Values

    private func refreshCacheSize() {
        cacheBytes = ImageCacheService.shared.diskCacheSize()
    }

    private var formattedCacheSize: String {
        guard cacheBytes > 0 else { return "Empty" }
        return ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private var platformDescription: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let arch = "Apple Silicon"
        #else
        let arch = "Intel"
        #endif
        return "macOS \(os.majorVersion).\(os.minorVersion) · \(arch)"
    }
}

// MARK: - Playback Language

/// Preferred track language, stored as a BCP-47 prefix.
///
/// A short curated list rather than every language: these are the defaults a
/// provider's catalogue realistically offers, and "Auto" covers the rest by
/// deferring to whatever the stream marks as default.
enum PlaybackLanguage: String, CaseIterable, Identifiable {
    case auto, off, english, french, arabic, spanish, german, italian, portuguese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto (stream default)"
        case .off: return "Off"
        case .english: return "English"
        case .french: return "French"
        case .arabic: return "Arabic"
        case .spanish: return "Spanish"
        case .german: return "German"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        }
    }

    /// Matched case-insensitively against a track's name.
    var matchTerms: [String] {
        switch self {
        case .auto, .off: return []
        case .english: return ["english", "eng", "en"]
        case .french: return ["french", "fre", "fra", "vf"]
        case .arabic: return ["arabic", "ara", "ar"]
        case .spanish: return ["spanish", "spa", "es"]
        case .german: return ["german", "ger", "deu", "de"]
        case .italian: return ["italian", "ita", "it"]
        case .portuguese: return ["portuguese", "por", "pt"]
        }
    }

    static var audioOptions: [PlaybackLanguage] {
        allCases.filter { $0 != .off }
    }

    static var subtitleOptions: [PlaybackLanguage] {
        allCases.filter { $0 != .auto }
    }
}

// MARK: - Previews

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SettingsView()
                .previewDisplayName("Settings — Dark")
                .preferredColorScheme(.dark)

            SettingsView()
                .previewDisplayName("Settings — Light")
                .preferredColorScheme(.light)
        }
        .environmentObject(SettingsViewModel())
        .environmentObject(PlayerViewModel())
        .frame(width: 540, height: 620)
    }
}
