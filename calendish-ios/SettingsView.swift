import ActivityKit
import SwiftUI
import UserNotifications

/// App and account settings, laid out like the Settings app: account card first, then grouped rows.
struct SettingsView: View {
    @Environment(HouseholdStore.self) private var store
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @AppStorage(WeekStart.storageKey) private var weekStart = WeekStart.system
    @AppStorage(MealSlot.enabledStorageKey) private var enabledSlots = MealSlot.allEnabled
    @AppStorage(PreferenceKey.recipeSort) private var recipeSort = RecipeSort.recent
    @AppStorage(PreferenceKey.defaultServings) private var defaultServings = 4
    @AppStorage(PreferenceKey.groceryGrouping) private var groceryGrouping = GroceryGrouping.none
    @AppStorage(PreferenceKey.showCompletedGroceries) private var showCompletedGroceries = false
    @AppStorage(MeasurementPreference.storageKey) private var units = MeasurementPreference.original
    private var mealsSummary: String {
        let slots = MealSlot.enabled(in: enabledSlots)
        return slots.count == MealSlot.allCases.count ? "All" : slots.map(\.title).formatted(.list(type: .and))
    }
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
                Picker(selection: $recipeSort) {
                    ForEach(RecipeSort.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsLabel("Sort By", systemImage: "arrow.up.arrow.down", color: .brown)
                }
                .tint(.secondary)
                HStack {
                    SettingsLabel("Default Servings", systemImage: "person.2.fill", color: .pink)
                    Spacer()
                    Text(defaultServings, format: .number).foregroundStyle(.secondary)
                    Stepper("Default Servings", value: $defaultServings, in: 1...20)
                        .labelsHidden()
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
                Picker(selection: $units) {
                    ForEach(MeasurementPreference.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsLabel("Units", systemImage: "ruler.fill", color: .indigo)
                }
                .tint(.secondary)
                NavigationLink { CookingSettingsView() } label: {
                    SettingsLabel("Cooking", systemImage: "frying.pan.fill", color: .purple)
                }
            } header: {
                Text("Recipes")
            }
            Section("Meal Plan") {
                Picker(selection: $weekStart) {
                    ForEach(WeekStart.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsLabel("Week Starts On", systemImage: "calendar", color: .red)
                }
                .tint(.secondary)
                NavigationLink { MealSlotSettingsView() } label: {
                    LabeledContent {
                        Text(mealsSummary)
                    } label: {
                        SettingsLabel("Meals", systemImage: "fork.knife", color: .teal)
                    }
                }
            }
            Section("Groceries") {
                Picker(selection: $groceryGrouping) {
                    ForEach(GroceryGrouping.allCases) { Text($0.rawValue).tag($0) }
                } label: {
                    SettingsLabel("Group By", systemImage: "basket.fill", color: .green)
                }
                .tint(.secondary)
                Toggle(isOn: $showCompletedGroceries) {
                    SettingsLabel("Show Completed", systemImage: "checkmark.circle.fill", color: .mint)
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
                    .confirmationDialog("Sign out of Calendish?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                        Button("Sign Out", role: .destructive) { Task { await store.signOut() } }
                    }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { memberName = store.currentMember?.displayName ?? "" }
        .onDisappear { saveName() }
    }
    private func saveName() { store.renameMember(to: memberName.trimmingCharacters(in: .whitespaces)) }
}

struct HouseholdSettingsView: View {
    @Environment(HouseholdStore.self) private var store
    @State private var householdName = ""
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteError: String?
    @State private var memberToRemove: HouseholdMember?
    @State private var showJoin = false
    @State private var showLeave = false
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
                        Text(member.displayName)
                        if member.userID == store.userID { Text("(You)").foregroundStyle(.secondary) }
                        Spacer()
                        Text(member.role.capitalized).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        if store.isOwner && member.role != "owner" {
                            Button("Make Owner") { memberToOwn = member }.tint(.orange)
                            Button("Remove") { memberToRemove = member }
                                .tint(.red)
                        }
                    }
                }
            } header: {
                Text("Members")
            } footer: {
                if store.isOwner && store.members.count > 1 {
                    Text("Swipe left on a member to remove them from your household.")
                }
            }
            if let code = store.household?.inviteCode {
                Section {
                    Button { copyInviteCode(code) } label: {
                        LabeledContent("Invite code") {
                            HStack(spacing: 8) {
                                Text(code).font(.body.monospaced())
                                // Hidden copy icon reserves a fixed size so the shorter checkmark can't shift the row.
                                Image(systemName: "doc.on.doc").hidden()
                                    .overlay {
                                        Image(systemName: copiedCode ? "checkmark" : "doc.on.doc")
                                            .foregroundStyle(copiedCode ? Color.accentColor : .secondary)
                                            .contentTransition(.symbolEffect(.replace))
                                    }
                            }
                        }
                    }
                    .tint(.primary)
                    .contextMenu {
                        Button("Copy", systemImage: "doc.on.doc") { copyInviteCode(code) }
                    }
                    .accessibilityHint("Copies the invite code")
                    .sensoryFeedback(.success, trigger: copiedCode) { _, new in new }
                    ShareLink(item: "Join my household on Calendish: \(HouseholdInvite.link(for: code).absoluteString)\nInvite code: \(code)") {
                        Label("Invite Members", systemImage: "person.badge.plus")
                    }
                } footer: {
                    Text("Someone joins by creating an account and entering this code.")
                }
            }
            Section {
                Button("Join Household") { showJoin = true }
                Button("Leave Household", role: .destructive) { showLeave = true }
            } footer: {
                Text("Your personal recipes follow you. Review what stays behind before making a change.")
            }
            if store.isOwner {
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        if deleting { ProgressView() } else { Text("Delete All Data") }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(deleting)
                } footer: {
                    Text("Deletes household-owned recipes, meal plans, and groceries. Personal recipes, members, and the invite code stay.")
                }
            }
        }
        .navigationTitle("Household")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { householdName = store.household?.name ?? "" }
        .onDisappear { saveName() }
        .alert("Delete All Household Data?", isPresented: $confirmDelete) {
            Button("Delete All Data", role: .destructive) { deleteAllData() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes household-owned recipes, meal plans, and groceries. Everyone’s personal recipes stay. This can’t be undone.")
        }
        .alert("Remove \(memberToRemove?.displayName ?? "Member")?", isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }), presenting: memberToRemove) { member in
            Button("Remove", role: .destructive) { store.removeMember(member) }
            Button("Cancel", role: .cancel) { }
        } message: { _ in
            Text("They keep their personal recipes and receive a fresh solo household. Their shared recipes remain here as independent household copies. Your invite code will change.")
        }
        .sheet(isPresented: $showJoin) { HouseholdMoveView() }
        .sheet(isPresented: $showLeave) { HouseholdMoveView(leaving: true) }
        .alert("Transfer Ownership?", isPresented: Binding(get: { memberToOwn != nil }, set: { if !$0 { memberToOwn = nil } }), presenting: memberToOwn) { member in
            Button("Make Owner") { store.transferOwnership(to: member); memberToOwn = nil }
            Button("Cancel", role: .cancel) { memberToOwn = nil }
        } message: { member in
            Text("\(member.displayName) will manage membership. You’ll remain a member and can still edit household recipes, groceries, and meals.")
        }
        .alert("Couldn’t Delete Data", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK") { }
        } message: {
            Text("Nothing was deleted. \(deleteError ?? "")")
        }
    }
    private func saveName() { store.renameHousehold(to: householdName.trimmingCharacters(in: .whitespaces)) }
    /// Copies the code and briefly swaps the copy icon for a checkmark.
    private func copyInviteCode(_ code: String) {
        UIPasteboard.general.string = code
        copiedCode = true
        copiedReset?.cancel()
        copiedReset = Task {
            try? await Task.sleep(for: .seconds(1.5))
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

struct MealSlotSettingsView: View {
    @AppStorage(MealSlot.enabledStorageKey) private var enabledSlots = MealSlot.allEnabled
    var body: some View {
        let enabled = MealSlot.enabled(in: enabledSlots)
        Form {
            Section {
                ForEach(MealSlot.allCases) { slot in
                    Toggle(isOn: Binding(
                        get: { enabled.contains(slot) },
                        set: { isOn in enabledSlots = MealSlot.storage(for: isOn ? enabled + [slot] : enabled.filter { $0 != slot }) }
                    )) {
                        Label(slot.title, systemImage: slot.symbol)
                    }
                    // Keep at least one meal to plan.
                    .disabled(enabled == [slot])
                }
            } footer: {
                Text("Choose which meals to plan. A turned-off meal still appears on days where it’s already planned.")
            }
        }
        .navigationTitle("Meals")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CookingSettingsView: View {
    @AppStorage(PreferenceKey.keepScreenAwake) private var keepScreenAwake = true
    @AppStorage(PreferenceKey.showCookIngredients) private var showIngredients = true
    @AppStorage(PreferenceKey.cookingHaptics) private var haptics = true
    @AppStorage(PreferenceKey.liveActivity) private var liveActivity = true
    @AppStorage(PreferenceKey.timerSound) private var timerSound = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var notifications: UNAuthorizationStatus?
    @State private var activitiesAllowed = ActivityAuthorizationInfo().areActivitiesEnabled
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
                Toggle("Timer Sound", isOn: $timerSound)
                if let notifications {
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
                Text("Timers alert you outside Calendish only when notifications are on.")
            }
        }
        .navigationTitle("Cooking")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            activitiesAllowed = ActivityAuthorizationInfo().areActivitiesEnabled
            Task { await loadNotificationStatus() }
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
