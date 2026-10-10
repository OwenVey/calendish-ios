import SwiftUI

struct AuthButton: View {
    let title: String
    let working: Bool
    var workingTitle = "Working"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(working ? 0 : 1)
                if working { ProgressView().tint(CalendishStyle.onAccent) }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .modifier(GlassActionStyle(prominent: true))
        .controlSize(.large)
        .accessibilityLabel(working ? workingTitle : title)
    }
}
