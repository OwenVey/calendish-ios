import SwiftUI
import UniformTypeIdentifiers

struct RecipeDetailView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let initialRecipe: Recipe
    let plannedMeal: PlannedMeal?
    @State private var checked: Set<UUID> = []
    /// Servings the cook scaled to, or nil to use the recipe as written.
    @State private var scaledServings: Int?
    @AppStorage(MeasurementPreference.storageKey) private var units = MeasurementPreference.original
    @State private var showImportOutline = false
    @State private var showEditor = false
    @State private var confirmDelete = false
    @State private var confirmSharing = false
    @State private var savingCopy = false
    @State private var savedCopy: Recipe?
    @State private var isCooking = false
    @State private var planning: MealSelection?
    @State private var sourceToVisit: RecipeSource?
    @State private var sharing: ActivitySheet.Items?
    @State private var preparingShare = false
    private struct RecipeSource: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }
    /// Bottom edge of the large title within the scroll content; the nav bar title appears once it scrolls under the bar.
    @State private var titleBottom: CGFloat = .infinity
    @State private var showsNavTitle = false
    init(recipe: Recipe, plannedMeal: PlannedMeal? = nil) { initialRecipe = recipe; self.plannedMeal = plannedMeal }
    /// Reads the latest copy from the store so edits show up immediately.
    private var recipe: Recipe { plannedMeal?.recipe ?? store.recipes.first { $0.id == initialRecipe.id } ?? initialRecipe }
    private var servings: Int { scaledServings ?? plannedMeal?.servings ?? recipe.servings }
    private var isScaled: Bool { servings != recipe.servings && recipe.servings > 0 }
    private var scale: Double { isScaled ? Double(servings) / Double(recipe.servings) : 1 }
    /// The recipe in the person's book that ratings, notes, and cooked history belong to. A planned meal's
    /// saved version uses its source recipe, while that still exists.
    private var reviewedRecipeID: UUID? {
        CookedHistory.recipeID(cooking: recipe, plannedMeal: plannedMeal, in: store.recipes)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                RecipeArtwork(recipe: recipe)
                    .frame(height: recipe.imagePath == nil ? 190 : 260)
                    .overlay(alignment: .bottomTrailing) {
                        if recipe.imagePath == nil && plannedMeal == nil && store.canEdit(recipe) {
                            PhotoSourceMenu(hasPhoto: false, onPick: { store.saveRecipe(recipe, photo: .replace($0)) }, onRemove: {}) {
                                Label("Add photo", systemImage: "camera")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .glassEffect(.regular.interactive(), in: .capsule)
                            }
                            .padding(12)
                        }
                    }
                VStack(alignment: .leading, spacing: 12) {
                    if let category = recipe.category {
                        Label(category.title.uppercased(), systemImage: category.systemImage)
                            .font(.footnote.weight(.semibold)).foregroundStyle(CalendishStyle.accent)
                            .accessibilityLabel("Category: \(category.title)")
                    }
                    Text(recipe.title).font(.largeTitle.bold())
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("recipeContent")).maxY } action: { titleBottom = $0 }
                    if let owner = store.ownerName(of: recipe) {
                        Group {
                            if !store.isMine(recipe) { Text(owner) }
                            else if recipe.owner?.isShared == true { Text("\(owner) · Shared with household") }
                            else { Text("\(owner) · Only me") }
                        }
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if plannedMeal != nil { Text("Recipe version saved with this meal").font(.subheadline).foregroundStyle(.secondary) }
                    Text(recipe.summary).foregroundStyle(.secondary)
                    FlowLayout(spacing: 16) {
                        Label("Prep: \(recipe.prepMinutes) min", systemImage: "clock")
                            .accessibilityLabel("Preparation time: \(InterfaceCopy.minutes(recipe.prepMinutes))")
                        Label("Cook: \(recipe.cookMinutes) min", systemImage: "flame")
                            .accessibilityLabel("Cooking time: \(InterfaceCopy.minutes(recipe.cookMinutes))")
                        Label(InterfaceCopy.servings(recipe.servings), systemImage: "person.2")
                        if let yieldText = recipe.yieldText { Label("Makes \(yieldText)", systemImage: "square.grid.2x2") }
                    }.font(.subheadline).foregroundStyle(.secondary)
                    if !recipe.tags.isEmpty {
                        FlowLayout {
                            ForEach(recipe.tags, id: \.self) { TagPill(tag: $0) }
                        }
                        .padding(.top, 4)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Tags: \(recipe.tags.formatted(.list(type: .and)))")
                    }
                }
                if let reviewedRecipeID { RecipeNotesSection(recipeID: reviewedRecipeID) }
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeading(title: "Ingredients", subtitle: ingredientsSubtitle)
                    RecipeServingsStepper(servings: servings, recipeServings: recipe.servings, scaledServings: $scaledServings)
                    VStack(spacing: 0) {
                        ForEach(recipe.ingredients) { ingredient in
                            Button {
                                if checked.contains(ingredient.id) { checked.remove(ingredient.id) }
                                else { checked.insert(ingredient.id) }
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: checked.contains(ingredient.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3).foregroundStyle(checked.contains(ingredient.id) ? CalendishStyle.accent : Color.secondary)
                                    IngredientLineText(line: ingredient.display(scale: scale, units: units)).strikethrough(checked.contains(ingredient.id)).foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 12)
                                        // Separators start at the text, like a system list, and stop after the last ingredient.
                                        .overlay(alignment: .bottom) {
                                            if ingredient.id != recipe.ingredients.last?.id { Divider() }
                                        }
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityValue(checked.contains(ingredient.id) ? "Checked" : "Unchecked")
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 20) {
                    SectionHeading(title: "Instructions")
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(index + 1).").font(.headline).foregroundStyle(.secondary)
                                .frame(minWidth: 30, alignment: .leading)
                            RecipeStepText(step: step, recipe: recipe, scale: scale, units: units).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }.padding(20)
            .coordinateSpace(.named("recipeContent"))
        }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > titleBottom } action: { _, scrolledPast in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showsNavTitle = scrolledPast }
        }
        .navigationTitle(recipe.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(recipe.title).font(.headline).lineLimit(1)
                    .opacity(showsNavTitle ? 1 : 0)
                    .accessibilityHidden(!showsNavTitle)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section {
                        Button(plannedMeal == nil ? "Plan a meal" : "Edit planned meal", systemImage: "calendar.badge.plus") {
                            if let plannedMeal {
                                planning = MealSelection(date: plannedMeal.date, meal: plannedMeal)
                                return
                            }
                            planning = MealSelection(recipeID: recipe.id)
                        }
                        Button("Add to groceries", systemImage: "basket") { showImportOutline = true }
                        if let link = recipe.recipeLink, let url = RecipeLinkImporter.validatedURL(link) {
                            Button("Visit source", systemImage: "safari") { sourceToVisit = RecipeSource(url: url) }
                        }
                        Button("Share recipe", systemImage: "square.and.arrow.up") {
                            Task { await shareRecipe() }
                        }.disabled(preparingShare)
                    }
                    Section {
                        if plannedMeal == nil {
                        Button(recipe.isFavorite ? "Remove from favorites" : "Add to favorites", systemImage: recipe.isFavorite ? "star.slash" : "star") {
                            store.toggleFavorite(recipe)
                        }
                        }
                        if plannedMeal == nil && !store.isMine(recipe) {
                            Button("Save to my collection", systemImage: "square.and.arrow.down") {
                                savingCopy = true
                                Task {
                                    defer { savingCopy = false }
                                    do { savedCopy = try await store.saveCopy(of: recipe) }
                                    catch {
                                        store.errorTitle = "Couldn’t save a recipe copy"
                                        store.errorMessage = InterfaceCopy.recoveryMessage(error, fallback: "Check your collection before trying again.")
                                    }
                                }
                            }.disabled(savingCopy)
                        }
                        if let plannedMeal, store.latestRecipe(for: plannedMeal) != nil {
                            Button("Use latest recipe version", systemImage: "arrow.clockwise") {
                                store.updateMealToLatest(plannedMeal)
                                dismiss()
                            }.disabled(!store.hasNewerVersion(plannedMeal))
                                .accessibilityHint("Replaces this meal’s saved ingredients and instructions")
                        }
                        if plannedMeal == nil && store.isMine(recipe) {
                            Button(recipe.owner?.isShared == true ? "Make private" : "Share with household", systemImage: "person.2") { confirmSharing = true }
                        }
                    }
                    if plannedMeal == nil && store.canEdit(recipe) {
                        Section {
                            Button("Delete recipe", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        }
                    }
                } label: {
                    Label("More recipe actions", systemImage: "ellipsis")
                }
                .sensoryFeedback(.selection, trigger: recipe.isFavorite)
                .confirmationDialog("Delete “\(recipe.title)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete recipe", role: .destructive) {
                        store.deleteRecipe(recipe)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(store.deletionExplanation(for: recipe))
                }
            }
            if plannedMeal == nil && store.canEdit(recipe) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit recipe", systemImage: "pencil") { showEditor = true }
                        .labelStyle(.iconOnly).toolbarGlyph()
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button { isCooking = true } label: { OnAccentLabel(title: "Cook", systemImage: "frying.pan") }
                    .labelStyle(.iconOnly)
                    .modifier(GlassActionStyle(prominent: true))
                    .disabled(recipe.steps.isEmpty)
                    .accessibilityHint("Opens step-by-step cooking instructions")
            }

        }
        .confirmationDialog(recipe.owner?.isShared == true ? "Make private?" : "Share with household?", isPresented: $confirmSharing, titleVisibility: .visible) {
            Button(recipe.owner?.isShared == true ? "Make private" : "Share with household") {
                store.setSharing(recipe, shared: recipe.owner?.isShared != true)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(recipe.owner?.isShared == true
                 ? "Your household keeps a separate copy of this recipe. Only you can access your original and future edits."
                 : "Your household can see and cook this recipe. Only you can edit your original. If you stop sharing, delete it, or leave, the household keeps a separate copy.")
        }
        .sheet(item: $savedCopy) { copy in NavigationStack { RecipeDetailView(recipe: copy) } }
        .sheet(isPresented: $showEditor) { RecipeEditorView(recipe: recipe) }
        .sheet(item: $planning) { MealPickerView(selection: $0) }
        .sheet(item: $sharing) { items in
            ActivitySheet(items: items.values)
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .sheet(item: $sourceToVisit) { source in
            RecipeSourceBrowser(url: source.url)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isCooking) { CookModeView(recipe: recipe, cookedRecipeID: reviewedRecipeID, servings: servings, checked: $checked) }
        .sheet(isPresented: $showImportOutline) {
            GroceryImportReviewView(candidates: [GroceryImportCandidate(recipe: recipe, servings: servings)])
        }
    }
}

extension RecipeDetailView {
    /// Shares the recipe as text plus a card image, at the servings and units on screen.
    private func shareRecipe() async {
        preparingShare = true
        defer { preparingShare = false }
        let share = RecipeShare(recipe: recipe, servings: servings, units: units)
        let photo: UIImage? = if let path = recipe.imagePath { await RecipePhotos.shared.image(for: path, thumbnail: false) } else { nil }
        var items: [Any] = [share.text]
        if let card = RecipeShareCard.image(for: share, photo: photo) { items.append(card) }
        sharing = ActivitySheet.Items(values: items)
    }

    private var ingredientsSubtitle: String {
        guard isScaled else { return "Check things off as you cook." }
        let scaledYield = recipe.yieldText.map { " · Makes \(Ingredient.scale($0, by: scale))" } ?? ""
        return "Scaled from \(InterfaceCopy.servings(recipe.servings))\(scaledYield)."
    }
}
