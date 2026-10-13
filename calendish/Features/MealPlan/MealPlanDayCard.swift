import SwiftUI

/// The shared day-card frame for persisted plans and the proposal being reviewed.
struct MealPlanDayCard<Header: View, Content: View>: View {
    let day: Date
    /// Emphasized days use solid cards; past days in the meal plan recede.
    let isEmphasized: Bool
    let isEmpty: Bool
    var isDropTarget = false
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            header
            content
        }
        .padding(6)
        .padding(.bottom, isEmpty && !isEmphasized ? 0 : 4)
        .background(isEmphasized ? CalendishStyle.surface : .clear, in: shape)
        .overlay {
            if isDropTarget {
                shape.fill(CalendishStyle.accent.opacity(0.08))
                shape.strokeBorder(CalendishStyle.accent, lineWidth: 2)
            } else if Calendar.current.isDateInToday(day) {
                shape.strokeBorder(CalendishStyle.accent.opacity(0.7), lineWidth: 1.5)
            } else if !isEmphasized {
                shape.strokeBorder(Color(.separator), lineWidth: 1)
            }
        }
    }
}
