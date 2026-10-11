import SwiftUI

struct MealPickerView: View {
    let selection: MealSelection
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var recipeID: UUID?
    @State private var keepsSavedVersion = true
    @State private var servings = 4
    @State private var date = Date.now
    @State private var initialValues: String?
    @State private var discardChanges = false
    @AppStorage(WeekStart.storageKey) private var weekStart = WeekStart.system
    private var values: String { "\(keepsSavedVersion)|\(recipeID?.uuidString ?? "")|\(servings)|\(date.timeIntervalSince1970)" }
    private var isDirty: Bool { initialValues != nil && values != initialValues }
    private var recipes: [Recipe] { store.recipes.filter { $0.matches(search) } }

    private func loadSelection() {
        guard initialValues == nil else { return }
        recipeID = selection.meal?.recipeID ?? selection.recipeID
        servings = selection.meal?.servings ?? store.recipes.first { $0.id == recipeID }?.servings ?? PreferenceKey.servingsForNewRecipes
        date = selection.date
        initialValues = values
    }

    private func save() {
        if keepsSavedVersion, let meal = selection.meal {
            store.saveMeal(date: date, recipe: meal.recipe, servings: servings, editing: meal, keepVersion: true)
            dismiss()
        } else if let recipe = store.recipes.first(where: { $0.id == recipeID }) {
            store.saveMeal(date: date, recipe: recipe, servings: servings, editing: selection.meal)
            dismiss()
        }
    }

    private func choose(_ recipe: Recipe) {
        keepsSavedVersion = false
        recipeID = recipe.id
        servings = recipe.servings
    }

    /// Why a recipe is suggested, such as "Rated 4.5 · Last cooked 2 months ago".
    private func suggestionReason(_ recipe: Recipe, stats: RecipeStats?) -> String {
        let liked = stats?.averageRating.map { "Rated \(RecipeRow.formatted($0))" } ?? "Favorite"
        return "\(liked) · \(CookedHistory.lastCookedText(stats?.history))"
    }

    var body: some View {
        let stats = store.recipeStats
        let recipes = recipes
        let suggested = search.isEmpty ? RecipeStats.suggestions(from: store.recipes, stats: stats, meals: store.meals, limit: 3) : []
        NavigationStack {
            List {
                Section {
                    DatePicker("Day", selection: $date, displayedComponents: .date)
                        .environment(\.calendar, weekStart.calendar)
                    ServingsField(servings: $servings)
                }
                if let meal = selection.meal {
                    Section {
                        RecipeRow(recipe: meal.recipe, servings: meal.servings)
                        Toggle("Keep saved version", isOn: $keepsSavedVersion)
                    } header: { Text("Saved recipe version") } footer: { Text("Changing the day or servings keeps this meal’s saved recipe. Turn this off to choose a recipe from your collection.") }
                }
                if !suggested.isEmpty {
                    Section {
                        ForEach(suggested) { recipe in
                            MealRecipeChoice(recipe: recipe, stats: stats[recipe.id], caption: suggestionReason(recipe, stats: stats[recipe.id]),
                                             isSelected: recipeID == recipe.id) { choose(recipe) }
                        }
                    } header: {
                        Text("Suggestions")
                    } footer: {
                        Text("Well-liked recipes you haven’t marked cooked or planned recently.")
                    }
                }
                Section("Choose a recipe") {
                    ForEach(recipes) { recipe in
                        MealRecipeChoice(recipe: recipe, stats: stats[recipe.id], isSelected: recipeID == recipe.id) { choose(recipe) }
                    }
                    if recipes.isEmpty {
                        ContentUnavailableView(store.recipes.isEmpty ? "Add a recipe first" : "No matching recipes", systemImage: "book.closed", description: Text(store.recipes.isEmpty ? "Add a recipe in Recipes, then return to plan a meal." : "Try another search."))
                    }
                }
            }
            .searchable(text: $search, prompt: "Search recipes and ingredients")
            .navigationTitle(selection.meal == nil ? "Plan a meal" : "Edit meal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if isDirty { discardChanges = true } else { dismiss() } }.toolbarGlyph()
                        .confirmationDialog("Discard meal changes?", isPresented: $discardChanges, titleVisibility: .visible) {
                            Button("Discard changes", role: .destructive) { dismiss() }
                            Button("Keep editing") { }
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { OnAccentLabel(title: "Save") }.disabled(!(keepsSavedVersion && selection.meal != nil) && recipeID == nil)
                    .modifier(GlassActionStyle(prominent: true))
                }
            }
            .onAppear(perform: loadSelection)
        }
        .background { DraftDismissalGuard(isDirty: isDirty) { discardChanges = true } }
    }
}
