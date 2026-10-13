import SwiftUI

/// Names the week, like Calendar's list view: relative names nearby, dates further out. A menu acts on the whole week.
struct WeekHeader: View {
    let week: Date
    /// Nil when the week has no empty day from today on.
    let autoPlan: (() -> Void)?
    /// Nil when nothing planned this week has groceries to add.
    let addToGroceries: (() -> Void)?
    /// Nil when the week has no meals or notes.
    let clear: (() -> Void)?

    /// "This week", "Next week", or the week's dates.
    static func title(for week: Date) -> String { relativeName(for: week) ?? range(for: week) }

    private static func relativeName(for week: Date) -> String? {
        switch Calendar.current.dateComponents([.weekOfYear], from: CalendarDays.startOfWeek(.now), to: week).weekOfYear ?? 0 {
        case -1: "Last week"
        case 0: "This week"
        case 1: "Next week"
        default: nil
        }
    }

    private static func range(for week: Date) -> String {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 6, to: week)!
        let sameYear = calendar.isDate(week, equalTo: .now, toGranularity: .year) && calendar.isDate(end, equalTo: .now, toGranularity: .year)
        return (week..<end).formatted(sameYear ? .interval.month(.abbreviated).day() : .interval.month(.abbreviated).day().year())
    }

    var body: some View {
        let name = Self.relativeName(for: week)
        let range = Self.range(for: week)
        HStack {
            HStack(alignment: .firstTextBaseline) {
                Text(name ?? range).font(.title3.weight(.semibold))
                Spacer()
                if name != nil { Text(range).font(.subheadline).foregroundStyle(.secondary) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Menu {
                Button("Auto plan", systemImage: "wand.and.stars") { autoPlan?() }
                    .disabled(autoPlan == nil)
                Button("Add to groceries", systemImage: "basket") { addToGroceries?() }
                    .disabled(addToGroceries == nil)
                Section {
                    Button("Clear week", systemImage: "trash", role: .destructive) { clear?() }
                        .disabled(clear == nil)
                }
            } label: {
                // A Menu only hit-tests its label, so the 44pt target has to live inside it.
                Label("More for \(name ?? range)", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .menuStyle(CalendishMenuStyle())
        }
        // Neutral like the day headers' menus.
        .foregroundStyle(.primary)
        .tint(.primary)
        .padding(.leading, 6)
        .padding(.top, 6)
    }
}
