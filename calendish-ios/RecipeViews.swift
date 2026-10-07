import SwiftUI

struct RecipeBookView: View {
    @Environment(HouseholdStore.self) private var store
    @State private var search = ""
    @State private var selectedTag = "All recipes"
    @State private var alphabetical = false
    @State private var sheet: RecipeSheet?
    private enum RecipeSheet: String, Identifiable {
        case manual, link
        var id: Self { self }
    }
    private var filteredRecipes: [Recipe] {
        let recipes = store.recipes.filter { recipe in
            (selectedTag == "All recipes" || recipe.tag == selectedTag) &&
            (search.isEmpty || ([recipe.title, recipe.summary] + recipe.ingredients.map(\.text)).contains { $0.localizedCaseInsensitiveContains(search) })
        }
        return alphabetical ? recipes.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } : recipes
    }
    private var subtitle: String {
        let count = filteredRecipes.count == 1 ? "1 recipe" : "\(filteredRecipes.count) recipes"
        return selectedTag == "All recipes" ? count : "\(selectedTag) · \(count)"
    }

    var body: some View {
        List {
            ForEach(filteredRecipes) { recipe in
                NavigationLink(value: recipe) { RecipeRow(recipe: recipe) }
            }
        }
        .overlay {
            if filteredRecipes.isEmpty {
                ContentUnavailableView(store.recipes.isEmpty ? "Your recipe book starts here" : "No matching recipes", systemImage: "book.closed", description: Text(store.recipes.isEmpty ? "Save something you love to cook." : "Try another search or tag."))
            }
        }
        .navigationTitle("Recipes")
        .toolbarTitleDisplayMode(.inlineLarge)
        .navigationSubtitle(subtitle)
        .searchable(text: $search, prompt: "Recipes, ingredients, and more")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Sort By") {
                        Picker("Sort By", selection: $alphabetical) {
                            Text("Recently Updated").tag(false)
                            Text("Title A–Z").tag(true)
                        }
                    }
                    Section("Filter") {
                        Picker("Filter", selection: $selectedTag) {
                            Text("All Recipes").tag("All recipes")
                            ForEach(Array(Set(store.recipes.map(\.tag))).sorted(), id: \.self) { Text($0).tag($0) }
                        }
                    }
                } label: {
                    Label("Sort and filter", systemImage: selectedTag == "All recipes" ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Write a recipe", systemImage: "square.and.pencil") { sheet = .manual }
                    Button("Import from a link", systemImage: "link") { sheet = .link }
                } label: { Label("Add recipe", systemImage: "plus") }
            }
        }
        .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .manual: RecipeEditorView()
            case .link: RecipeLinkView()
            }
        }
    }
}

struct RecipeDetailView: View {
    @Environment(HouseholdStore.self) private var store
    let initialRecipe: Recipe
    @State private var checked: Set<UUID> = []
    @State private var showImportOutline = false
    @State private var showEditor = false
    @State private var isCooking = false
    @State private var planning: MealSelection?
    init(recipe: Recipe) { initialRecipe = recipe }
    /// Reads the latest copy from the store so edits show up immediately.
    private var recipe: Recipe { store.recipes.first { $0.id == initialRecipe.id } ?? initialRecipe }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                RecipeArtwork(recipe: recipe).frame(height: 190)
                VStack(alignment: .leading, spacing: 12) {
                    Text(recipe.tag.uppercased()).font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(CalendishStyle.accent)
                    Text(recipe.title).font(.largeTitle.bold())
                    Text(recipe.summary).foregroundStyle(.secondary)
                    HStack(spacing: 24) {
                        Label("\(recipe.minutes) min", systemImage: "clock")
                        Label("\(recipe.servings) servings", systemImage: "person.2")
                    }.font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeading(title: "Ingredients", subtitle: "Check things off as you cook.")
                    ForEach(recipe.ingredients) { ingredient in
                        Button {
                            if checked.contains(ingredient.id) { checked.remove(ingredient.id) }
                            else { checked.insert(ingredient.id) }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: checked.contains(ingredient.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(checked.contains(ingredient.id) ? CalendishStyle.accent : Color.secondary)
                                Text(ingredient.text).strikethrough(checked.contains(ingredient.id)).foregroundStyle(.primary)
                                Spacer()
                            }.padding(.vertical, 12).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityValue(checked.contains(ingredient.id) ? "Checked" : "Unchecked")
                        Divider()
                    }
                }
                VStack(alignment: .leading, spacing: 20) {
                    SectionHeading(title: "Let’s cook")
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(index + 1)").font(.headline).foregroundStyle(CalendishStyle.accent)
                                .frame(width: 30, height: 30).background(CalendishStyle.accent.opacity(0.1), in: Circle())
                            Text(step).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }.padding(20)
        }
        .navigationTitle("Recipe").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Edit") { showEditor = true } }
            ToolbarItem(placement: .bottomBar) {
                Button("Plan", systemImage: "calendar.badge.plus") {
                    let date = store.planningDate
                    let slot = MealSlot.allCases.first { store.meal(on: date, slot: $0) == nil } ?? .dinner
                    planning = MealSelection(date: date, slot: slot, recipeID: recipe.id)
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Add to groceries", systemImage: "basket") { showImportOutline = true }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button { isCooking = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("Start Cooking")
                    }.padding(.horizontal, 6)
                }
                    .modifier(GlassActionStyle(prominent: true))
                    .disabled(recipe.steps.isEmpty)
            }
        }
        .sheet(isPresented: $showEditor) { RecipeEditorView(recipe: recipe) }
        .sheet(item: $planning) { MealPickerView(selection: $0) }
        .fullScreenCover(isPresented: $isCooking) { CookModeView(recipe: recipe, checked: $checked) }
        .sheet(isPresented: $showImportOutline) {
            GroceryImportReviewView(candidates: [GroceryImportCandidate(recipe: recipe, servings: recipe.servings)])
        }
    }
}

struct RecipeEditorView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The recipe being edited, or nil when writing a new one.
    private let original: Recipe?
    @State private var title: String
    @State private var summary: String
    @State private var servings: Int
    @State private var minutes: Int
    @State private var ingredients: [Ingredient]
    @FocusState private var focusedIngredient: Ingredient.ID?
    @State private var steps: [StepDraft]
    @FocusState private var focusedStep: StepDraft.ID?
    init(recipe: Recipe? = nil) {
        original = recipe
        _title = State(initialValue: recipe?.title ?? "")
        _summary = State(initialValue: recipe?.summary ?? "")
        _servings = State(initialValue: recipe?.servings ?? 4)
        _minutes = State(initialValue: recipe?.minutes ?? 30)
        _ingredients = State(initialValue: recipe.map { $0.ingredients.isEmpty ? [Ingredient(text: "")] : $0.ingredients } ?? [Ingredient(text: "")])
        _steps = State(initialValue: recipe.map { $0.steps.isEmpty ? [StepDraft()] : $0.steps.map { StepDraft(text: $0) } } ?? [StepDraft()])
    }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        ingredients.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } &&
        steps.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("The basics") {
                    TextField("Recipe title", text: $title)
                    TextField("A little about this recipe", text: $summary, axis: .vertical)
                    Stepper("Servings: \(servings)", value: $servings, in: 1...1000)
                    Stepper("Total time: \(minutes) min", value: $minutes, in: 0...1440, step: 5)
                }
                Section {
                    ForEach($ingredients) { $ingredient in
                        TextField("e.g. 2 cups flour", text: $ingredient.text)
                            .focused($focusedIngredient, equals: ingredient.id)
                            .submitLabel(.next)
                            .onSubmit { addIngredient(after: ingredient.id) }
                    }
                    .onMove { source, destination in
                        ingredients.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        ingredients.remove(atOffsets: offsets)
                    }

                    Button("Add ingredient", systemImage: "plus") {
                        addIngredient(after: ingredients.last?.id)
                    }
                } header: {
                    Text("Ingredients")
                } footer: {
                    Text("Swipe to delete. Touch and hold to reorder.")
                }
                Section {
                    ForEach($steps) { $step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\((steps.firstIndex { $0.id == step.id } ?? 0) + 1).")
                                .monospacedDigit().foregroundStyle(.secondary)
                            TextField("Describe this step", text: $step.text, axis: .vertical)
                                .lineLimit(3...8)
                                .focused($focusedStep, equals: step.id)
                        }
                    }
                    .onMove { source, destination in
                        steps.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        steps.remove(atOffsets: offsets)
                    }

                    Button("Add step", systemImage: "plus") {
                        let step = StepDraft()
                        steps.append(step)
                        focusedStep = step.id
                    }
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("Swipe to delete. Touch and hold to reorder.")
                }
            }
            .navigationTitle(original == nil ? "New recipe" : "Edit recipe").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let savedIngredients = ingredients.compactMap { ingredient -> Ingredient? in
                            var ingredient = ingredient
                            ingredient.text = ingredient.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            return ingredient.text.isEmpty ? nil : ingredient
                        }
                        let savedSteps = steps.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                        var recipe = original ?? Recipe(title: "", summary: "", minutes: 0, servings: 0, tag: "Homemade", symbol: "fork.knife", ingredients: [], steps: [])
                        recipe.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        recipe.summary = summary
                        recipe.minutes = minutes
                        recipe.servings = servings
                        recipe.ingredients = savedIngredients
                        recipe.steps = savedSteps
                        store.saveRecipe(recipe)
                        dismiss()
                    }.disabled(!canSave)
                }
            }
        }
    }
    private func addIngredient(after id: Ingredient.ID?) {
        let index = ingredients.firstIndex { $0.id == id }.map { $0 + 1 } ?? ingredients.endIndex
        let ingredient = Ingredient(text: "")
        ingredients.insert(ingredient, at: index)
        focusedIngredient = ingredient.id
    }
}

private struct StepDraft: Identifiable {
    let id = UUID()
    var text = ""
}

struct RecipeLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Recipe link") } footer: { Text("Paste a public recipe page. The full import flow will open an editable draft for review before saving.") }
                Section {
                    Label("URL extraction is coming in the next build.", systemImage: "info.circle").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import a recipe").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
