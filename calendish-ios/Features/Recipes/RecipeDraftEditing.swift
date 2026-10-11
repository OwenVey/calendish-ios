import Observation
import SwiftUI

/// Editing a recipe, including recovery of unsaved work and acknowledgment of a submitted save.
@Observable
final class RecipeDraftEditing {
    struct Step: Identifiable {
        let id = UUID()
        var text = ""
    }

    struct Fields {
        var id: UUID
        var title: String
        var summary: String
        var sourceLink: String
        var category: RecipeCategory?
        var servings: Int
        var yieldText: String
        var prepMinutes: Int
        var cookMinutes: Int
        var tags: [String]
        var newTag = ""
        var ingredients: [Ingredient]
        var steps: [Step]
        var photo: Data?
        var removesPhoto = false
        var isShared = true
    }

    var fields: Fields {
        didSet {
            if fields.photo != oldValue.photo { photo = fields.photo.flatMap(UIImage.init(data:)) }
            autosave()
        }
    }
    private(set) var photo: UIImage?
    private(set) var isClosing = false
    private let original: Recipe?
    private let seed: Fields
    private let identity: String
    private let defaults: UserDefaults
    private var accountID: UUID?
    private var storageKey: String?
    private var baseline: Data?

    init(recipe: Recipe? = nil, imported: ImportedRecipe? = nil, defaultServings: Int, sharesNewRecipes: Bool = true,
         defaults: UserDefaults = .standard) {
        original = recipe
        identity = recipe?.id.uuidString ?? imported?.recipe.id.uuidString ?? "new"
        self.defaults = defaults
        let source = recipe ?? imported?.recipe
        let fields = Fields(id: source?.id ?? UUID(), title: source?.title ?? "", summary: source?.summary ?? "",
            sourceLink: source?.recipeLink ?? "", category: source?.category, servings: source?.servings ?? defaultServings,
            yieldText: source?.yieldText ?? "", prepMinutes: source?.prepMinutes ?? 10, cookMinutes: source?.cookMinutes ?? 20,
            tags: source?.tags ?? [], ingredients: source.flatMap { $0.ingredients.isEmpty ? nil : $0.ingredients } ?? [Ingredient(text: "")],
            steps: source.flatMap { $0.steps.isEmpty ? nil : $0.steps.map { Step(text: $0) } } ?? [Step()],
            photo: imported?.photo.flatMap(UIImage.init(data:)).flatMap { RecipePhotos.uploadData(for: $0) },
            isShared: sharesNewRecipes)
        seed = fields
        self.fields = fields
        photo = fields.photo.flatMap(UIImage.init(data:))
    }

    var isNew: Bool { original == nil }
    var isDirty: Bool { baseline != nil && encoded() != baseline }
    var canSave: Bool {
        !fields.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (fields.ingredients.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ||
         fields.steps.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }
    var keptPhotoPath: String? { fields.removesPhoto ? nil : original?.imagePath }
    var hasPhoto: Bool { photo != nil || keptPhotoPath != nil }

    /// Opening again is harmless; changing accounts resets content before restoring that account's draft.
    func open(accountID: UUID?) {
        let key = "recipeDraft.\(accountID?.uuidString ?? "preview").\(identity)"
        guard storageKey != key else { return }
        storageKey = nil
        self.accountID = accountID
        isClosing = false
        fields = seed
        baseline = encoded()
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(StoredDraft.self, from: data) {
            fields = Fields(id: saved.id, title: saved.title, summary: saved.summary, sourceLink: saved.recipeLink ?? "",
                category: saved.category.flatMap(RecipeCategory.init(matching:)), servings: saved.servings,
                yieldText: saved.yieldText ?? "", prepMinutes: saved.prepMinutes, cookMinutes: saved.cookMinutes,
                tags: saved.tags, newTag: saved.newTag, ingredients: saved.ingredients,
                steps: saved.steps.map { Step(text: $0) }, photo: saved.photo,
                removesPhoto: saved.removesPhoto, isShared: saved.isShared ?? seed.isShared)
        }
        storageKey = key
    }

    func setPhoto(_ image: UIImage?) {
        var updated = fields
        updated.photo = image.flatMap { RecipePhotos.uploadData(for: $0) }
        updated.removesPhoto = image == nil
        fields = updated
    }

    func tagSuggestions(in knownTags: [String]) -> [String] {
        let typed = fields.newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        return knownTags.filter { suggestion in
            !fields.tags.contains { $0.caseInsensitiveCompare(suggestion) == .orderedSame } &&
            (typed.isEmpty || suggestion.localizedStandardContains(typed))
        }
    }

    @discardableResult
    func addTag(_ text: String, knownTags: [String]) -> Bool {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        fields.newTag = ""
        guard !typed.isEmpty else { return false }
        let tag = knownTags.first { $0.caseInsensitiveCompare(typed) == .orderedSame } ?? typed
        if !fields.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { fields.tags.append(tag) }
        return true
    }

    func addIngredient(after id: Ingredient.ID?) -> Ingredient.ID {
        let index = fields.ingredients.firstIndex { $0.id == id }.map { $0 + 1 } ?? fields.ingredients.endIndex
        let ingredient = Ingredient(text: "")
        fields.ingredients.insert(ingredient, at: index)
        return ingredient.id
    }

    func discard() {
        isClosing = true
        if let storageKey { defaults.removeObject(forKey: storageKey) }
    }

    /// Stores the submitted draft before calling persistence. Only that submission's acknowledgment can clear it.
    /// A failure leaves it available to the next editor; a later edit or save has its own stored revision.
    @discardableResult
    func save(knownTags: [String], using persist: (Recipe, HouseholdStore.PhotoChange, @escaping () -> Void) -> Void) -> Bool {
        guard canSave, let key = storageKey, !isClosing else { return false }
        addTag(fields.newTag, knownTags: knownTags)
        var recipe = original ?? Recipe(id: fields.id, title: "", summary: "", prepMinutes: 0, cookMinutes: 0,
                                      servings: 0, tags: [], symbol: "fork.knife", ingredients: [], steps: [])
        if original == nil, let accountID { recipe.owner = .person(accountID, shared: fields.isShared) }
        recipe.title = fields.title.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.summary = fields.summary
        let link = fields.sourceLink.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.recipeLink = link.isEmpty ? nil : link
        recipe.category = fields.category
        let yield = fields.yieldText.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.yieldText = yield.isEmpty ? nil : yield
        recipe.prepMinutes = fields.prepMinutes
        recipe.cookMinutes = fields.cookMinutes
        recipe.servings = fields.servings
        recipe.tags = fields.tags
        recipe.ingredients = fields.ingredients.compactMap {
            var ingredient = $0
            ingredient.text = ingredient.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return ingredient.text.isEmpty ? nil : ingredient
        }
        recipe.steps = fields.steps.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let change: HouseholdStore.PhotoChange = photo.map { .replace($0) } ?? (fields.removesPhoto ? .remove : .keep)
        guard let submitted = encoded(revision: UUID()) else { return false }
        defaults.set(submitted, forKey: key)
        isClosing = true
        let defaults = defaults
        persist(recipe, change) {
            if defaults.data(forKey: key) == submitted { defaults.removeObject(forKey: key) }
        }
        return true
    }

    private func autosave() {
        guard let storageKey, !isClosing else { return }
        if isDirty { defaults.set(encoded(revision: UUID()), forKey: storageKey) }
        else { defaults.removeObject(forKey: storageKey) }
    }

    private func encoded(revision: UUID? = nil) -> Data? {
        let stored = StoredDraft(id: fields.id, title: fields.title, summary: fields.summary, recipeLink: fields.sourceLink,
            category: fields.category?.rawValue, servings: fields.servings, yieldText: fields.yieldText,
            prepMinutes: fields.prepMinutes, cookMinutes: fields.cookMinutes, tags: fields.tags, newTag: fields.newTag,
            ingredients: fields.ingredients, steps: fields.steps.map(\.text), photo: fields.photo,
            removesPhoto: fields.removesPhoto, isShared: fields.isShared, revision: revision)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(stored)
    }

    /// Matches the original editor's stored format; revision is optional for existing drafts.
    private struct StoredDraft: Codable {
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
        var isShared: Bool?
        var revision: UUID?
    }
}
