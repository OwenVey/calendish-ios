import SwiftUI

/// A form field whose label stays visible above its value, so filled-in rows still say what they are.
struct LabeledFormField<Field: View>: View {
    let title: String
    @ViewBuilder var field: Field
    init(_ title: String, @ViewBuilder field: () -> Field) {
        self.title = title
        self.field = field()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            field
        }
        .accessibilityElement(children: .combine)
    }
}
