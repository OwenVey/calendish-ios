import SwiftUI
import UserNotifications

/// App and account settings, laid out like the Settings app: account card first, then grouped rows.
struct SettingsView: View {
    @Environment(HouseholdStore.self) private var store
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @AppStorage(WeekStart.storageKey) private var weekStart = WeekStart.system
    @AppStorage(MealSlot.enabledStorageKey) private var enabledSlots = MealSlot.allEnabled
    @AppStorage(PreferenceKey.recipeSort) private var recipeSort = RecipeSort.recent
    @AppStorage(PreferenceKey.groceryGrouping) private var groceryGrouping = GroceryGrouping.none
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
                Picker(selection: $weekStart) {
                    ForEach(WeekStart.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsLabel("Week Starts On", systemImage: "calendar", color: .red)
                }
                NavigationLink { MealSlotSettingsView() } label: {
                    LabeledContent {
                        Text(mealsSummary)
                    } label: {
                        SettingsLabel("Meals", systemImage: "fork.knife", color: .teal)
                    }
                }
            }
            Section {
                Picker(selection: $recipeSort) {
                    ForEach(RecipeSort.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsLabel("Sort Recipes By", systemImage: "book.closed.fill", color: .brown)
                }
                Picker(selection: $groceryGrouping) {
                    ForEach(GroceryGrouping.allCases) { Text($0.rawValue).tag($0) }
                } label: {
                    SettingsLabel("Group Groceries By", systemImage: "basket.fill", color: .green)
                }
            }
            Section {
                NavigationLink { CookingSettingsView() } label: {
                    SettingsLabel("Cooking", systemImage: "frying.pan.fill", color: .purple)
                }
                Picker(selection: $units) {
                    ForEach(MeasurementPreference.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsLabel("Units", systemImage: "ruler.fill", color: .indigo)
                }
            } footer: {
                Text("Units converts cups, ounces, pounds, and oven temperatures in recipes and cook mode. Saved recipes keep their original measurements.")
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
    @AppStorage(PreferenceKey.cookingHaptics) private var haptics = true
    @AppStorage(PreferenceKey.timerSound) private var timerSound = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var notifications: UNAuthorizationStatus?
    private var notificationsAllowed: Bool { [.authorized, .provisional, .ephemeral].contains(notifications) }
    var body: some View {
        Form {
            Section {
                Toggle("Keep Screen Awake", isOn: $keepScreenAwake)
            } footer: {
                Text("Your screen stays on while cook mode is open.")
            }
            Section {
                Toggle("Haptics", isOn: $haptics)
            } footer: {
                Text("Feel a tap when you change steps, check off ingredients, or finish a timer.")
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
            if phase == .active { Task { await loadNotificationStatus() } }
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
