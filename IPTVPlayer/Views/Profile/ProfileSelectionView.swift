import SwiftUI

// MARK: - Profile Selection View

/// Full-screen profile picker shown on launch or when switching profiles.
struct ProfileSelectionView: View {
    @EnvironmentObject var profileVM: ProfileViewModel
    @State private var newName = ""
    @State private var isCreating = false
    @State private var hoveredProfile: UUID?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Title
            VStack(spacing: 8) {
                Image(systemName: "tv")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                Text("IPTV Player")
                    .font(.system(size: 32, weight: .bold, design: .rounded))

                Text("Who's watching?")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 40)

            // Profile grid
            if !profileVM.profiles.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 20)], spacing: 20) {
                    ForEach(profileVM.profiles) { profile in
                        ProfileCard(
                            profile: profile,
                            isHovered: hoveredProfile == profile.id
                        )
                        .onTapGesture {
                            profileVM.selectProfile(profile)
                        }
                        .onHover { isHovering in
                            hoveredProfile = isHovering ? profile.id : nil
                        }
                        .contextMenu {
                            Button("Rename") {
                                profileVM.profileToRename = profile
                                newName = profile.name
                                profileVM.isShowingRenameProfile = true
                            }

                            Divider()

                            Button("Delete", role: .destructive) {
                                profileVM.deleteProfile(profile)
                            }
                        }
                    }
                }
                .padding(.horizontal, 60)
            }

            // Add profile button
            Button {
                isCreating = true
                newName = ""
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                    Text("Add Profile")
                        .font(.headline)
                }
                .foregroundColor(.blue)
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 30)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $isCreating) {
            CreateProfileSheet(isPresented: $isCreating) { name in
                profileVM.createProfile(name: name)
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
    }
}

// MARK: - Profile Card

struct ProfileCard: View {
    let profile: Profile
    let isHovered: Bool

    private let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .teal]

    private var profileColor: Color {
        colors[abs(profile.name.hashValue) % colors.count]
    }

    var body: some View {
        VStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(profileColor.gradient)
                    .frame(width: 80, height: 80)

                Text(profile.name.prefix(1).uppercased())
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .shadow(color: profileColor.opacity(isHovered ? 0.5 : 0.2), radius: isHovered ? 12 : 4)
            .scaleEffect(isHovered ? 1.08 : 1.0)

            Text(profile.name)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
    }
}

// MARK: - Create Profile Sheet

struct CreateProfileSheet: View {
    @Binding var isPresented: Bool
    let onCreate: (String) -> Void
    @State private var name = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("Create Profile")
                .font(.title2.bold())

            TextField("Profile name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .frame(width: 280)
                .onSubmit {
                    if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        onCreate(name)
                        isPresented = false
                    }
                }

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    onCreate(name)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(30)
        .frame(width: 360)
        .onAppear { isFocused = true }
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

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.title2.bold())

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .frame(width: 280)
                .onSubmit {
                    if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        onRename(name)
                        isPresented = false
                    }
                }

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    onRename(name)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(30)
        .frame(width: 360)
        .onAppear {
            name = currentName
            isFocused = true
        }
    }
}
