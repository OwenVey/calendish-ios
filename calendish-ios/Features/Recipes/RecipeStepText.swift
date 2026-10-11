import SwiftUI

/// A recipe step with the ingredients it mentions in the accent color, cook times in the timer color, and temperatures in the temperature color.
/// Tapping an ingredient shows how much the recipe calls for, at the current scale and units, pointing at the tapped word.
struct RecipeStepText: View {
    let step: String
    let recipe: Recipe
    let scale: Double
    let units: MeasurementPreference
    /// Cooking mode reveals the matching rows in its ingredients panel instead of presenting a popover.
    var onIngredientTap: (([UUID]) -> Void)? = nil
    @AppStorage(TemperatureUnit.storageKey) private var temperatureUnit = TemperatureUnit.system
    @State private var frames = MentionFrames()
    @State private var shown: Mention?

    private struct Mention: Identifiable, Equatable, TextAttribute {
        let ingredients: [Int]
        var rect: CGRect = .zero
        var id: [Int] { ingredients }
    }

    private enum Highlight {
        case ingredients([Int])
        case cue(Color)
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
        let displayed = Ingredient.convertTemperatures(in: step, to: temperatureUnit)
        let mentions = IngredientParser.mentions(in: displayed, ingredients: recipe.ingredients.map(\.text))
        let cues = CookTimer.timeRanges(in: displayed).map { ($0, CalendishStyle.timer) }
            + Ingredient.temperatureRanges(in: displayed).map { ($0, CalendishStyle.temperature) }
        let highlights = (mentions.map { ($0.range, Highlight.ingredients($0.ingredients)) }
            + cues.filter { cue in !mentions.contains { $0.range.overlaps(cue.0) } }.map { ($0.0, Highlight.cue($0.1)) })
            .sorted { $0.0.lowerBound < $1.0.lowerBound }
        var text = Text("")
        var position = displayed.startIndex
        for (range, highlight) in highlights where range.lowerBound >= position {
            let word = switch highlight {
            case .ingredients(let ingredients):
                Text(displayed[range]).foregroundStyle(CalendishStyle.accent).customAttribute(Mention(ingredients: ingredients))
            case .cue(let color):
                Text(displayed[range]).foregroundStyle(color)
            }
            text = Text("\(text)\(Text(displayed[position..<range.lowerBound]))\(word)")
            position = range.upperBound
        }
        text = Text("\(text)\(Text(displayed[position...]))")
        return text
            .textRenderer(MentionRenderer(frames: frames))
            .onTapGesture { location in
                // A wrapped name draws as one run per line, so any of its pieces counts.
                select(frames.mentions.first { $0.rect.insetBy(dx: -4, dy: -6).contains(location) })
            }
            .accessibilityActions {
                ForEach(Array(mentions.enumerated()), id: \.offset) { _, mention in
                    Button(String(displayed[mention.range])) {
                        select(frames.mentions.first { $0.ingredients == mention.ingredients } ?? Mention(ingredients: mention.ingredients))
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

    private func select(_ mention: Mention?) {
        guard let mention else { shown = nil; return }
        if let onIngredientTap {
            onIngredientTap(mention.ingredients.filter(recipe.ingredients.indices.contains).map { recipe.ingredients[$0].id })
        } else {
            shown = mention
        }
    }

}
