import SwiftUI

/// An ingredient line with its leading amount, such as "1 cup", in the accent color.
struct IngredientLineText: View {
    let line: String
    var highlightsAmount = true

    var body: some View {
        var text = AttributedString(line)
        if highlightsAmount, let range = IngredientParser.amountRange(in: line),
           let lower = AttributedString.Index(range.lowerBound, within: text),
           let upper = AttributedString.Index(range.upperBound, within: text) {
            text[lower..<upper].foregroundColor = CalendishStyle.accent
        }
        return Text(text)
    }
}

/// A recipe step with the ingredients it mentions in the accent color.
/// Tapping one shows how much the recipe calls for, at the current scale and units, pointing at the tapped word.
struct RecipeStepText: View {
    let step: String
    let recipe: Recipe
    let scale: Double
    let units: MeasurementPreference
    @State private var frames = MentionFrames()
    @State private var shown: Mention?

    private struct Mention: Identifiable, Equatable, TextAttribute {
        let ingredients: [Int]
        var rect: CGRect = .zero
        var id: [Int] { ingredients }
    }

    /// Where each mention was last drawn, in the text's coordinates. Written while drawing, so it doesn't trigger updates.
    private final class MentionFrames {
        var mentions: [Mention] = []
    }

    private struct MentionRenderer: TextRenderer {
        let frames: MentionFrames
        func draw(layout: Text.Layout, in context: inout GraphicsContext) {
            var mentions: [Mention] = []
            for line in layout {
                for run in line {
                    if var mention = run[Mention.self] {
                        mention.rect = run.typographicBounds.rect
                        mentions.append(mention)
                    }
                    context.draw(run)
                }
            }
            frames.mentions = mentions
        }
    }

    var body: some View {
        let displayed = Ingredient.convertTemperatures(in: step, to: units)
        let mentions = IngredientParser.mentions(in: displayed, ingredients: recipe.ingredients.map(\.text))
        var text = Text("")
        var position = displayed.startIndex
        for mention in mentions {
            let word = Text(displayed[mention.range]).foregroundStyle(CalendishStyle.accent).customAttribute(Mention(ingredients: mention.ingredients))
            text = Text("\(text)\(Text(displayed[position..<mention.range.lowerBound]))\(word)")
            position = mention.range.upperBound
        }
        text = Text("\(text)\(Text(displayed[position...]))")
        return text
            .textRenderer(MentionRenderer(frames: frames))
            .onTapGesture { location in
                // A wrapped name draws as one run per line, so any of its pieces counts.
                shown = frames.mentions.first { $0.rect.insetBy(dx: -4, dy: -6).contains(location) }
            }
            .accessibilityActions {
                ForEach(Array(mentions.enumerated()), id: \.offset) { _, mention in
                    Button(String(displayed[mention.range])) {
                        shown = frames.mentions.first { $0.ingredients == mention.ingredients } ?? Mention(ingredients: mention.ingredients)
                    }
                }
            }
            .popover(item: $shown, attachmentAnchor: .rect(.rect(shown?.rect ?? .zero))) { mention in
                let indexes = mention.ingredients.filter(recipe.ingredients.indices.contains)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(indexes, id: \.self) { index in
                        if index != indexes.first {
                            Divider()
                        }
                        IngredientLineText(line: recipe.ingredients[index].display(scale: scale, units: units))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.body)
                .padding(16)
                .presentationCompactAdaptation(.popover)
                .onAppear { TabBarTint.keepsColor(true) }
                .onDisappear { TabBarTint.keepsColor(false) }
            }
    }
}

/// Popovers dim the app's tint behind them, which would gray out the selected tab. The tab bar keeps its color.
private enum TabBarTint {
    static func keepsColor(_ keeps: Bool) {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        for tabBar in windows.flatMap({ tabBars(in: $0) }) { tabBar.tintAdjustmentMode = keeps ? .normal : .automatic }
    }

    private static func tabBars(in view: UIView) -> [UITabBar] {
        if let tabBar = view as? UITabBar { return [tabBar] }
        return view.subviews.flatMap { tabBars(in: $0) }
    }
}
