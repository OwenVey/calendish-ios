import SwiftUI

/// Expands a compact form row into the system's hour/minute duration wheels.
struct RecipeDurationField: View {
    let title: String
    @Binding var minutes: Int

    private var formattedDuration: String {
        guard minutes > 0 else { return "Not set" }
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    var body: some View {
        DisclosureGroup {
            RecipeDurationPicker(minutes: $minutes, title: title)
                .frame(maxWidth: .infinity)
                .frame(height: 180)
        } label: {
            LabeledContent(title, value: formattedDuration)
        }
    }
}
