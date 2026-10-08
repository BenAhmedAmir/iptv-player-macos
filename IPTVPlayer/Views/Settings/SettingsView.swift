import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @State private var showClearCacheConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Settings")
                    .font(.title2.bold())

                // Appearance
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Appearance")
                            .font(.headline)

                        Picker("Theme", selection: $settingsVM.appearance) {
                            ForEach(AppAppearance.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 300)
                        .onChange(of: settingsVM.appearance) { newValue in
                            settingsVM.saveAppearance(newValue)
                        }
                    }
                    .padding(8)
                }

                // Cache
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cache")
                            .font(.headline)

                        Text("Clear the image cache to free up disk space.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)

                        Button("Clear Image Cache") {
                            showClearCacheConfirm = true
                        }
                        .alert("Clear Cache", isPresented: $showClearCacheConfirm) {
                            Button("Cancel", role: .cancel) {}
                            Button("Clear", role: .destructive) {
                                settingsVM.clearImageCache()
                            }
                        } message: {
                            Text("This will remove all cached channel logos. They will be re-downloaded as needed.")
                        }
                    }
                    .padding(8)
                }

                // About
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About")
                            .font(.headline)

                        HStack {
                            Text("IPTV Player")
                            Spacer()
                            Text("Version 1.0.0")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Platform")
                            Spacer()
                            Text("macOS · Apple Silicon")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
