import Foundation
import Observation

@Observable
final class RecipeListState {
    var recipes: [Recipe] = []
}

/// Observation's callback is Sendable; protect the counter even though updates
/// in this regression test are synchronous.
final class ObservationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

@main
struct RecipeObservationTests {
    static func main() {
        let original = SampleRecipes.all[0]
        let edits: [(String, (inout Recipe) -> Void)] = [
            ("servings", { $0.servings += 2 }),
            ("prep time", { $0.prepMinutes += 10 }),
            ("cook time", { $0.cookMinutes += 10 }),
            ("title", { $0.title = "An updated recipe" }),
            ("favorite", { $0.isFavorite.toggle() }),
            ("photo", { $0.imagePath = "household/new-photo.jpg" }),
            ("ingredients", { $0.ingredients[0].text = "3 cups tomatoes" }),
        ]
        for (name, edit) in edits {
            let store = RecipeListState()
            store.recipes = [original]
            let notifications = ObservationCounter()
            withObservationTracking { _ = store.recipes } onChange: { notifications.increment() }
            var changed = original
            edit(&changed)
            precondition(changed.id == original.id)
            store.recipes = [changed] // The same assignment used by Supabase refetches.
            precondition(notifications.value == 1, "A remote \(name) edit must notify the visible recipe list")
        }
        let unchanged = RecipeListState()
        unchanged.recipes = [original]
        let notifications = ObservationCounter()
        withObservationTracking { _ = unchanged.recipes } onChange: { notifications.increment() }
        unchanged.recipes = [original]
        precondition(notifications.value == 0, "An unchanged refetch should not redraw the recipe list")
        print("Recipe observation tests passed")
    }
}
