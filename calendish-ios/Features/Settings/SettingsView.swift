import SwiftUI

/// App and account settings, laid out like the Settings app: account card first, then grouped rows.
struct SettingsView: View {
    @Environment(HouseholdStore.self) private var store
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @AppStorage(PreferenceKey.haptics) private var haptics = true
    @AppStorage(WeekStart.storageKey) private var weekStart = WeekStart.system
    @AppStorage(PreferenceKey.defaultServings) private var defaultServings = 4
    @AppStorage(PreferenceKey.shareNewRecipes) private var shareNewRecipes = true
    @AppStorage(MeasurementPreference.storageKey) private var units = MeasurementPreference.original
    /// Nil follows the region, which is also what recipe screens fall back to.
    @AppStorage(TemperatureUnit.storageKey) private var temperatureUnit: TemperatureUnit?
    private var groceryAutoClear: Binding<GroceryAutoClear> {
        Binding { store.household?.groceryAutoClear ?? .never } set: { store.setGroceryAutoClear($0) }
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
            // Sort, grouping, and show-completed live in each screen's own menus, which remember the choice.
            Section("General") {
                Picker(selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsLabel("Appearance", systemImage: "circle.lefthalf.filled", color: .blue)
                }
                .tint(.secondary)
                Toggle(isOn: $haptics) {
                    SettingsLabel("Haptics", systemImage: "iphone.radiowaves.left.and.right", color: .gray)
                }
            }
            Section {
                Picker(selection: $units) {
                    ForEach(MeasurementPreference.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsLabel("Units", systemImage: "ruler.fill", color: .indigo)
                }
                .tint(.secondary)
                Picker(selection: $temperatureUnit) {
                    Text("Regional default").tag(TemperatureUnit?.none)
                    ForEach(TemperatureUnit.allCases) { Text($0.title).tag(Optional($0)) }
                } label: {
                    SettingsLabel("Temperature", systemImage: "thermometer.medium", color: .red)
                }
                .tint(.secondary)
                HStack {
                    SettingsLabel("Default servings", systemImage: "person.2.fill", color: .pink)
                    Spacer()
                    Text(defaultServings, format: .number).foregroundStyle(.secondary)
                    Stepper("Default servings", value: $defaultServings, in: 1...20)
                        .labelsHidden()
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
                Toggle(isOn: $shareNewRecipes) {
                    SettingsLabel("Share new recipes", systemImage: "person.2.wave.2.fill", color: .teal)
                }
                NavigationLink { CookingSettingsView() } label: {
                    SettingsLabel("Cooking", systemImage: "frying.pan.fill", color: .purple)
                }
            } header: {
                Text("Recipes")
            }
            Section("Meal plan") {
                Picker(selection: $weekStart) {
                    ForEach(WeekStart.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsLabel("Week starts on", systemImage: "calendar", color: .red)
                }
                .tint(.secondary)
            }
            Section {
                Picker(selection: groceryAutoClear) {
                    ForEach(GroceryAutoClear.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsLabel("Clear checked items", systemImage: "checklist.checked", color: .green)
                }
                .tint(.secondary)
                NavigationLink { SiriSettingsView() } label: {
                    SettingsLabel("Siri & Shortcuts", systemImage: "waveform", color: .cyan)
                }
            } header: {
                Text("Groceries")
            }
            Section("About") {
                Link(destination: AppLinks.feedback) {
                    SettingsLinkLabel("Report an issue", systemImage: "envelope.fill", color: .blue)
                }
                .accessibilityHint("Opens GitHub. A GitHub account may be needed.")
                if let review = AppLinks.writeReview {
                    Link(destination: review) {
                        SettingsLinkLabel("Rate on the App Store", systemImage: "star.fill", color: .yellow)
                    }
                }
                if let privacy = AppLinks.privacyPolicy {
                    Link(destination: privacy) {
                        SettingsLinkLabel("Privacy policy", systemImage: "hand.raised.fill", color: .blue)
                    }
                }
                if let terms = AppLinks.terms {
                    Link(destination: terms) {
                        SettingsLinkLabel("Terms of use", systemImage: "doc.text.fill", color: .gray)
                    }
                }
                LabeledContent {
                    Text(Bundle.main.appVersion)
                } label: {
                    SettingsLabel("Version", systemImage: "info", color: .gray)
                }
                .calendishContextMenu {
                    Button("Copy version", systemImage: "doc.on.doc") { UIPasteboard.general.string = Bundle.main.appVersion }
                }
                .accessibilityHint("Touch and hold to copy the version.")
            }
        }
        .navigationTitle("Settings")
        .tabRootStyle()
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
