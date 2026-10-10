import SwiftUI

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
