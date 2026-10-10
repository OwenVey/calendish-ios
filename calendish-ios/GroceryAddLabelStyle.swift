import SwiftUI

/// Lines the add-from-search row up with grocery rows' checkmark column.
struct GroceryAddLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.icon
            configuration.title.font(.body.weight(.medium))
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
