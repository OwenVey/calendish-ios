import SwiftUI

/// The shared date capsule, with actions supplied by the plan or proposal that owns the day.
struct MealPlanDayCardHeader<Actions: View>: View {
    let day: Date
    let isEmphasized: Bool
    let isToday: Bool
    @ViewBuilder let actions: Actions

    var body: some View {
        let weekday = day.formatted(.dateTime.weekday(.wide))
        let fullDate = day.formatted(date: .complete, time: .omitted)
        HStack(spacing: 0) {
            Text("\(Text(weekday).foregroundStyle(isToday ? CalendishStyle.accent : Color.primary)) \(Text(day.formatted(.dateTime.month(.abbreviated).day())).foregroundStyle(.secondary))")
                .font(.headline)
                .accessibilityLabel(isToday ? Text("Today, \(fullDate)") : Text(fullDate))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            actions
        }
        // Color belongs on the visible glyphs, so native menu roles and disabled items keep their colors.
        .font(.body.weight(.semibold))
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .background(Color(isEmphasized ? .tertiarySystemFill : .quaternarySystemFill), in: .capsule)
    }
}
