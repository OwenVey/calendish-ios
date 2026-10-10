import SwiftUI

struct PullHintLabelStyle: LabelStyle {
    let isArmed: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.rotationEffect(.degrees(isArmed ? 180 : 0))
            configuration.title.contentTransition(.opacity)
        }
    }
}
