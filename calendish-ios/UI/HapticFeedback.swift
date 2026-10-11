import SwiftUI

extension View {
    /// Plays haptic feedback when `trigger` changes, unless Haptics is off in Settings.
    func hapticFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T,
                                      condition: @escaping (T, T) -> Bool = { _, _ in true }) -> some View {
        modifier(HapticFeedback(feedback: feedback, trigger: trigger, condition: condition))
    }
}

private struct HapticFeedback<T: Equatable>: ViewModifier {
    @AppStorage(PreferenceKey.haptics) private var enabled = true
    let feedback: SensoryFeedback
    let trigger: T
    let condition: (T, T) -> Bool
    func body(content: Content) -> some View {
        content.sensoryFeedback(feedback, trigger: trigger) { old, new in enabled && condition(old, new) }
    }
}
