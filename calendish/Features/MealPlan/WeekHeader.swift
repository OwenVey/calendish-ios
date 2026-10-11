import SwiftUI

/// Names the week, like Calendar's list view: relative names nearby, dates further out.
struct WeekHeader: View {
    let week: Date

    var body: some View {
        let calendar = Calendar.current
        let thisWeek = CalendarDays.startOfWeek(.now)
        let offset = calendar.dateComponents([.weekOfYear], from: thisWeek, to: week).weekOfYear ?? 0
        let end = calendar.date(byAdding: .day, value: 6, to: week)!
        let sameYear = calendar.isDate(week, equalTo: .now, toGranularity: .year) && calendar.isDate(end, equalTo: .now, toGranularity: .year)
        let range = (week..<end).formatted(sameYear ? .interval.month(.abbreviated).day() : .interval.month(.abbreviated).day().year())
        let name: String? = switch offset {
        case -1: "Last week"
        case 0: "This week"
        case 1: "Next week"
        default: nil
        }
        HStack(alignment: .firstTextBaseline) {
            Text(name ?? range).font(.title3.weight(.semibold))
            Spacer()
            if name != nil { Text(range).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 6)
        .padding(.top, 14)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
