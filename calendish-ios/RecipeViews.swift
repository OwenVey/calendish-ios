import SwiftUI
import UIKit
import SafariServices
import PhotosUI
import VisionKit
import UniformTypeIdentifiers

struct RecipeBookView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var selectedTag = "All recipes"
    @State private var scope = RecipeScope.all
    @AppStorage(PreferenceKey.recipeSort) private var sort = RecipeSort.recent
    @AppStorage(PreferenceKey.recipeLayout) private var layout = RecipeLayout.list
    @State private var favoritesOnly = false
    @State private var sheet: RecipeSheet?
    @State private var importDrafts = RecipeImportDrafts()
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showScanner = false
    @State private var scannedPages: [Data] = []
    @State private var showFilePicker = false
    @State private var fileError: String?
    @State private var recipeToDelete: Recipe?
    @State private var confirmDelete = false
    @State private var planning: MealSelection?
    @State private var groceryRecipe: Recipe?
    private enum RecipeSheet: Identifiable {
        case manual
        case importing(RecipeImportView.Start)
        var id: String { if case .manual = self { "manual" } else { "import" } }
    }
    private var filteredRecipes: [Recipe] {
        let recipes = store.recipes.filter { recipe in
            scope.includes(recipe, person: store.userID) &&
            (selectedTag == "All recipes" || recipe.tags.contains { $0.caseInsensitiveCompare(selectedTag) == .orderedSame }) &&
            (!favoritesOnly || recipe.isFavorite) &&
            (search.isEmpty || ([recipe.title, recipe.summary, recipe.category?.title ?? ""] + recipe.tags + recipe.ingredients.map(\.text)).contains { $0.localizedCaseInsensitiveContains(search) })
        }
        return sort.sorted(recipes, stats: recipeStats)
    }
    private var recipeStats: [UUID: RecipeStats] { store.recipeStats }
    private var subtitle: String {
        let count = filteredRecipes.count == 1 ? "1 recipe" : "\(filteredRecipes.count) recipes"
        let filters = (favoritesOnly ? ["Favorites"] : []) + (selectedTag == "All recipes" ? [] : [selectedTag])
        return (filters + [count]).joined(separator: " · ")
    }
    private var isFiltered: Bool { favoritesOnly || selectedTag != "All recipes" }

    private var scopePicker: some View {
        Picker("Recipe collection", selection: $scope) {
            ForEach(RecipeScope.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var recipeList: some View {
        let stats = recipeStats
        return List {
            scopePicker.listRowSeparator(.hidden)
            ForEach(filteredRecipes) { recipe in
                NavigationLink(value: recipe) {
                    RecipeRow(recipe: recipe, showsOwner: false, stats: stats[recipe.id], showsLastCooked: sort.showsLastCooked)
                }
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // A destructive swipe button removes the row before confirmation.
                        if store.canEdit(recipe) {
                            Button("Delete", systemImage: "trash") {
                                recipeToDelete = recipe
                                confirmDelete = true
                            }
                            .tint(.red)
                        }
                    }
                    .calendishContextMenu { actions(for: recipe) } preview: { RecipePreview(recipe: recipe) }
            }
        }
    }

    private var recipeGrid: some View {
        let stats = recipeStats
        return ScrollView {
            VStack(spacing: 20) {
                scopePicker
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 2), spacing: 24) {
                    ForEach(filteredRecipes) { recipe in
                        NavigationLink(value: recipe) { RecipeCard(recipe: recipe, stats: stats[recipe.id], showsLastCooked: sort.showsLastCooked) }
                            .buttonStyle(.plain)
                            .calendishContextMenu { actions(for: recipe) } preview: { RecipePreview(recipe: recipe) }
                    }
                }
            }
            // Lines up with the search field above.
            .padding(.horizontal, 20)
            .padding(.bottom)
        }
        .background(CalendishStyle.background)
    }

    @ViewBuilder private func actions(for recipe: Recipe) -> some View {
        Section {
            Button("Plan a meal", systemImage: "calendar.badge.plus") {
                planning = MealSelection(recipeID: recipe.id)
            }
            Button("Add to groceries", systemImage: "basket") { groceryRecipe = recipe }
        }
        Section {
            Button(recipe.isFavorite ? "Remove from favorites" : "Add to favorites", systemImage: recipe.isFavorite ? "star.slash" : "star") {
                store.toggleFavorite(recipe)
            }
        }
        if store.canEdit(recipe) {
            Section {
                Button("Delete recipe", systemImage: "trash", role: .destructive) {
                    recipeToDelete = recipe
                    confirmDelete = true
                }
            }
        }
    }

    var body: some View {
        Group {
            switch layout {
            case .list: recipeList
            case .grid: recipeGrid
            }
        }
        .overlay {
            if filteredRecipes.isEmpty {
                if store.recipes.isEmpty {
                    ContentUnavailableView("Your recipe book starts here", systemImage: "book.closed", description: Text("Add a recipe or import one from a link, text, photo, or PDF."))
                } else if favoritesOnly && search.isEmpty && !store.recipes.contains(where: \.isFavorite) {
                    ContentUnavailableView("No favorites yet", systemImage: "star", description: Text("Open a recipe’s actions menu and choose Add to favorites."))
                } else {
                    ContentUnavailableView("No matching recipes", systemImage: "book.closed", description: Text("Try another search or change the filters."))
                }
            }
        }
        .navigationTitle("Recipes")
        .tabRootStyle()
        .navigationSubtitle(subtitle)
        .searchable(text: $search, prompt: "Search recipes and ingredients")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("View as") {
                        Picker("View as", selection: $layout) {
                            ForEach(RecipeLayout.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                    }
                    Section("Sort by") {
                        Picker("Sort by", selection: $sort) {
                            ForEach(RecipeSort.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    Section("Filter") {
                        Toggle("Favorites only", systemImage: "star", isOn: $favoritesOnly)
                        Picker("Filter", selection: $selectedTag) {
                            Text("All recipes").tag("All recipes")
                            ForEach(store.recipeTags, id: \.self) { Text($0).tag($0) }
                        }
                    }
                } label: {
                    Label("View, sort, and filter", systemImage: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Write a recipe", systemImage: "square.and.pencil") { sheet = .manual }
                    Section {
                        Button("Import from link", systemImage: "link") { sheet = .importing(.link) }
                        Button("Paste recipe text", systemImage: "doc.on.clipboard") { sheet = .importing(.text) }
                    }
                    Section {
                        if VNDocumentCameraViewController.isSupported {
                            Button("Scan with camera", systemImage: "doc.viewfinder") { showScanner = true }
                        }
                        Button("Choose photos", systemImage: "photo.on.rectangle") { showPhotoPicker = true }
                        Button("Choose file", systemImage: "folder") { showFilePicker = true }
                    }
                } label: { Label("New recipe", systemImage: "plus") }
            }
        }
        .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
        .calendishAlert("Delete “\(recipeToDelete?.title ?? "recipe")”?", isPresented: $confirmDelete, presenting: recipeToDelete) { recipe in
            Button("Delete recipe", role: .destructive) {
                store.deleteRecipe(recipe)
                recipeToDelete = nil
            }
            Button("Cancel", role: .cancel) { recipeToDelete = nil }
        } message: { recipe in
            Text(store.deletionExplanation(for: recipe))
        }
        // Drop a link, text, images, or a PDF from another app, as on iPad.
        .dropDestination(for: RecipeImport.self) { items, _ in
            guard let item = RecipeImport.combined(items) else { return false }
            sheet = .importing(.content(item))
            return true
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, maxSelectionCount: 10, selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            sheet = .importing(.photos(items))
            photoItems = []
        }
        .fullScreenCover(isPresented: $showScanner, onDismiss: {
            guard !scannedPages.isEmpty else { return }
            sheet = .importing(.content(.images(scannedPages)))
            scannedPages = []
        }) {
            DocumentScanner { scannedPages = $0 }.ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            do {
                let items = try urls.map { url -> RecipeImport in
                    let isScoped = url.startAccessingSecurityScopedResource()
                    defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    return UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true ? .pdf(data) : .images([data])
                }
                if let item = RecipeImport.combined(items) { sheet = .importing(.content(item)) }
            } catch {
                fileError = InterfaceCopy.failure(error, action: "open the file", recovery: "Choose another file and try again.")
            }
        }
        .calendishAlert("Couldn’t open file", isPresented: Binding(get: { fileError != nil }, set: { if !$0 { fileError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(fileError ?? "")
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .manual: RecipeEditorView()
            case .importing(let start): RecipeImportView(start: start, drafts: $importDrafts)
            }
        }
        .sheet(item: $planning) { MealPickerView(selection: $0) }
        .sheet(item: $groceryRecipe) { recipe in
            GroceryImportReviewView(candidates: [GroceryImportCandidate(recipe: recipe, servings: recipe.servings)])
        }
    }
}

/// A recipe's photo with its title and time below, for the recipe book's grid.
private struct RecipeCard: View {
    @Environment(HouseholdStore.self) private var store
    let recipe: Recipe
    var stats: RecipeStats?
    var showsLastCooked = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RecipeArtwork(recipe: recipe)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if recipe.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .padding(6)
                            .background(.ultraThinMaterial, in: .circle)
                            .padding(8)
                            .accessibilityLabel("Favorite")
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title).font(.headline).lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.caption2).accessibilityHidden(true)
                    Text("\(recipe.minutes) min")
                    if let rating = stats?.averageRating {
                        Image(systemName: "star.fill").font(.caption2).padding(.leading, 4).accessibilityHidden(true)
                        Text(RecipeRow.formatted(rating)).accessibilityLabel(InterfaceCopy.rating(RecipeRow.formatted(rating)))
                    }
                    if store.isMine(recipe) && recipe.owner?.isShared == false {
                        Image(systemName: "lock.fill").font(.caption2).accessibilityLabel("Only me")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if showsLastCooked {
                    Text(CookedHistory.lastCookedText(stats?.history)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 2)
        }
        .contentShape(.rect)
    }
}

/// A recipe's photo and details, shown when pressing and holding it in the recipe book.
private struct RecipePreview: View {
    let recipe: Recipe
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RecipeArtwork(recipe: recipe).aspectRatio(4 / 3, contentMode: .fit)
            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.title).font(.title3.weight(.semibold))
                if !recipe.summary.isEmpty {
                    Text(recipe.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .frame(width: 320)
    }
}

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
                        Text(owner + (store.isMine(recipe) ? (recipe.owner?.isShared == true ? " · Shared with household" : " · Only me") : ""))
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
                    servingsStepper
                    ForEach(recipe.ingredients) { ingredient in
                        Button {
                            if checked.contains(ingredient.id) { checked.remove(ingredient.id) }
                            else { checked.insert(ingredient.id) }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: checked.contains(ingredient.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(checked.contains(ingredient.id) ? CalendishStyle.accent : Color.secondary)
                                IngredientLineText(line: ingredient.display(scale: scale, units: units)).strikethrough(checked.contains(ingredient.id)).foregroundStyle(.primary)
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
                            Text("\(index + 1).").font(.headline).foregroundStyle(.secondary)
                                .frame(minWidth: 30, alignment: .leading)
                            RecipeStepText(step: step, recipe: recipe, scale: scale, units: units).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }.padding(20)
            .coordinateSpace(name: "recipeContent")
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
    private var ingredientsSubtitle: String {
        guard isScaled else { return "Check things off as you cook." }
        let scaledYield = recipe.yieldText.map { " · Makes \(Ingredient.scale($0, by: scale))" } ?? ""
        return "Scaled from \(InterfaceCopy.servings(recipe.servings))\(scaledYield)."
    }

    private var servingsStepper: some View {
        HStack(spacing: 12) {
            Label {
                Text(InterfaceCopy.servings(servings)).monospacedDigit().contentTransition(.numericText(value: Double(servings)))
            } icon: { Image(systemName: "person.2") }
            if isScaled {
                Button("Reset") { scaledServings = nil }
                    .font(.subheadline)
                    .accessibilityLabel("Reset to \(InterfaceCopy.servings(recipe.servings))")
                    .transition(.opacity)
            }
            Spacer()
            Stepper("Servings", value: Binding(get: { servings }, set: { scaledServings = $0 }), in: 1...100)
                .labelsHidden()
                .accessibilityValue(InterfaceCopy.servings(servings))
        }
        .padding(.vertical, 6)
        .animation(reduceMotion ? nil : .snappy, value: servings)
        .sensoryFeedback(.selection, trigger: servings)
    }
}

private struct RecipeSourceBrowser: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { dismiss() }
    }
}

struct RecipeEditorView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var editing: RecipeDraftEditing
    private let isImported: Bool
    private let importedWithoutIngredients: Bool
    private let importedWithoutInstructions: Bool
    @State private var discardChanges = false
    @FocusState private var isTagFieldFocused: Bool
    @FocusState private var focusedIngredient: Ingredient.ID?
    @FocusState private var focusedStep: RecipeDraftEditing.Step.ID?

    init(recipe: Recipe? = nil, imported: ImportedRecipe? = nil) {
        isImported = imported != nil
        importedWithoutIngredients = imported?.recipe.ingredients.isEmpty == true
        importedWithoutInstructions = imported?.recipe.steps.isEmpty == true
        _editing = State(initialValue: RecipeDraftEditing(recipe: recipe, imported: imported,
            defaultServings: PreferenceKey.servingsForNewRecipes))
    }
    var body: some View {
        @Bindable var editing = editing
        NavigationStack {
            Form {
                if isImported {
                    Section {
                        Text("Check the ingredients, steps, and servings before saving.")
                        if importedWithoutIngredients && !editing.fields.ingredients.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                            Text("No ingredients were imported.")
                        }
                        if importedWithoutInstructions && !editing.fields.steps.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                            Text("No instructions were imported.")
                        }
                    }
                }
                Section {
                    TextField("Recipe title", text: $editing.fields.title)
                        .font(.title3.weight(.semibold))
                    ServingsField(servings: $editing.fields.servings)
                    RecipeDurationField(title: "Prep time", minutes: $editing.fields.prepMinutes)
                    RecipeDurationField(title: "Cook time", minutes: $editing.fields.cookMinutes)
                } footer: {
                    if !editing.canSave { Text("To save, add a title and at least one ingredient or instruction.") }
                }
                Section {
                    PhotoSourceMenu(hasPhoto: editing.hasPhoto, onPick: editing.setPhoto, onRemove: { editing.setPhoto(nil) }) {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill))
                                if let newPhoto = editing.photo {
                                    Image(uiImage: newPhoto).resizable().scaledToFill()
                                } else if let keptPhotoPath = editing.keptPhotoPath {
                                    RecipePhoto(path: keptPhotoPath)
                                } else {
                                    Image(systemName: "camera").font(.title3).foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(.rect(cornerRadius: 10))
                            Text(editing.hasPhoto ? "Edit photo" : "Add photo")
                                .foregroundStyle(CalendishStyle.accent)
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(editing.hasPhoto ? "Edit photo" : "Add photo")
                }
                Section {
                    ForEach($editing.fields.ingredients) { $ingredient in
                        TextField("e.g. 2 cups flour", text: $ingredient.text)
                            .focused($focusedIngredient, equals: ingredient.id)
                            .submitLabel(.next)
                            .onSubmit { addIngredient(after: ingredient.id) }
                    }
                    .onMove { source, destination in
                        editing.fields.ingredients.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        editing.fields.ingredients.remove(atOffsets: offsets)
                    }

                    Button("Add ingredient", systemImage: "plus.circle.fill") {
                        addIngredient(after: editing.fields.ingredients.last?.id)
                    }
                } header: {
                    Text("Ingredients")
                } footer: {
                    Text("Add ingredients here. Drag the handles to reorder.")
                }
                Section {
                    ForEach($editing.fields.steps) { $step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\((editing.fields.steps.firstIndex { $0.id == step.id } ?? 0) + 1).")
                                .monospacedDigit().foregroundStyle(.secondary)
                            TextField("Describe this step", text: $step.text, axis: .vertical)
                                .lineLimit(3...8)
                                .focused($focusedStep, equals: step.id)
                        }
                    }
                    .onMove { source, destination in
                        editing.fields.steps.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        editing.fields.steps.remove(atOffsets: offsets)
                    }

                    Button("Add step", systemImage: "plus.circle.fill") {
                        let step = RecipeDraftEditing.Step()
                        editing.fields.steps.append(step)
                        focusedStep = step.id
                    }
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("Add cooking steps here. Drag the handles to reorder.")
                }
                Section("Details") {
                    LabeledFormField("Description") {
                        TextField("A little about this recipe", text: $editing.fields.summary, axis: .vertical)
                    }
                    LabeledFormField("Source link") {
                        TextField("https://", text: $editing.fields.sourceLink)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Picker("Category", selection: $editing.fields.category) {
                        Text("None").tag(RecipeCategory?.none)
                        ForEach(RecipeCategory.allCases) { category in
                            Label(category.title, systemImage: category.systemImage).tag(Optional(category))
                        }
                    }
                    .tint(.secondary)
                    LabeledFormField("Makes") {
                        TextField("24 cookies", text: $editing.fields.yieldText)
                    }
                }
                Section {
                    if !editing.fields.tags.isEmpty {
                        FlowLayout {
                            ForEach(editing.fields.tags, id: \.self) { tag in
                                Button { withAnimation(reduceMotion ? nil : .default) { editing.fields.tags.removeAll { $0 == tag } } } label: {
                                    TagPill(tag: tag, systemImage: "xmark").frame(minHeight: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove tag \(tag)")
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    TextField("Add a tag", text: $editing.fields.newTag)
                        .focused($isTagFieldFocused)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit {
                            guard addTag(editing.fields.newTag) else { return }
                            isTagFieldFocused = true
                        }
                    if !tagSuggestions.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(tagSuggestions, id: \.self) { tag in
                                    Button { addTag(tag) } label: { TagPill(tag: tag, systemImage: "plus", muted: true).frame(minHeight: 44) }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Add tag \(tag)")
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .scrollIndicators(.hidden)
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                    }
                } header: {
                    Text("Tags")
                } footer: {
                    if !editing.fields.tags.isEmpty { Text("Tap a tag to remove it.") }
                }
                if editing.isNew {
                    Section {
                        Toggle("Share with household", isOn: $editing.fields.isShared)
                    } footer: {
                        Text(editing.fields.isShared ? "Your household will be able to see and cook this recipe. Only you will be able to edit it." : "This recipe will be private.")
                    }
                }
            }
            // Always editing, so ingredient and step rows show the delete control and drag handle.
            .environment(\.editMode, .constant(.active))
            .navigationTitle(isImported ? "Review recipe" : editing.isNew ? "New recipe" : "Edit recipe").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if editing.isDirty { discardChanges = true } else { dismiss() } }.toolbarGlyph()
                        .confirmationDialog("Discard recipe changes?", isPresented: $discardChanges, titleVisibility: .visible) {
                            Button("Discard changes", role: .destructive) { editing.discard(); dismiss() }
                            Button("Keep editing") { }
                        } message: { Text("Your draft stays on this device until you save or discard it.") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if editing.save(knownTags: store.recipeTags, using: { recipe, photo, onSaved in
                            store.saveRecipe(recipe, photo: photo, onSaved: onSaved)
                        }) { dismiss() }
                    } label: { OnAccentLabel(title: "Save") }
                    .disabled(!editing.canSave)
                    .modifier(GlassActionStyle(prominent: true))
                }
            }
        }
        .background { DraftDismissalGuard(isDirty: editing.isDirty && !editing.isClosing) { discardChanges = true } }
        .onAppear { editing.open(accountID: store.userID) }
        .onChange(of: store.userID) { _, account in editing.open(accountID: account) }
    }
    private var tagSuggestions: [String] { editing.tagSuggestions(in: store.recipeTags) }

    @discardableResult
    private func addTag(_ text: String) -> Bool {
        withAnimation(reduceMotion ? nil : .default) { editing.addTag(text, knownTags: store.recipeTags) }
    }

    private func addIngredient(after id: Ingredient.ID?) {
        focusedIngredient = editing.addIngredient(after: id)
    }
}

/// A form field whose label stays visible above its value, so filled-in rows still say what they are.
private struct LabeledFormField<Field: View>: View {
    let title: String
    @ViewBuilder var field: Field
    init(_ title: String, @ViewBuilder field: () -> Field) {
        self.title = title
        self.field = field()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            field
        }
        .accessibilityElement(children: .combine)
    }
}

/// Expands a compact form row into the system's hour/minute duration wheels.
private struct RecipeDurationField: View {
    let title: String
    @Binding var minutes: Int

    private var formattedDuration: String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    var body: some View {
        DisclosureGroup {
            RecipeDurationPicker(minutes: $minutes, title: title)
                .frame(maxWidth: .infinity)
                .frame(height: 180)
        } label: {
            LabeledContent(title, value: formattedDuration)
        }
    }
}

private struct RecipeDurationPicker: UIViewRepresentable {
    @Binding var minutes: Int
    let title: String

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .countDownTimer
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = 1
        picker.countDownDuration = TimeInterval(min(minutes, 1439) * 60)
        picker.accessibilityLabel = title
        picker.addTarget(context.coordinator, action: #selector(Coordinator.durationChanged(_:)), for: .valueChanged)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.minutes = $minutes
        let duration = TimeInterval(min(minutes, 1439) * 60)
        if picker.countDownDuration != duration {
            picker.countDownDuration = duration
        }
        picker.accessibilityLabel = title
    }

    func makeCoordinator() -> Coordinator { Coordinator(minutes: $minutes) }

    final class Coordinator: NSObject {
        var minutes: Binding<Int>

        init(minutes: Binding<Int>) { self.minutes = minutes }

        @objc func durationChanged(_ picker: UIDatePicker) {
            minutes.wrappedValue = Int((picker.countDownDuration / 60).rounded())
        }
    }
}
