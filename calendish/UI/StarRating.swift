import SwiftUI

/// One to five stars. Tapping the current rating clears it.
struct StarRating: View {
    @Binding var rating: Int?
    var size: Font = .title2
    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    rating = rating == star ? nil : star
                } label: {
                    Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                        .font(size)
                        .foregroundStyle(star <= (rating ?? 0) ? Color.yellow : Color.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(star == 1 ? "Rate 1 star" : "Rate \(star) stars")
                .accessibilityValue(rating == star ? "Selected" : "Not selected")
                .accessibilityAddTraits(rating == star ? .isSelected : [])
                .accessibilityHint(rating == star ? "Tap again to clear your rating." : "Sets your rating.")
            }
        }
        .hapticFeedback(.selection, trigger: rating)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your rating")
        .accessibilityValue(rating.map { $0 == 1 ? "1 star" : "\($0) stars" } ?? "Not rated")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(5, (rating ?? 0) + 1)
            case .decrement: rating = (rating ?? 0) <= 1 ? nil : (rating ?? 0) - 1
            @unknown default: break
            }
        }
    }
}
