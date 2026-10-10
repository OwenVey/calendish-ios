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
