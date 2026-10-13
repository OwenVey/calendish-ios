import SwiftUI

/// A day to plan, checked when selected. Past days and days with plans can't be chosen and say why.
struct AutoPlanDayRow: View {
    let day: AutoPlan.Day
    let toggle: () -> Void
    private var reason: String? {
        switch day.availability {
        case .open: nil
        case .past: "Already passed"
        case .planned: "Has plans"
        }
    }

    var body: some View {
        Button(action: toggle) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .foregroundStyle(reason == nil ? .primary : .secondary)
                    if let reason { Text(reason).font(.subheadline).foregroundStyle(.secondary) }
                }
                Spacer()
                if day.isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(CalendishStyle.accent).accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(reason != nil)
        .accessibilityValue(day.isSelected ? "Selected" : reason ?? "Not selected")
        .accessibilityAddTraits(day.isSelected ? .isSelected : [])
    }
}
