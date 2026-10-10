import SwiftUI

/// The image sent alongside a shared recipe's text. Always drawn in light mode at a fixed width.
struct RecipeShareCard: View {
    let share: RecipeShare
    let photo: UIImage?
    private var recipe: Recipe { share.recipe }

    /// The card rendered for sharing, with the recipe's photo across the top when it has one.
    static func image(for share: RecipeShare, photo: UIImage?) -> UIImage? {
        let renderer = ImageRenderer(content: RecipeShareCard(share: share, photo: photo))
        renderer.scale = 3
        return renderer.uiImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    if let category = recipe.category {
                        Label(category.title.uppercased(), systemImage: category.systemImage)
                            .font(.footnote.weight(.semibold)).foregroundStyle(CalendishStyle.accent)
                    }
                    Text(recipe.title).font(.title.bold())
                    if let summary = share.summary { Text(summary).font(.subheadline).foregroundStyle(.secondary) }
                }
                HStack(spacing: 8) {
                    ForEach(share.facts, id: \.label) { fact in
                        VStack(spacing: 2) {
                            Text(fact.value).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            Text(fact.label).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(CalendishStyle.accent.opacity(0.1), in: .rect(cornerRadius: 12))
                    }
                }
                if !share.ingredientLines.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ingredients").font(.title3.weight(.semibold))
                        ForEach(share.ingredientLines.prefix(RecipeShare.cardIngredientLimit).enumerated(), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Circle().fill(CalendishStyle.accent).frame(width: 5, height: 5)
                                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                                IngredientLineText(line: line).font(.subheadline)
                            }
                        }
                        moreNote(share.ingredientLines.count - RecipeShare.cardIngredientLimit, of: "ingredient")
                    }
                }
                if !share.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Steps").font(.title3.weight(.semibold))
                        ForEach(share.steps.prefix(RecipeShare.cardStepLimit).enumerated(), id: \.offset) { index, step in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold)).foregroundStyle(CalendishStyle.onAccent)
                                    .frame(width: 22, height: 22)
                                    .background(CalendishStyle.accent, in: .circle)
                                Text(step).font(.subheadline).lineSpacing(3)
                            }
                        }
                        moreNote(share.steps.count - RecipeShare.cardStepLimit, of: "step")
                    }
                }
                Divider()
                HStack(spacing: 10) {
                    BrandIcon(size: 26)
                    Text(RecipeShare.signature).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
        .frame(width: 400, alignment: .leading)
        .background(.white)
        .environment(\.colorScheme, .light)
    }

    /// Points to the full text for what a long recipe's card leaves out.
    @ViewBuilder private func moreNote(_ count: Int, of item: String) -> some View {
        if count > 0 {
            Text("\(count) more \(count == 1 ? item : item + "s") in the message")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var header: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable().scaledToFill()
                .frame(width: 400, height: 280)
                .clipped()
        } else {
            Image(systemName: recipe.symbol)
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(CalendishStyle.accent)
                .frame(width: 400, height: 180)
                .background(CalendishStyle.accent.opacity(0.1))
        }
    }
}
