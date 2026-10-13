import SwiftUI

/// The shared invitation to fill an empty day.
struct MealPlanDayEmptyEntry: View {
    let title: String
    var accessibilityLabel: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}
