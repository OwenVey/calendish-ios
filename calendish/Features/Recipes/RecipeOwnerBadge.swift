import SwiftUI

/// Whose recipe it is, as the owner's avatar in the photo's bottom-trailing corner, opposite the favorite heart.
/// A household recipe shows a house. A household of one shows nothing, since every recipe is theirs.
struct RecipeOwnerBadge: View {
    @Environment(HouseholdStore.self) private var store
    let recipe: Recipe
    var compact = false
    private var size: CGFloat { compact ? 22 : 28 }
    var body: some View {
        if store.members.count > 1, let owner = recipe.owner, let name = store.ownerName(of: recipe) {
            Group {
                if let person = owner.person {
                    MemberAvatar(member: store.members.first { $0.userID == person }, size: size)
                } else {
                    Image(systemName: "house.fill")
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(CalendishStyle.accent)
                        .frame(width: size, height: size)
                        .background(CalendishStyle.surface, in: .circle)
                }
            }
            // A ring keeps the avatar apart from the photo behind it.
            .padding(compact ? 1.5 : 2)
            .background(CalendishStyle.surface, in: .circle)
            .padding(compact ? 2 : 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(owner.person == nil ? "Owned by the household" : store.isMine(recipe) ? "Your recipe" : "\(name)’s recipe")
        }
    }
}

/// A lock on a recipe only you can see. Shared recipes are the norm, so they go unmarked.
struct RecipePrivateIcon: View {
    @Environment(HouseholdStore.self) private var store
    let recipe: Recipe
    var body: some View {
        if store.isMine(recipe), recipe.owner?.isShared == false {
            Image(systemName: "lock.fill").accessibilityLabel("Only me")
        }
    }
}

/// A recipe's title, with the private lock after its last word so it follows the text when the title wraps.
struct RecipeTitle: View {
    @Environment(HouseholdStore.self) private var store
    let recipe: Recipe
    private var isPrivate: Bool { store.isMine(recipe) && recipe.owner?.isShared == false }
    var body: some View {
        // A no-break space keeps the lock from wrapping onto a line by itself.
        let lock = Text(Image(systemName: "lock.fill")).font(.caption).foregroundStyle(.secondary)
        Group {
            if isPrivate { Text("\(recipe.title)\u{00A0}\(lock)") } else { Text(recipe.title) }
        }
        .recipeTitleAccessibility(recipe)
        .accessibilityValue(isPrivate ? "Only me" : "")
    }
}
