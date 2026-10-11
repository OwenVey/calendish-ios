import SwiftUI

extension EnvironmentValues {
    /// Shows a saved recipe in the Recipes tab, such as one an import turned out to duplicate.
    @Entry var openRecipe: (Recipe) -> Void = { _ in }
}
