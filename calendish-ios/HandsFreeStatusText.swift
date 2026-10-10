import SwiftUI

/// A line of status in the voice commands bar, taking the room its buttons leave.
struct HandsFreeStatusText: View {
    let text: String

    var body: some View {
        Text(text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
    }
}
