import SwiftUI

struct RecipeDurationPicker: UIViewRepresentable {
    @Binding var minutes: Int
    let title: String

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .countDownTimer
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = 1
        picker.countDownDuration = TimeInterval(min(minutes, 1439) * 60)
        picker.accessibilityLabel = title
        picker.addTarget(context.coordinator, action: #selector(Coordinator.durationChanged(_:)), for: .valueChanged)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.minutes = $minutes
        let duration = TimeInterval(min(minutes, 1439) * 60)
        if picker.countDownDuration != duration {
            picker.countDownDuration = duration
        }
        picker.accessibilityLabel = title
    }

    func makeCoordinator() -> Coordinator { Coordinator(minutes: $minutes) }

    final class Coordinator: NSObject {
        var minutes: Binding<Int>

        init(minutes: Binding<Int>) { self.minutes = minutes }

        @objc func durationChanged(_ picker: UIDatePicker) {
            minutes.wrappedValue = Int((picker.countDownDuration / 60).rounded())
        }
    }
}
