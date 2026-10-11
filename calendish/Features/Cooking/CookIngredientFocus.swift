import Foundation

/// Ingredients tapped in a step, highlighted and scrolled to in cook mode's panel.
/// Each tap gets a new ID so tapping the same name again scrolls again.
struct CookIngredientFocus {
    let id = UUID()
    let ingredients: [UUID]
}
