import AppIntents
import SwiftUI

/// Shows what to say to Siri, since voice and Shortcuts actions are otherwise hard to discover.
struct SiriSettingsView: View {
    private var phrases: [(phrase: String, detail: String)] {
        var phrases = [("“Add to Calendish”", "Siri asks what to add to your grocery list.")]
        if #available(iOS 27, *) {
            phrases.insert(("“Add apples to Calendish”", "Adds an item to your grocery list in one step."), at: 0)
        }
        return phrases
    }
    var body: some View {
        Form {
            Section {
                ForEach(phrases, id: \.phrase) { phrase, detail in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(phrase)
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Try saying")
            } footer: {
                Text("Items go on your household’s grocery list without opening Calendish.")
            }
            Section {
                ShortcutsLink()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } footer: {
                Text("“Add to Groceries” is also available in Spotlight and the Shortcuts app, where you can use it in your own shortcuts.")
            }
        }
        .navigationTitle("Siri & Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SiriSettingsView() }
}
