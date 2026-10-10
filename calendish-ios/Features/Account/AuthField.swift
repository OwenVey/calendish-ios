import SwiftUI

/// A large filled text field, as used in modern onboarding flows.
struct AuthField<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .font(.title3)
            .padding(.horizontal, 18)
            .frame(minHeight: 58)
            .background(.fill.tertiary, in: .rect(cornerRadius: 18))
    }
}
