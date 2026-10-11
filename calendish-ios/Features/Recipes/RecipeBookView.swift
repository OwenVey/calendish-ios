import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

struct RecipeBookView: View {
    @Environment(HouseholdStore.self) private var store
    @State private var search = ""
    @State private var selectedCategory: RecipeCategory?
    @State private var selectedTag: String?
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
    @State private var planning: MealSelection?
    @State private var groceryRecipe: Recipe?
    private enum RecipeSheet: Identifiable {
        case manual
        case importing(RecipeImportView.Start)
        var id: String { if case .manual = self { "manual" } else { "import" } }
    }
    /// Filters and sorts once per update; both the stats and the search are costly over a large book.
    private func filteredRecipes(stats: [UUID: RecipeStats]) -> [Recipe] {
        let recipes = store.recipes.filter { recipe in
            scope.includes(recipe, person: store.userID) &&
            (selectedCategory == nil || recipe.category == selectedCategory) &&
            (selectedTag.map { tag in recipe.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } } ?? true) &&
            (!favoritesOnly || recipe.isFavorite) &&
            recipe.matches(search)
        }
        return sort.sorted(recipes, stats: stats)
    }
    private func subtitle(count: Int) -> String {
        let count = count == 1 ? "1 recipe" : "\(count) recipes"
        let filters = (favoritesOnly ? ["Favorites"] : []) + [selectedCategory?.title, selectedTag].compactMap(\.self)
        return (filters + [count]).joined(separator: " · ")
    }
    private var isFiltered: Bool { favoritesOnly || selectedCategory != nil || selectedTag != nil }

    private func perform(_ action: RecipeBookAction) {
        switch action {
        case .plan(let recipe): planning = MealSelection(recipeID: recipe.id)
        case .addToGroceries(let recipe): groceryRecipe = recipe
        case .delete(let recipe): recipeToDelete = recipe
        }
    }

    var body: some View {
        let stats = store.recipeStats
        let recipes = filteredRecipes(stats: stats)
        ZStack {
            switch layout {
            case .list:
                RecipeBookList(recipes: recipes, stats: stats, showsLastCooked: sort.showsLastCooked, scope: $scope, perform: perform)
            case .grid:
                RecipeBookGrid(recipes: recipes, stats: stats, showsLastCooked: sort.showsLastCooked, scope: $scope, perform: perform)
            }
        }
        .overlay {
            if recipes.isEmpty {
                if scope == .mine, search.isEmpty, !isFiltered, !store.recipes.contains(where: store.isMine) {
                    ContentUnavailableView {
                        Label("Your collection starts here", systemImage: "book.closed")
                    } description: {
                        Text("Write or import a recipe, or open a household recipe and choose Save to my collection.")
                    } actions: {
                        Button("Write a recipe", systemImage: "square.and.pencil") { sheet = .manual }
                        Button("Import from link", systemImage: "link") { sheet = .importing(.link) }
                    }
                } else if store.recipes.isEmpty {
                    ContentUnavailableView("Your recipe book starts here", systemImage: "book.closed", description: Text("Add a recipe or import one from a link, text, photo, or PDF."))
                } else if favoritesOnly, search.isEmpty, !store.recipes.contains(where: \.isFavorite) {
                    ContentUnavailableView("No favorites yet", systemImage: "star", description: Text("Open a recipe’s actions menu and choose Add to favorites."))
                } else {
                    ContentUnavailableView("No matching recipes", systemImage: "book.closed", description: Text("Try another search or change the filters."))
                }
            }
        }
        .navigationTitle("Recipes")
        .tabRootStyle()
        .navigationSubtitle(subtitle(count: recipes.count))
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search recipes and ingredients")
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
                        Picker("Category", selection: $selectedCategory) {
                            Text("All categories").tag(nil as RecipeCategory?)
                            ForEach(RecipeCategory.allCases) { category in
                                Label(category.title, systemImage: category.systemImage).tag(Optional(category))
                            }
                        }
                        .pickerStyle(.menu)
                        Picker("Tag", selection: $selectedTag) {
                            Text("All tags").tag(nil as String?)
                            ForEach(store.recipeTags, id: \.self) { Text($0).tag(Optional($0)) }
                        }
                        .pickerStyle(.menu)
                        if isFiltered {
                            Button("Clear filters") {
                                selectedCategory = nil
                                selectedTag = nil
                                favoritesOnly = false
                            }
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
        .calendishAlert("Delete “\(recipeToDelete?.title ?? "recipe")”?", item: $recipeToDelete) { recipe in
            Button("Delete recipe", role: .destructive) { store.deleteRecipe(recipe) }
            Button("Cancel", role: .cancel) { }
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
            switch result {
            case .success(let urls): sheet = .importing(.files(urls))
            case .failure:
                fileError = "Couldn’t open the file. Choose the file again, or try another file."
            }
        }
        .calendishAlert("Couldn’t open file", item: $fileError) { _ in
            Button("OK", role: .cancel) { }
        } message: { Text($0) }
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
