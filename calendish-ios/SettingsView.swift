import ActivityKit
import AlarmKit
import SwiftUI
import UserNotifications

/// App and account settings, laid out like the Settings app: account card first, then grouped rows.
struct SettingsView: View {
    @Environment(HouseholdStore.self) private var store
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @AppStorage(WeekStart.storageKey) private var weekStart = WeekStart.system
    @AppStorage(PreferenceKey.defaultServings) private var defaultServings = 4
    @AppStorage(MeasurementPreference.storageKey) private var units = MeasurementPreference.original
    @AppStorage(PreferenceKey.groceryAutoClear) private var groceryAutoClear = GroceryAutoClear.never
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
            // Sort, grouping, and show-completed live in each screen's own menus, which remember the choice.
            Section("General") {
                NavigationLink { AppearanceSettingsView() } label: {
                    LabeledContent {
                        Text(appearance.title)
                    } label: {
                        SettingsLabel("Appearance", systemImage: "circle.lefthalf.filled", color: .blue)
                    }
                }
                Picker(selection: $weekStart) {
                    ForEach(WeekStart.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsLabel("Week Starts On", systemImage: "calendar", color: .red)
                }
                .tint(.secondary)
                Picker(selection: $units) {
                    ForEach(MeasurementPreference.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsLabel("Units", systemImage: "ruler.fill", color: .indigo)
                }
                .tint(.secondary)
            }
            Section("Recipes") {
                HStack {
                    SettingsLabel("Default Servings", systemImage: "person.2.fill", color: .pink)
                    Spacer()
                    Text(defaultServings, format: .number).foregroundStyle(.secondary)
                    Stepper("Default Servings", value: $defaultServings, in: 1...20)
                        .labelsHidden()
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
                NavigationLink { CookingSettingsView() } label: {
                    SettingsLabel("Cooking", systemImage: "frying.pan.fill", color: .purple)
                }
            }
            Section {
                Picker(selection: $groceryAutoClear) {
                    ForEach(GroceryAutoClear.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsLabel("Clear Checked Items", systemImage: "checklist.checked", color: .green)
                }
                .tint(.secondary)
            } header: {
                Text("Groceries")
            } footer: {
                Text("Checked items are removed from the list for everyone in your household.")
            }
            Section("About") {
                Link(destination: AppLinks.feedback) {
                    SettingsLinkLabel("Send Feedback", systemImage: "envelope.fill", color: .blue)
                }
                if let review = AppLinks.writeReview {
                    Link(destination: review) {
                        SettingsLinkLabel("Rate on the App Store", systemImage: "star.fill", color: .yellow)
                    }
                }
                if let privacy = AppLinks.privacyPolicy {
                    Link(destination: privacy) {
                        SettingsLinkLabel("Privacy Policy", systemImage: "hand.raised.fill", color: .blue)
                    }
                }
                if let terms = AppLinks.terms {
                    Link(destination: terms) {
                        SettingsLinkLabel("Terms of Use", systemImage: "doc.text.fill", color: .gray)
                    }
                }
                LabeledContent {
                    Text(Bundle.main.appVersion)
                } label: {
                    SettingsLabel("Version", systemImage: "info", color: .gray)
                }
            }
        }
        .navigationTitle("Settings")
        .tabRootStyle()
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

/// A settings row that leaves the app, marked with the outward arrow Settings uses for links.
struct SettingsLinkLabel: View {
    let title: String
    let systemImage: String
    let color: Color
    init(_ title: String, systemImage: String, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }
    var body: some View {
        HStack {
            SettingsLabel(title, systemImage: systemImage, color: color).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Pages outside the app. Rows for links that aren't set yet stay hidden.
enum AppLinks {
    static let feedback = URL(string: "https://github.com/OwenVey/calendish-ios/issues/new")!
    /// The numeric ID from the app's App Store URL.
    static let appStoreID: String? = nil
    static let privacyPolicy: URL? = nil
    static let terms: URL? = nil
    static var writeReview: URL? {
        appStoreID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)?action=write-review") }
    }
}

struct ProfileSettingsView: View {
    @Environment(HouseholdStore.self) private var store
    @State private var memberName = ""
    @State private var confirmSignOut = false
    @State private var confirmDeleteAccount = false
    @State private var deletingAccount = false
    @State private var deleteAccountError: String?
    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    ProfilePhotoControl()
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
                    .confirmationDialog("Sign out of Calendish?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                        Button("Sign Out", role: .destructive) { Task { await store.signOut() } }
                    }
            }
            Section {
                Button(role: .destructive) { confirmDeleteAccount = true } label: {
                    if deletingAccount { ProgressView("Deleting Account…") }
                    else { Text("Delete Account") }
                }
                .frame(maxWidth: .infinity)
                .disabled(deletingAccount)
            } footer: {
                Text("Permanently deletes your account and personal recipes. Your household keeps the recipes you shared with it.")
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { memberName = store.currentMember?.displayName ?? "" }
        .onDisappear { saveName() }
        .calendishAlert("Delete Account?", isPresented: $confirmDeleteAccount) {
            Button("Delete Account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(store.members.count > 1
                ? "This permanently deletes your account and personal recipes. Your household keeps the recipes you shared with it. This can’t be undone."
                : "This permanently deletes your account, your household, and all of its recipes, meal plans, and groceries. This can’t be undone.")
        }
        .calendishAlert("Couldn’t Delete Account", isPresented: Binding(get: { deleteAccountError != nil }, set: { if !$0 { deleteAccountError = nil } })) {
            Button("OK") { }
        } message: {
            Text("Your account wasn’t deleted. \(deleteAccountError ?? "")")
        }
    }
    private func saveName() { store.renameMember(to: memberName.trimmingCharacters(in: .whitespaces)) }
    private func deleteAccount() {
        deletingAccount = true
        Task {
            defer { deletingAccount = false }
            do { try await store.deleteAccount() } catch { deleteAccountError = error.localizedDescription }
        }
    }
}

struct HouseholdSettingsView: View {
    @Environment(HouseholdStore.self) private var store
    @State private var householdName = ""
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteError: String?
    @State private var memberToRemove: HouseholdMember?
    private enum HouseholdChange: String, Identifiable {
        case join, leave
        var id: String { rawValue }
    }
    @State private var householdChange: HouseholdChange?
    @State private var memberToOwn: HouseholdMember?
    @State private var copiedCode = false
    @State private var copiedReset: Task<Void, Never>?
    var body: some View {
        Form {
            Section("Name") {
                TextField("Household name", text: $householdName)
                    .onSubmit { saveName() }
            }
            Section {
                ForEach(store.members) { member in
                    HStack(spacing: 12) {
                        MemberAvatar(member: member, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName)
                            Text(member.userID == store.userID ? "You · \(member.role.capitalized)" : member.role.capitalized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.isOwner && member.role != "owner" {
                            Menu {
                                Button("Make Owner", systemImage: "person.badge.key") { memberToOwn = member }
                                Button("Remove Member", systemImage: "person.badge.minus", role: .destructive) { memberToRemove = member }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .foregroundStyle(Color.secondary)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Actions for \(member.displayName)")
                        }
                    }
                }
                if let code = store.household?.inviteCode {
                    Menu {
                        ShareLink(item: "Join my household on Calendish: \(HouseholdInvite.link(for: code).absoluteString)\nInvite code: \(code)") {
                            Label("Share Invitation", systemImage: "square.and.arrow.up")
                        }
                        Button("Copy Code", systemImage: "doc.on.doc") { copyInviteCode(code) }
                    } label: {
                        LabeledContent {
                            HStack(spacing: 8) {
                                Text(code).font(.body.monospaced())
                                Image(systemName: copiedCode ? "checkmark" : "chevron.down")
                                    .font(.footnote.weight(.semibold))
                                    .frame(width: 16)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .foregroundStyle(.secondary)
                        } label: {
                            Label("Invite Members", systemImage: "person.badge.plus")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .accessibilityIdentifier("household-invitation")
                    .accessibilityLabel("Invite Members")
                    .accessibilityValue(copiedCode ? "Code copied" : code)
                    .accessibilityHint("Share an invitation or copy the invite code")
                    .sensoryFeedback(.success, trigger: copiedCode) { _, new in new }
                }
            } header: {
                Text("Members")
            } footer: {
                Text("Share an invitation or copy the code.")
            }
            Section {
                Button("Join Household", systemImage: "person.2.badge.plus") { householdChange = .join }
                Button("Leave Household", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { householdChange = .leave }
                    // Form row icons use list-item tint separately from the button's destructive title.
                    .listItemTint(.red)
            } header: {
                Text("Change Household")
            } footer: {
                Text("Your personal recipes stay with you.")
            }
            if store.isOwner {
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        if deleting { ProgressView("Deleting Household Data…") }
                        else { Label("Delete Household Data", systemImage: "trash") }
                    }
                    .listItemTint(.red)
                    .disabled(deleting)
                } header: {
                    Text("Household Data")
                } footer: {
                    Text("Deletes household-owned recipes, meal plans, and groceries. Personal recipes, members, and the invite code stay.")
                }
            }
        }
        .navigationTitle("Household")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { householdName = store.household?.name ?? "" }
        .onChange(of: store.household?.id) { _, _ in householdName = store.household?.name ?? "" }
        .onDisappear { saveName() }
        .calendishAlert("Delete Household Data?", isPresented: $confirmDelete) {
            Button("Delete Household Data", role: .destructive) { deleteAllData() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes household-owned recipes, meal plans, and groceries. Everyone’s personal recipes stay. This can’t be undone.")
        }
        .calendishAlert("Remove \(memberToRemove?.displayName ?? "Member")?", isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }), presenting: memberToRemove) { member in
            Button("Remove", role: .destructive) { store.removeMember(member) }
            Button("Cancel", role: .cancel) { }
        } message: { _ in
            Text("They keep their personal recipes and receive a fresh solo household. Their shared recipes remain here as independent household copies. Your invite code will change.")
        }
        .sheet(item: $householdChange) { change in
            HouseholdMoveView(leaving: change == .leave)
        }
        .calendishAlert("Transfer Ownership?", isPresented: Binding(get: { memberToOwn != nil }, set: { if !$0 { memberToOwn = nil } }), presenting: memberToOwn) { member in
            Button("Make Owner", role: .confirm) { store.transferOwnership(to: member); memberToOwn = nil }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { memberToOwn = nil }
        } message: { member in
            Text("\(member.displayName) will manage membership. You’ll remain a member and can still edit household recipes, groceries, and meals.")
        }
        .calendishAlert("Couldn’t Delete Data", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK") { }
        } message: {
            Text("Nothing was deleted. \(deleteError ?? "")")
        }
    }
    private func saveName() { store.renameHousehold(to: householdName.trimmingCharacters(in: .whitespaces)) }
    /// Copies the code and briefly confirms it with a checkmark in the invitation row.
    private func copyInviteCode(_ code: String) {
        UIPasteboard.general.string = code
        copiedCode = true
        copiedReset?.cancel()
        copiedReset = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            copiedCode = false
        }
    }
    private func deleteAllData() {
        deleting = true
        Task {
            defer { deleting = false }
            do { try await store.deleteAllHouseholdData() } catch { deleteError = error.localizedDescription }
        }
    }
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

struct CookingSettingsView: View {
    @AppStorage(PreferenceKey.keepScreenAwake) private var keepScreenAwake = true
    @AppStorage(PreferenceKey.showCookIngredients) private var showIngredients = true
    @AppStorage(PreferenceKey.cookingHaptics) private var haptics = true
    @AppStorage(PreferenceKey.liveActivity) private var liveActivity = true
    @AppStorage(PreferenceKey.timerAlert) private var timerAlert = TimerAlert.alarm
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var notifications: UNAuthorizationStatus?
    @State private var activitiesAllowed = ActivityAuthorizationInfo().areActivitiesEnabled
    @State private var alarms = AlarmManager.shared.authorizationState
    private var notificationsAllowed: Bool { [.authorized, .provisional, .ephemeral].contains(notifications) }
    var body: some View {
        Form {
            Section {
                Toggle("Keep Screen Awake", isOn: $keepScreenAwake)
            } footer: {
                Text("Your screen stays on while cook mode is open.")
            }
            Section {
                Toggle("Show Ingredients", isOn: $showIngredients)
            } footer: {
                Text("Open the ingredient list alongside the steps when you start cooking.")
            }
            Section {
                Toggle("Haptics", isOn: $haptics)
            } footer: {
                Text("Feel a tap when you change steps, check off ingredients, or finish a timer.")
            }
            Section {
                Toggle("Live Activity", isOn: $liveActivity)
                if liveActivity && !activitiesAllowed {
                    Button("Open Calendish Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            } footer: {
                Text(liveActivity && !activitiesAllowed
                    ? "Live Activities are turned off for Calendish in the Settings app."
                    : "Follow the current step and start timers from the Lock Screen and Dynamic Island.")
            }
            Section {
                Picker("Alert", selection: $timerAlert) {
                    ForEach(TimerAlert.allCases) { Text($0.title).tag($0) }
                }
                .tint(.secondary)
                if timerAlert == .alarm {
                    if alarms == .notDetermined {
                        Button("Allow Alarms") {
                            Task { alarms = (try? await AlarmManager.shared.requestAuthorization()) ?? AlarmManager.shared.authorizationState }
                        }
                    } else if alarms == .denied {
                        Button("Open Calendish Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                } else if let notifications {
                    LabeledContent("Notifications", value: notificationsAllowed ? "On" : "Off")
                    if notifications == .notDetermined {
                        Button("Allow Notifications") {
                            Task {
                                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                                await loadNotificationStatus()
                            }
                        }
                    } else {
                        Button("Open Notification Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }
                    }
                }
            } header: {
                Text("Timers")
            } footer: {
                Text(timerFooter)
            }
        }
        .navigationTitle("Cooking")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            activitiesAllowed = ActivityAuthorizationInfo().areActivitiesEnabled
            alarms = AlarmManager.shared.authorizationState
            Task { await loadNotificationStatus() }
        }
    }
    private var timerFooter: String {
        switch timerAlert {
        case .alarm where alarms == .denied:
            "Alarms are turned off for Calendish in the Settings app, so timers use notifications instead."
        case .alarm: "Timers ring like the Clock app, even when your iPhone is on silent or in a Focus."
        case .notification: "Timers play a sound and show a notification. They alert you outside Calendish only when notifications are on."
        case .silent: "Timers show a notification without a sound."
        }
    }
    private func loadNotificationStatus() async {
        notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
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
