import SwiftUI

/// Steps between the current and later weeks, named like the meal plan's week headers.
struct AutoPlanWeekPicker: View {
    let plan: AutoPlan

    var body: some View {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: plan.week)!
        let range = (plan.week..<end).formatted(.interval.month(.abbreviated).day())
        let name: String? = switch plan.weekOffset {
        case 0: "This week"
        case 1: "Next week"
        default: nil
        }
        HStack {
            Button("Previous week", systemImage: "chevron.left") { plan.showWeek(offset: -1) }
                .disabled(!plan.canShowPreviousWeek)
            Spacer()
            VStack {
                Text(name ?? range).font(.headline)
                if name != nil { Text(range).font(.subheadline).foregroundStyle(.secondary) }
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button("Next week", systemImage: "chevron.right") { plan.showWeek(offset: 1) }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .tint(.primary)
    }
}
