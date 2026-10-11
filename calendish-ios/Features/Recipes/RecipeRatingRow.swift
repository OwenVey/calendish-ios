import SwiftUI

/// Keep every star reachable when the member label and rating don't fit on one line.
struct RecipeRatingRow: View {
    let member: HouseholdMember?
    @Binding var rating: Int?

    var body: some View {
        let identity = HStack(spacing: 10) {
            MemberAvatar(member: member, size: 28)
            Text("You").font(.headline)
        }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                identity.fixedSize()
                Spacer(minLength: 0)
                StarRating(rating: $rating).fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                identity
                StarRating(rating: $rating)
            }
        }
    }
}
