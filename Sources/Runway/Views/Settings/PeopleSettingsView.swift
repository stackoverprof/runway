import SwiftUI
import AppKit

struct PeopleSettings: View {
    @State private var selectedPersonLogin: String?
    @State private var usernameDraft = ""
    @State private var fullNameDraft = ""
    @State private var draftSaveTask: Task<Void, Never>?
    private var manager = PersonProfileManager.shared

    var body: some View {
        VStack(spacing: 0) {
            peopleList
            
            if let selected = selectedPersonLogin {
                let profile = manager.profile(for: selected) ?? PersonProfile(login: selected)
                Divider()
                editProfilePanel(for: selected, profile: profile)
            }
        }
        .frame(minHeight: 500)
        .onAppear {
            GitHubFeed.discoverCachedPeople()
            PullRequests.discoverCachedPeople()
        }
        .onChange(of: usernameDraft) { _, _ in scheduleDraftSave() }
        .onChange(of: fullNameDraft) { _, _ in scheduleDraftSave() }
        .onDisappear { commitDrafts() }
    }

    private var peopleList: some View {
        List {
            if manager.profiles.isEmpty {
                Text("People will appear here when Runway sees them in Feeds or Pulls.")
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
        ForEach(sortedProfiles) { profile in
            peopleRow(profile: profile)
        }
    }

    private var sortedProfiles: [PersonProfile] {
        manager.profiles.sorted {
            $0.effectiveFullName.localizedCaseInsensitiveCompare(
                $1.effectiveFullName
            ) == .orderedAscending
        }
    }

    private func peopleRow(profile: PersonProfile) -> some View {
        Button {
            select(profile.login)
        } label: {
            HStack(spacing: 10) {
                Avatar(login: profile.login, url: profile.avatarURL, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.effectiveFullName)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("@\(profile.effectiveUsername)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            selectedPersonLogin == profile.login
                ? Color.accentColor.opacity(0.16)
                : Color.clear
        )
        .pointerCursor()
    }

    private func editProfilePanel(for login: String, profile: PersonProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Profile")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                Avatar(login: login, url: profile.avatarURL, size: 48)
                
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
                    .pointerCursor()
                    if profile.imageData != nil {
                        Button("Remove Image", role: .destructive) {
                            var updated = profile
                            updated.imageData = nil
                            updateProfile(updated)
                        }
                        .font(.system(size: 11))
                        .pointerCursor()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Username")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(login, text: $usernameDraft)
                    .font(.system(size: 12))
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Full name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Full name", text: $fullNameDraft)
                    .font(.system(size: 12))
                    .textFieldStyle(.roundedBorder)
            }

            Text("Edits are local to Runway. An empty username uses the GitHub login, and an empty full name uses the username.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Reset") {
                    draftSaveTask?.cancel()
                    var updated = manager.profile(for: login) ?? PersonProfile(login: login)
                    updated.displayName = ""
                    updated.fullNameOverride = nil
                    updateProfile(updated)
                    usernameDraft = ""
                    fullNameDraft = updated.githubFullName ?? ""
                }
                .disabled(
                    profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && profile.fullNameOverride == nil
                )
                .pointerCursor()
            }
        }
        .padding()
    }

    private func select(_ login: String) {
        commitDrafts()
        let profile = manager.profile(for: login) ?? PersonProfile(login: login)
        usernameDraft = profile.displayName
        fullNameDraft = profile.fullNameOverride ?? profile.githubFullName ?? ""
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedPersonLogin = login
        }
    }

    private func scheduleDraftSave() {
        guard selectedPersonLogin != nil else { return }
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            commitDrafts()
        }
    }

    private func commitDrafts() {
        guard let login = selectedPersonLogin else { return }
        var profile = manager.profile(for: login) ?? PersonProfile(login: login)
        guard profile.displayName != usernameDraft
            || (profile.fullNameOverride ?? profile.githubFullName ?? "") != fullNameDraft
        else { return }
        profile.displayName = usernameDraft
        profile.fullNameOverride = fullNameDraft
        updateProfile(profile)
    }

    private func updateProfile(_ profile: PersonProfile) {
        manager.updateProfile(profile)
    }
}
