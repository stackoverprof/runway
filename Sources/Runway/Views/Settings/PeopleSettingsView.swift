import SwiftUI
import AppKit

struct PeopleSettings: View {
    @Bindable var feed = GitHubFeed.shared
    @State private var selectedPersonLogin: String?
    @State private var knownLogins: Set<String> = []
    @State private var editingDisplayName = ""

    private var manager = PersonProfileManager.shared

    var body: some View {
        VStack(spacing: 0) {
            peopleList
            
            if let selected = selectedPersonLogin {
                let profile = manager.profiles.first { $0.login == selected } ?? PersonProfile(login: selected)
                Divider()
                editProfilePanel(for: selected, profile: profile)
            }
        }
        .frame(minHeight: 500)
        .onAppear {
            updateKnownLogins()
        }
        .onChange(of: selectedPersonLogin) { _, selected in
            if let selected, let profile = manager.profiles.first(where: { $0.login == selected }) {
                editingDisplayName = profile.displayName
            } else if let selected {
                editingDisplayName = selected
            }
        }
    }

    private var peopleList: some View {
        List(selection: $selectedPersonLogin) {
            if knownLogins.isEmpty {
                Text("People will appear here as they show up in the activity feed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                peopleListRows
            }
        }
        .listStyle(.inset)
    }

    private var peopleListRows: some View {
        ForEach(knownLogins.sorted(), id: \.self) { login in
            peopleRow(login: login)
        }
    }

    private func peopleRow(login: String) -> some View {
        let profile = manager.profiles.first { $0.login == login } ?? PersonProfile(login: login)
        return HStack(spacing: 10) {
            if let imageData = profile.imageData, let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(Color.gray.opacity(0.5), lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                Text("@\(login)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .tag(login)
    }

    private func editProfilePanel(for login: String, profile: PersonProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Profile")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                if let imageData = profile.imageData, let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 48, height: 48)
                        .overlay(Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Button("Upload Image") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.allowsMultipleSelection = false
                        panel.allowedContentTypes = [.image]
                        if panel.runModal() == .OK, let url = panel.url {
                            var updated = profile
                            updated.imageData = try? Data(contentsOf: url)
                            updateProfile(updated)
                        }
                    }
                    .font(.system(size: 11))
                    if profile.imageData != nil {
                        Button("Remove Image", role: .destructive) {
                            var updated = profile
                            updated.imageData = nil
                            updateProfile(updated)
                        }
                        .font(.system(size: 11))
                    }
                }
            }
            
            TextField("Display name", text: $editingDisplayName)
                .font(.system(size: 12))
                .textFieldStyle(.roundedBorder)
                .onChange(of: editingDisplayName) { _, newName in
                    var updated = profile
                    updated.displayName = newName
                    updateProfile(updated)
                }
        }
        .padding()
    }

    private func updateKnownLogins() {
        var logins = Set<String>()
        logins.formUnion(feed.events.map { $0.actor })
        logins.formUnion(feed.presence.map { $0.login })
        knownLogins = logins
    }

    private func updateProfile(_ profile: PersonProfile) {
        manager.updateProfile(profile)
    }
}
