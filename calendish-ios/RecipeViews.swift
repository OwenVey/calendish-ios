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
    @State private var alphabetical = false
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
    private enum RecipeSheet: Identifiable {
        case manual
        case importing(RecipeImportView.Start)
        var id: String { if case .manual = self { "manual" } else { "import" } }
    }
    private var filteredRecipes: [Recipe] {
        let recipes = store.recipes.filter { recipe in
            (selectedTag == "All recipes" || recipe.tags.contains { $0.caseInsensitiveCompare(selectedTag) == .orderedSame }) &&
            (!favoritesOnly || recipe.isFavorite) &&
            (search.isEmpty || ([recipe.title, recipe.summary, recipe.category ?? ""] + recipe.tags + recipe.ingredients.map(\.text)).contains { $0.localizedCaseInsensitiveContains(search) })
        }
        return alphabetical ? recipes.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } : recipes
    }
    private var subtitle: String {
        let count = filteredRecipes.count == 1 ? "1 recipe" : "\(filteredRecipes.count) recipes"
        let filters = (favoritesOnly ? ["Favorites"] : []) + (selectedTag == "All recipes" ? [] : [selectedTag])
        return (filters + [count]).joined(separator: " · ")
    }
    private var isFiltered: Bool { favoritesOnly || selectedTag != "All recipes" }

    var body: some View {
        List {
            ForEach(filteredRecipes) { recipe in
                NavigationLink(value: recipe) { RecipeRow(recipe: recipe) }
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // A destructive swipe button removes the row before confirmation.
                        Button("Delete", systemImage: "trash") {
                            recipeToDelete = recipe
                            confirmDelete = true
                        }
                        .tint(.red)
                    }
            }
        }
        .overlay {
            if filteredRecipes.isEmpty {
                if store.recipes.isEmpty {
                    ContentUnavailableView("Your recipe book starts here", systemImage: "book.closed", description: Text("Save something you love to cook."))
                } else if favoritesOnly && search.isEmpty && !store.recipes.contains(where: \.isFavorite) {
                    ContentUnavailableView("No favorites yet", systemImage: "star", description: Text("Choose Add to Favorites from a recipe’s More menu to save it here."))
                } else {
                    ContentUnavailableView("No matching recipes", systemImage: "book.closed", description: Text("Try another search or tag."))
                }
            }
        }
        .refreshable { await store.refresh() }
        .navigationTitle("Recipes")
        .tabRootStyle()
        .navigationSubtitle(subtitle)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Recipes, ingredients, and more")
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
                        Toggle("Favorites Only", systemImage: "star", isOn: $favoritesOnly)
                        Picker("Filter", selection: $selectedTag) {
                            Text("All Recipes").tag("All recipes")
                            ForEach(store.recipeTags, id: \.self) { Text($0).tag($0) }
                        }
                    }
                } label: {
                    Label("Sort and filter", systemImage: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add Manually", systemImage: "square.and.pencil") { sheet = .manual }
                    Section {
                        Button("Import from Link", systemImage: "link") { sheet = .importing(.link) }
                        Button("Paste Recipe Text", systemImage: "doc.on.clipboard") { sheet = .importing(.text) }
                    }
                    Section {
                        if VNDocumentCameraViewController.isSupported {
                            Button("Scan with Camera", systemImage: "doc.viewfinder") { showScanner = true }
                        }
                        Button("Choose from Photos", systemImage: "photo.on.rectangle") { showPhotoPicker = true }
                        Button("Choose File", systemImage: "folder") { showFilePicker = true }
                    }
                } label: { Label("Add recipe", systemImage: "plus") }
            }
        }
        .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
        .confirmationDialog("Delete “\(recipeToDelete?.title ?? "recipe")”?", isPresented: $confirmDelete, titleVisibility: .visible, presenting: recipeToDelete) { recipe in
            Button("Delete Recipe", role: .destructive) {
                store.deleteRecipe(recipe)
                recipeToDelete = nil
            }
            Button("Cancel", role: .cancel) { recipeToDelete = nil }
        } message: { _ in
            Text("This deletes the recipe and any meals planned with it for your household. Grocery items will stay on your list. This can’t be undone.")
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
                fileError = error.localizedDescription
            }
        }
        .alert("Couldn’t Open File", isPresented: Binding(get: { fileError != nil }, set: { if !$0 { fileError = nil } })) {
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
    }
}

struct RecipeDetailView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let initialRecipe: Recipe
    @State private var checked: Set<UUID> = []
    /// Servings the cook scaled to, or nil to use the recipe as written.
    @State private var scaledServings: Int?
    @State private var showImportOutline = false
    @State private var showEditor = false
    @State private var confirmDelete = false
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
    init(recipe: Recipe) { initialRecipe = recipe }
    /// Reads the latest copy from the store so edits show up immediately.
    private var recipe: Recipe { store.recipes.first { $0.id == initialRecipe.id } ?? initialRecipe }
    private var servings: Int { scaledServings ?? recipe.servings }
    private var isScaled: Bool { servings != recipe.servings && recipe.servings > 0 }
    private var scale: Double { isScaled ? Double(servings) / Double(recipe.servings) : 1 }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                RecipeArtwork(recipe: recipe)
                    .frame(height: recipe.imagePath == nil ? 190 : 260)
                    .overlay(alignment: .bottomTrailing) {
                        if recipe.imagePath == nil {
                            PhotoSourceMenu(hasPhoto: false, onPick: { store.saveRecipe(recipe, photo: .replace($0)) }, onRemove: {}) {
                                Label("Add Photo", systemImage: "camera")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .glassEffect(.regular.interactive(), in: .capsule)
                            }
                            .padding(12)
                        }
                    }
                VStack(alignment: .leading, spacing: 12) {
                    if let category = recipe.category {
                        Text(category.uppercased()).font(.footnote.weight(.semibold)).foregroundStyle(CalendishStyle.accent)
                            .accessibilityLabel("Category: \(category)")
                    }
                    Text(recipe.title).font(.largeTitle.bold())
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("recipeContent")).maxY } action: { titleBottom = $0 }
                    Text(recipe.summary).foregroundStyle(.secondary)
                    FlowLayout(spacing: 16) {
                        Label("Prep: \(recipe.prepMinutes) min", systemImage: "clock")
                        Label("Cook: \(recipe.cookMinutes) min", systemImage: "flame")
                        Label("\(recipe.servings) servings", systemImage: "person.2")
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
                                Text(ingredient.scaled(by: scale)).strikethrough(checked.contains(ingredient.id)).foregroundStyle(.primary)
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
                            Text(step).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
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
                        Button("Plan Meal", systemImage: "calendar.badge.plus") {
                            let date = store.planningDate
                            let slot = MealSlot.allCases.first { store.meal(on: date, slot: $0) == nil } ?? .dinner
                            planning = MealSelection(date: date, slot: slot, recipeID: recipe.id)
                        }
                        Button("Add to Groceries", systemImage: "basket") { showImportOutline = true }
                        if let link = recipe.recipeLink, let url = RecipeLinkImporter.validatedURL(link) {
                            Button("Visit Source", systemImage: "safari") { sourceToVisit = RecipeSource(url: url) }
                        }
                    }
                    Section {
                        Button(recipe.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: recipe.isFavorite ? "star.slash" : "star") {
                            store.toggleFavorite(recipe)
                        }
                    }
                    Section {
                        Button("Delete Recipe", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    }
                } label: {
                    Label("More recipe actions", systemImage: "ellipsis")
                }
                .sensoryFeedback(.selection, trigger: recipe.isFavorite)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit Recipe", systemImage: "pencil") { showEditor = true }
                    .labelStyle(.iconOnly)
                    .toolbarGlyph()
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button { isCooking = true } label: { OnAccentLabel(title: "Start Cooking", systemImage: "play.fill") }
                    .labelStyle(.iconOnly)
                    .modifier(GlassActionStyle(prominent: true))
                    .disabled(recipe.steps.isEmpty)
                    .accessibilityHint("Opens step-by-step cooking instructions")
            }

        }
        .confirmationDialog("Delete “\(recipe.title)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Recipe", role: .destructive) {
                store.deleteRecipe(recipe)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the recipe and any meals planned with it for your household. Grocery items will stay on your list. This can’t be undone.")
        }
        .sheet(isPresented: $showEditor) { RecipeEditorView(recipe: recipe) }
        .sheet(item: $planning) { MealPickerView(selection: $0) }
        .sheet(item: $sourceToVisit) { source in
            RecipeSourceBrowser(url: source.url)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isCooking) { CookModeView(recipe: recipe, servings: servings, checked: $checked) }
        .sheet(isPresented: $showImportOutline) {
            GroceryImportReviewView(candidates: [GroceryImportCandidate(recipe: recipe, servings: servings)])
        }
    }
}

extension RecipeDetailView {
    private var ingredientsSubtitle: String {
        guard isScaled else { return "Check things off as you cook." }
        let scaledYield = recipe.yieldText.map { " · Makes \(Ingredient.scale($0, by: scale))" } ?? ""
        return "Scaled from \(recipe.servings) servings\(scaledYield)."
    }

    private var servingsStepper: some View {
        HStack(spacing: 12) {
            Label {
                Text("\(servings) servings").monospacedDigit().contentTransition(.numericText(value: Double(servings)))
            } icon: { Image(systemName: "person.2") }
            if isScaled {
                Button("Reset") { scaledServings = nil }
                    .font(.subheadline)
                    .accessibilityLabel("Reset to \(recipe.servings) servings")
                    .transition(.opacity)
            }
            Spacer()
            Stepper("Servings", value: Binding(get: { servings }, set: { scaledServings = $0 }), in: 1...100)
                .labelsHidden()
                .accessibilityValue("\(servings) servings")
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
    /// The recipe being edited, or nil when writing a new one.
    private let original: Recipe?
    private let importedDraftID: UUID?
    @State private var draftID = UUID()
    @State private var title: String
    @State private var summary: String
    @State private var sourceLink: String
    @State private var category: String
    @State private var servings: Int
    @State private var yieldText: String
    @State private var prepMinutes: Int
    @State private var cookMinutes: Int
    @State private var tags: [String]
    @State private var newTag = ""
    @FocusState private var isTagFieldFocused: Bool
    @State private var ingredients: [Ingredient]
    @FocusState private var focusedIngredient: Ingredient.ID?
    @State private var steps: [StepDraft]
    @FocusState private var focusedStep: StepDraft.ID?
    /// A photo picked in this session, saved along with the recipe.
    @State private var newPhoto: UIImage?
    @State private var draftPhoto: Data?
    @State private var saving = false
    @State private var removesPhoto = false
    @State private var discardChanges = false
    @State private var initialDraft: Data?
    @State private var restoredDraft = false
    private var draftKey: String { "recipeDraft.\(store.userID?.uuidString ?? "preview").\(original?.id.uuidString ?? importedDraftID?.uuidString ?? "new")" }
    private var draft: RecipeDraft {
        RecipeDraft(id: draftID, title: title, summary: summary, recipeLink: sourceLink, category: category, servings: servings,
                    yieldText: yieldText, prepMinutes: prepMinutes,
                    cookMinutes: cookMinutes, tags: tags, newTag: newTag, ingredients: ingredients,
                    steps: steps.map(\.text), photo: draftPhoto, removesPhoto: removesPhoto)
    }
    private var draftData: Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(draft)
    }
    private var isDirty: Bool { initialDraft != nil && draftData != initialDraft }
    private func clearDraft() { UserDefaults.standard.removeObject(forKey: draftKey) }
    private func restoreDraft() {
        guard !restoredDraft else { return }
        restoredDraft = true
        initialDraft = draftData
        if let data = UserDefaults.standard.data(forKey: draftKey),
           let saved = try? JSONDecoder().decode(RecipeDraft.self, from: data) {
            draftID = saved.id
            title = saved.title; summary = saved.summary; sourceLink = saved.recipeLink ?? ""; servings = saved.servings
            category = saved.category ?? ""; yieldText = saved.yieldText ?? ""
            prepMinutes = saved.prepMinutes; cookMinutes = saved.cookMinutes
            tags = saved.tags; newTag = saved.newTag; ingredients = saved.ingredients
            steps = saved.steps.map { StepDraft(text: $0) }
            draftPhoto = saved.photo
            newPhoto = saved.photo.flatMap(UIImage.init(data:)); removesPhoto = saved.removesPhoto
        }
    }
    private var keptPhotoPath: String? { removesPhoto ? nil : original?.imagePath }
    private var hasPhoto: Bool { newPhoto != nil || keptPhotoPath != nil }
    private var photoChange: HouseholdStore.PhotoChange {
        if let newPhoto { return .replace(newPhoto) }
        return removesPhoto ? .remove : .keep
    }
    init(recipe: Recipe? = nil, imported: ImportedRecipe? = nil) {
        original = recipe
        importedDraftID = imported?.recipe.id
        let recipe = recipe ?? imported?.recipe
        _newPhoto = State(initialValue: imported?.photo.flatMap(UIImage.init(data:)))
        _draftPhoto = State(initialValue: imported?.photo.flatMap(UIImage.init(data:)).flatMap { RecipePhotos.uploadData(for: $0) })
        _draftID = State(initialValue: recipe?.id ?? UUID())
        _title = State(initialValue: recipe?.title ?? "")
        _summary = State(initialValue: recipe?.summary ?? "")
        _sourceLink = State(initialValue: recipe?.recipeLink ?? "")
        _category = State(initialValue: recipe?.category ?? "")
        _servings = State(initialValue: recipe?.servings ?? 4)
        _yieldText = State(initialValue: recipe?.yieldText ?? "")
        _prepMinutes = State(initialValue: recipe?.prepMinutes ?? 10)
        _cookMinutes = State(initialValue: recipe?.cookMinutes ?? 20)
        _tags = State(initialValue: recipe?.tags ?? [])
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
                Section {
                    PhotoSourceMenu(hasPhoto: hasPhoto, onPick: { newPhoto = $0; draftPhoto = RecipePhotos.uploadData(for: $0) }, onRemove: { newPhoto = nil; draftPhoto = nil; removesPhoto = true }) {
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20).fill(Color(.tertiarySystemFill))
                                if let newPhoto {
                                    Image(uiImage: newPhoto).resizable().scaledToFill()
                                } else if let keptPhotoPath {
                                    RecipePhoto(path: keptPhotoPath)
                                } else {
                                    Image(systemName: "camera").font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
                                }
                            }
                            .frame(height: 180)
                            .clipShape(.rect(cornerRadius: 20))
                            Text(hasPhoto ? "Edit Photo" : "Add Photo")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(CalendishStyle.accent)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hasPhoto ? "Edit Photo" : "Add Photo")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                Section {
                    TextField("Recipe Title (Required)", text: $title)
                    TextField("A little about this recipe", text: $summary, axis: .vertical)
                    TextField("Recipe Link", text: $sourceLink)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Category, like Dinner or Dessert", text: $category)
                    ServingsField(servings: $servings)
                    TextField("Yield, like 24 cookies", text: $yieldText)
                    RecipeDurationField(title: "Prep time", minutes: $prepMinutes)
                    RecipeDurationField(title: "Cook time", minutes: $cookMinutes)
                } header: { Text("The Basics") } footer: {
                    if !canSave { Text("To save, add a title, at least one ingredient, and one instruction.") }
                }
                Section {
                    if !tags.isEmpty {
                        FlowLayout {
                            ForEach(tags, id: \.self) { tag in
                                Button { withAnimation(reduceMotion ? nil : .default) { tags.removeAll { $0 == tag } } } label: {
                                    TagPill(tag: tag, systemImage: "xmark").frame(minHeight: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(tag)")
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    TextField("Add a tag", text: $newTag)
                        .focused($isTagFieldFocused)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit {
                            guard addTag(newTag) else { return }
                            isTagFieldFocused = true
                        }
                    if !tagSuggestions.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(tagSuggestions, id: \.self) { tag in
                                    Button { addTag(tag) } label: { TagPill(tag: tag, systemImage: "plus", muted: true).frame(minHeight: 44) }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Add \(tag)")
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
                    if !tags.isEmpty { Text("Tap a tag to remove it.") }
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

                    Button("Add ingredient", systemImage: "plus.circle.fill") {
                        addIngredient(after: ingredients.last?.id)
                    }
                } header: {
                    Text("Ingredients")
                } footer: {
                    Text("At least one entry is required. Drag the handles to reorder.")
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

                    Button("Add step", systemImage: "plus.circle.fill") {
                        let step = StepDraft()
                        steps.append(step)
                        focusedStep = step.id
                    }
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("At least one entry is required. Drag the handles to reorder.")
                }
            }
            // Always editing, so ingredient and step rows show the delete control and drag handle.
            .environment(\.editMode, .constant(.active))
            .navigationTitle(original == nil ? "New recipe" : "Edit recipe").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if isDirty { discardChanges = true } else { dismiss() } }.toolbarGlyph() }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let savedIngredients = ingredients.compactMap { ingredient -> Ingredient? in
                            var ingredient = ingredient
                            ingredient.text = ingredient.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            return ingredient.text.isEmpty ? nil : ingredient
                        }
                        let savedSteps = steps.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                        var recipe = original ?? Recipe(id: draftID, title: "", summary: "", prepMinutes: 0, cookMinutes: 0, servings: 0, tags: [], symbol: "fork.knife", ingredients: [], steps: [])
                        recipe.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        recipe.summary = summary
                        let link = sourceLink.trimmingCharacters(in: .whitespacesAndNewlines)
                        recipe.recipeLink = link.isEmpty ? nil : link
                        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
                        recipe.category = trimmedCategory.isEmpty ? nil : trimmedCategory
                        let trimmedYield = yieldText.trimmingCharacters(in: .whitespacesAndNewlines)
                        recipe.yieldText = trimmedYield.isEmpty ? nil : trimmedYield
                        recipe.prepMinutes = prepMinutes
                        recipe.cookMinutes = cookMinutes
                        recipe.servings = servings
                        addTag(newTag)
                        recipe.tags = tags
                        recipe.ingredients = savedIngredients
                        recipe.steps = savedSteps
                        saving = true
                        let key = draftKey
                        let savedDraft = draftData
                        UserDefaults.standard.set(savedDraft, forKey: key)
                        store.saveRecipe(recipe, photo: photoChange) {
                            // A later edit must not be cleared by an earlier save completing.
                            if UserDefaults.standard.data(forKey: key) == savedDraft {
                                UserDefaults.standard.removeObject(forKey: key)
                            }
                        }
                        dismiss()
                    } label: { OnAccentLabel(title: "Save") }
                    .disabled(!canSave)
                    .modifier(GlassActionStyle(prominent: true))
                }
            }
        }
        .background { DraftDismissalGuard(isDirty: isDirty && !saving) { discardChanges = true } }
        .onAppear(perform: restoreDraft)
        .onChange(of: draftData) { _, data in
            guard restoredDraft, !saving else { return }
            if isDirty { UserDefaults.standard.set(data, forKey: draftKey) }
            else { clearDraft() }
        }
        .confirmationDialog("Discard Recipe Changes?", isPresented: $discardChanges, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { saving = true; clearDraft(); dismiss() }
            Button("Keep Editing") { }
        } message: { Text("Your draft stays on this device until you save or discard it.") }
    }
    /// Tags from the rest of the recipe book that this recipe doesn't have yet, narrowed by what's typed.
    private var tagSuggestions: [String] {
        let typed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.recipeTags.filter { suggestion in
            !tags.contains { $0.caseInsensitiveCompare(suggestion) == .orderedSame } &&
            (typed.isEmpty || suggestion.localizedCaseInsensitiveContains(typed))
        }
    }
    /// Adds a tag, reusing the spelling of a matching tag elsewhere in the recipe book. Returns false when there was nothing to add.
    @discardableResult
    private func addTag(_ text: String) -> Bool {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        newTag = ""
        guard !typed.isEmpty else { return false }
        let tag = store.recipeTags.first { $0.caseInsensitiveCompare(typed) == .orderedSame } ?? typed
        if !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            withAnimation(reduceMotion ? nil : .default) { tags.append(tag) }
        }
        return true
    }
    private func addIngredient(after id: Ingredient.ID?) {
        let index = ingredients.firstIndex { $0.id == id }.map { $0 + 1 } ?? ingredients.endIndex
        let ingredient = Ingredient(text: "")
        ingredients.insert(ingredient, at: index)
        focusedIngredient = ingredient.id
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

private struct StepDraft: Identifiable {
    let id = UUID()
    var text = ""
}


private struct RecipeDraft: Codable {
    var id: UUID
    var title: String
    var summary: String
    var recipeLink: String?
    var category: String?
    var servings: Int
    var yieldText: String?
    var prepMinutes: Int
    var cookMinutes: Int
    var tags: [String]
    var newTag: String
    var ingredients: [Ingredient]
    var steps: [String]
    var photo: Data?
    var removesPhoto: Bool
}
