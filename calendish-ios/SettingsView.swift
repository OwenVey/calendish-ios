import SwiftUI

/// App and account settings, laid out like the Settings app: account card first, then grouped rows.
struct SettingsView: View {
    @Environment(HouseholdStore.self) private var store
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    var body: some View {
        Form {
            Section {
                NavigationLink { ProfileSettingsView() } label: {
                    HStack(spacing: 14) {
                        MemberAvatar(member: store.currentMember, size: 60)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.currentMember?.displayName ?? "You").font(.title3.weight(.semibold))
                            Text(store.accountEmail ?? "Profile and sign out").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }
            }
            Section {
                NavigationLink { HouseholdSettingsView() } label: {
                    LabeledContent {
                        Text(store.household?.name ?? "")
                    } label: {
                        SettingsLabel("Household", systemImage: "house.fill", color: .orange)
                    }
                }
            }
            Section {
                NavigationLink { AppearanceSettingsView() } label: {
                    LabeledContent {
                        Text(appearance.title)
                    } label: {
                        SettingsLabel("Appearance", systemImage: "circle.lefthalf.filled", color: .blue)
                    }
                }
            }
            Section {
                LabeledContent {
                    Text(Bundle.main.appVersion)
                } label: {
                    SettingsLabel("Version", systemImage: "info", color: .gray)
                }
            }
        }
        .navigationTitle("Settings")
    }
}

/// A settings row title with the Settings app's white glyph on a colored rounded square.
struct SettingsLabel: View {
    let title: String
    let systemImage: String
    let color: Color
    init(_ title: String, systemImage: String, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }
    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(color.gradient, in: .rect(cornerRadius: 7))
        }
    }
}

struct ProfileSettingsView: View {
    @Environment(HouseholdStore.self) private var store
    @State private var memberName = ""
    @State private var confirmSignOut = false
    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    MemberAvatar(member: store.currentMember, size: 88)
                    Text(store.currentMember?.displayName ?? "You").font(.title2.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                TextField("Your name", text: $memberName).textContentType(.givenName)
                    .onSubmit { saveName() }
            } header: {
                Text("Name")
            } footer: {
                Text("This is how you’ll appear to your household.")
            }
            if let email = store.accountEmail {
                Section("Account") {
                    LabeledContent("Email", value: email)
                }
            }
            Section {
                Button("Sign Out", role: .destructive) { confirmSignOut = true }
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { memberName = store.currentMember?.displayName ?? "" }
        .onDisappear { saveName() }
        .confirmationDialog("Sign out of Calendish?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { Task { await store.signOut() } }
        }
    }
    private func saveName() { store.renameMember(to: memberName.trimmingCharacters(in: .whitespaces)) }
}

struct HouseholdSettingsView: View {
    @Environment(HouseholdStore.self) private var store
    @State private var householdName = ""
    var body: some View {
        Form {
            Section("Name") {
                TextField("Household name", text: $householdName)
                    .onSubmit { saveName() }
            }
            Section("Members") {
                ForEach(store.members) { member in
                    HStack(spacing: 12) {
                        MemberAvatar(member: member, size: 32)
                        Text(member.displayName)
                        if member.userID == store.userID { Text("(You)").foregroundStyle(.secondary) }
                        Spacer()
                        Text(member.role.capitalized).foregroundStyle(.secondary)
                    }
                }
            }
            if let code = store.household?.inviteCode {
                Section {
                    LabeledContent("Invite code") {
                        Text(code).font(.body.monospaced()).textSelection(.enabled)
                    }
                    ShareLink(item: "Join my household on Calendish with invite code \(code)") {
                        Label("Invite Members", systemImage: "person.badge.plus")
                    }
                } footer: {
                    Text("Someone joins by creating an account and entering this code.")
                }
            }
        }
        .navigationTitle("Household")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { householdName = store.household?.name ?? "" }
        .onDisappear { saveName() }
    }
    private func saveName() { store.renameHousehold(to: householdName.trimmingCharacters(in: .whitespaces)) }
}

struct AppearanceSettingsView: View {
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    var body: some View {
        Form {
            Picker("Theme", selection: $appearance) {
                ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    NavigationStack { SettingsView() }.environment(HouseholdStore.preview())
}
