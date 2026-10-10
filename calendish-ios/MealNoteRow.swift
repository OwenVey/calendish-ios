import SwiftUI

/// A meal plan note, laid out like a recipe row so a day's entries line up.
struct MealNoteRow: View {
    let note: MealPlanNote

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color(.tertiarySystemFill))
                Image(systemName: "note.text").font(.system(size: 25, weight: .light)).foregroundStyle(.secondary)
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(note.text).font(.headline).foregroundStyle(.primary).lineLimit(2)
                if !note.items.isEmpty {
                    Label(note.items.formatted(.list(type: .and, width: .narrow)), systemImage: "basket")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        .accessibilityLabel("Groceries: \(note.items.formatted())")
                }
            }.padding(.vertical, 4)
        }
        .accessibilityElement(children: .combine)
    }
}
