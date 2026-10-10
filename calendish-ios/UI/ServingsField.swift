import SwiftUI

struct ServingsField: View {
    @Binding var servings: Int
    var body: some View {
        HStack {
            Text("Servings")
            Spacer()
            TextField("Servings", value: $servings, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .frame(width: 60)
                .accessibilityLabel("Number of servings")
            Stepper("Adjust Servings", value: $servings, in: 1...1000)
                .labelsHidden()
                .fixedSize()
        }
        .onChange(of: servings) { _, value in servings = min(1000, max(1, value)) }
    }
}
