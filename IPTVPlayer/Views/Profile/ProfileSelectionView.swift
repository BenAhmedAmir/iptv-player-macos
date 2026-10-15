import SwiftUI

// MARK: - Profile Selection View

/// "Who's watching?" picker.
struct ProfileSelectionView: View {
    @EnvironmentObject var profileVM: ProfileViewModel

    @State private var isCreating = false
    @State private var hoveredProfile: UUID?
    @State private var profileToDelete: Profile?
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 44) {
            Text("Who's watching?")
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.6)
                .foregroundColor(Theme.textPrimary)

            HStack(alignment: .top, spacing: 40) {
                ForEach(profileVM.profiles) { profile in
                    ProfileCard(
                        profile: profile,
                        sourceCount: profileVM.sourceCount(for: profile),
                        isHovered: hoveredProfile == profile.id
                    )
                    .onTapGesture { profileVM.selectProfile(profile) }
                    .onHover { hoveredProfile = $0 ? profile.id : nil }
                    .contextMenu {
                        Button("Rename…") {
                            profileVM.profileToRename = profile
                            profileVM.isShowingRenameProfile = true
                        }
                        Divider()
                        Button("Delete…", role: .destructive) {
                            profileToDelete = profile
                            showDeleteConfirm = true
                        }
                    }
                }

                addProfileButton
            }

            Text("Each profile keeps its own sources, favorites and watch history.")
                .font(.system(size: 13))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backdrop)
        .sheet(isPresented: $isCreating) {
            CreateProfileSheet(isPresented: $isCreating) { name, colorID, isKids in
                profileVM.createProfile(name: name, avatarColorID: colorID, isKids: isKids)
            }
        }
        .sheet(isPresented: $profileVM.isShowingRenameProfile) {
            if let profile = profileVM.profileToRename {
                RenameSheet(
                    title: "Rename Profile",
                    currentName: profile.name,
                    isPresented: $profileVM.isShowingRenameProfile
                ) { newName in
                    profileVM.renameProfile(profile, to: newName)
                }
            }
        }
        .confirmationDialog(
            "Delete “\(profileToDelete?.name ?? "")”?",
            isPresented: $showDeleteConfirm
        ) {
            Button("Delete Profile", role: .destructive) {
                if let profile = profileToDelete {
                    profileVM.deleteProfile(profile)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its sources, favorites and watch history are removed. This cannot be undone.")
        }
    }

    /// Soft wash behind the picker, tuned per appearance.
    private var backdrop: some View {
        RadialGradient(
            colors: [Theme.surfaceRaised, Theme.backdrop],
            center: UnitPoint(x: 0.5, y: 0.3),
            startRadius: 0,
            endRadius: 700
        )
        .ignoresSafeArea()
    }

    /// Dashed placeholder matching the avatar footprint so the row stays aligned.
    private var addProfileButton: some View {
        Button {
            isCreating = true
        } label: {
            VStack(spacing: 14) {
                Circle()
                    .strokeBorder(
                        Theme.textTertiary.opacity(0.5),
                        style: StrokeStyle(lineWidth: 2, dash: [6, 5])
                    )
                    .frame(width: 128, height: 128)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 40, weight: .thin))
                            .foregroundColor(Theme.textSecondary)
                    )
                Text("Add Profile")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                Text(" ")
                    .font(.system(size: 12))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profile Card

struct ProfileCard: View {
    let profile: Profile
    let sourceCount: Int
    let isHovered: Bool

    var body: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(AvatarPalette.gradient(for: profile.avatarColorID))
                .frame(width: 128, height: 128)
                .overlay(
                    Text(profile.name.prefix(1).uppercased())
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundColor(.white)
                )
                .overlay(alignment: .bottomTrailing) {
                    if profile.isRestricted {
                        Image(systemName: "figure.and.child.holdinghands")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(7)
                            .background(Circle().fill(Theme.accent))
                            .overlay(Circle().stroke(Theme.backdrop, lineWidth: 3))
                    }
                }
                .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                .opacity(isHovered ? 0.85 : 1)

            Text(profile.name)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)

            // Kids profiles say so; everyone else gets their source count.
            Text(profile.isRestricted
                 ? "Restricted"
                 : (sourceCount == 1 ? "1 source" : "\(sourceCount) sources"))
                .font(.system(size: 12))
                .foregroundColor(profile.isRestricted ? Theme.accent : Theme.textTertiary)
        }
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Create Profile Sheet

/// Name, avatar colour and the kids toggle.
struct CreateProfileSheet: View {
    @Binding var isPresented: Bool
    /// name, avatar swatch id, isKids
    let onCreate: (String, String, Bool) -> Void

    @State private var name = ""
    @State private var colorID = AvatarPalette.swatches[0].id
    @State private var isKids = false
    @FocusState private var isFocused: Bool

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Create Profile")
                .font(.system(size: 17, weight: .semibold))

            HStack(spacing: 16) {
                Circle()
                    .fill(AvatarPalette.gradient(for: colorID))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Text(name.isEmpty ? "?" : name.prefix(1).uppercased())
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                    TextField("e.g. Alex", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($isFocused)
                        .onSubmit { if canCreate { create() } }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Avatar colour")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)

                HStack(spacing: 10) {
                    ForEach(AvatarPalette.swatches, id: \.id) { swatch in
                        Button {
                            colorID = swatch.id
                        } label: {
                            Circle()
                                .fill(swatch.color)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(Theme.textPrimary, lineWidth: colorID == swatch.id ? 2.5 : 0)
                                        .padding(-3)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(swatch.id.capitalized)
                    }
                }
            }

            Toggle(isOn: $isKids) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kids profile")
                    Text("Hides adult categories and shows a “Restricted” caption.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
            }
            .toggleStyle(.switch)

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear { isFocused = true }
    }

    private func create() {
        onCreate(name, colorID, isKids)
        isPresented = false
    }
}

// MARK: - Rename Sheet

struct RenameSheet: View {
    let title: String
    let currentName: String
    @Binding var isPresented: Bool
    let onRename: (String) -> Void

    @State private var name: String = ""
    @FocusState private var isFocused: Bool

    private var canRename: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != currentName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { if canRename { rename() } }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { rename() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRename)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            name = currentName
            isFocused = true
        }
    }

    private func rename() {
        onRename(name)
        isPresented = false
    }
}

// MARK: - Previews

struct ProfileSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ProfileSelectionView()
                .previewDisplayName("Profiles — Dark")
                .preferredColorScheme(.dark)

            ProfileSelectionView()
                .previewDisplayName("Profiles — Light")
                .preferredColorScheme(.light)
        }
        .environmentObject(ProfileViewModel())
        .frame(width: 900, height: 560)
    }
}

struct ProfileSheets_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CreateProfileSheet(isPresented: .constant(true)) { _, _, _ in }
                .previewDisplayName("Create Profile — Dark")
                .preferredColorScheme(.dark)

            CreateProfileSheet(isPresented: .constant(true)) { _, _, _ in }
                .previewDisplayName("Create Profile — Light")
                .preferredColorScheme(.light)

            RenameSheet(title: "Rename Profile", currentName: "Alex", isPresented: .constant(true)) { _ in }
                .previewDisplayName("Rename — Dark")
                .preferredColorScheme(.dark)
        }
    }
}
