import SwiftUI

/// A read-only rating, such as another member's.
struct StarsLabel: View {
    let rating: Int
    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating ? Color.yellow : Color.secondary)
            }
        }
        .font(.caption)
        .accessibilityElement()
        .accessibilityLabel(rating == 1 ? "1 star" : "\(rating) stars")
    }
}
