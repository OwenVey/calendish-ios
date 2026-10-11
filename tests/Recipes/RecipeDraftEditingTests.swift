import SwiftUI

@main
struct RecipeDraftTestApp: App {
    @State private var result = "Running draft tests…"
    var body: some Scene {
        WindowGroup {
            Text(result).padding().task {
                do { try await run(); result = "PASS" }
                catch { result = "FAIL: \(error)" }
                try? Data(result.utf8).write(to: URL.documentsDirectory.appending(path: "result.txt"))
            }
        }
    }

    private func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: message, code: 1) }
    }

    private func run() async throws {
        let suite = "recipe-draft-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let account = UUID()
        func draft(_ recipe: Recipe? = nil, imported: ImportedRecipe? = nil) -> RecipeDraftEditing {
            let editing = RecipeDraftEditing(recipe: recipe, imported: imported, defaultServings: 3, defaults: defaults)
            editing.open(accountID: account)
            return editing
        }

        let fresh = draft()
        try expect(!fresh.isDirty && !fresh.canSave && fresh.fields.servings == 3, "New recipe defaults and validation")
        fresh.fields.title = "  Noodles  "
        fresh.fields.ingredients = [Ingredient(text: "  2 cups flour  "), Ingredient(text: "  ")]
        fresh.fields.steps = [.init(text: "  Mix.  "), .init(text: " ")]
        fresh.fields.newTag = " dinner "
        fresh.fields.isShared = false
        fresh.fields.sourceLink = " https://example.com/recipe "
        fresh.fields.yieldText = " 2 bowls "
        let id = fresh.fields.id
        let recovered = draft()
        try expect(recovered.fields.id == id && recovered.fields.title == "  Noodles  " && recovered.isDirty,
                   "Autosave restores content and new recipe identity")
        var firstAcknowledgment: (() -> Void)?
        try expect(recovered.save(knownTags: ["Dinner"]) { _, _, acknowledge in
            firstAcknowledgment = acknowledge
        }, "Valid recipe submitted")
        // Explicitly inspect the submitted result, rather than letting an assertion disappear inside a callback.
        let retry = draft()
        try expect(retry.isDirty && retry.fields.tags == ["Dinner"] && retry.fields.newTag.isEmpty,
                   "Unacknowledged save remains recoverable")
        var submitted: Recipe?
        var secondAcknowledgment: (() -> Void)?
        retry.save(knownTags: []) { recipe, _, acknowledge in submitted = recipe; secondAcknowledgment = acknowledge }
        try expect(submitted?.title == "Noodles" && submitted?.ingredients.map(\.text) == ["2 cups flour"] && submitted?.steps == ["Mix."],
                   "Save normalizes recipe content")
        try expect(submitted?.recipeLink == "https://example.com/recipe" && submitted?.yieldText == "2 bowls" && submitted?.owner == .person(account, shared: false),
                   "Save retains source, yield and sharing choice")
        firstAcknowledgment?()
        try expect(draft().isDirty, "Older identical save cannot clear a newer unacknowledged submission")
        secondAcknowledgment?()
        try expect(!draft().isDirty && draft().fields.title.isEmpty, "Acknowledged submission clears its draft")

        let editing = draft()
        editing.fields.title = "First edit"
        editing.fields.steps = [.init(text: "Cook.")]
        var older: (() -> Void)?
        editing.save(knownTags: []) { _, _, acknowledge in older = acknowledge }
        let newer = draft()
        newer.fields.title = "Later edit"
        older?()
        try expect(draft().fields.title == "Later edit", "Earlier acknowledgment preserves later editing")
        newer.discard()
        newer.fields.title = "Accidental later update"
        try expect(!draft().isDirty, "Discard clears draft and stops autosave")

        var original = SampleRecipes.all[0]
        original.owner = .household
        original.imagePath = "household/photo.jpg"
        let existing = draft(original)
        try expect(!existing.isDirty && !existing.isNew && existing.hasPhoto, "Existing recipe baseline and retained photo")
        existing.fields.title = "Changed"
        existing.fields.title = original.title
        try expect(!draft(original).isDirty, "Returning to baseline removes autosave")
        existing.setPhoto(nil)
        let restoredRemoval = draft(original)
        try expect(restoredRemoval.isDirty && !restoredRemoval.hasPhoto, "Photo removal survives restoration")
        var removal: HouseholdStore.PhotoChange?
        restoredRemoval.save(knownTags: []) { recipe, photo, _ in
            submitted = recipe
            removal = photo
        }
        if case .remove? = removal { } else { throw NSError(domain: "Restored removal must submit remove intent", code: 1) }
        try expect(submitted?.owner == .household && submitted?.id == original.id, "Editing preserves ownership and identity")
        restoredRemoval.discard()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let withPhoto = draft(original)
        withPhoto.setPhoto(image)
        let photoRestored = draft(original)
        try expect(photoRestored.photo != nil && photoRestored.hasPhoto && !photoRestored.fields.removesPhoto, "Picked photo survives restoration")
        var replacement = false
        photoRestored.save(knownTags: []) { _, photo, _ in if case .replace = photo { replacement = true } }
        try expect(replacement, "Recovered photo submits replacement intent")

        let imported = ImportedRecipe(recipe: SampleRecipes.all[1], photo: nil)
        let importedDraft = draft(imported: imported)
        importedDraft.fields.title = "Recovered import"
        try expect(draft(imported: imported).fields.title == "Recovered import" && draft().fields.title.isEmpty,
                   "Imported and manual drafts have separate identities")
        importedDraft.open(accountID: UUID())
        try expect(importedDraft.fields.title == imported.recipe.title && !importedDraft.isDirty,
                   "Changing account cannot carry private draft content into the new account")

        // Old stored drafts have no revision and can omit the formerly optional sharing and source fields.
        let legacyKey = "recipeDraft.\(account.uuidString).\(original.id.uuidString)"
        let legacy: [String: Any] = ["id": original.id.uuidString, "title": "Legacy draft", "summary": "", "servings": 4,
            "prepMinutes": 10, "cookMinutes": 20, "tags": [], "newTag": "", "ingredients": [], "steps": ["Cook."], "removesPhoto": false]
        try defaults.set(JSONSerialization.data(withJSONObject: legacy), forKey: legacyKey)
        let migrated = draft(original)
        try expect(migrated.fields.title == "Legacy draft" && migrated.fields.isShared && migrated.canSave, "Existing stored draft format remains readable")

        // The same persistence callback used by the editor must retain work on a real store write failure.
        let backend = InMemoryHouseholdBackend()
        backend.account = backend.identity
        let home = Household(id: UUID(), name: "Draft test household", inviteCode: "DRAFT123")
        backend.seed(HouseholdSnapshot(household: home,
            members: [HouseholdMember(userID: backend.identity.id, displayName: "Fixture", role: "owner")], recipes: [original]))
        let store = HouseholdStore(backend: backend, finishedCooks: FinishedCooks(defaults: defaults))
        let session = Task { await store.start() }
        defer { session.cancel() }
        let deadline = ContinuousClock.now + .seconds(5)
        while store.phase != .ready {
            guard ContinuousClock.now < deadline else { throw NSError(domain: "Household did not load", code: 1) }
            await Task.yield()
        }
        let storeDraft = RecipeDraftEditing(recipe: original, defaultServings: 3, defaults: defaults)
        storeDraft.open(accountID: backend.identity.id)
        storeDraft.fields.title = "Failed save retained"
        backend.beforeWrite = { _ in throw URLError(.notConnectedToInternet) }
        storeDraft.save(knownTags: []) { recipe, photo, onSaved in store.saveRecipe(recipe, photo: photo, onSaved: onSaved) }
        await store.waitForSaves()
        let reopened = RecipeDraftEditing(recipe: original, defaultServings: 3, defaults: defaults)
        reopened.open(accountID: backend.identity.id)
        try expect(reopened.fields.title == "Failed save retained" && store.errorMessage != nil, "Failed household write keeps recipe draft recoverable")
        backend.beforeWrite = nil
        reopened.save(knownTags: []) { recipe, photo, onSaved in store.saveRecipe(recipe, photo: photo, onSaved: onSaved) }
        await store.waitForSaves()
        let afterSave = RecipeDraftEditing(recipe: store.recipes[0], defaultServings: 3, defaults: defaults)
        afterSave.open(accountID: backend.identity.id)
        try expect(!afterSave.isDirty && store.recipes[0].title == "Failed save retained", "Successful store acknowledgment clears submitted draft")
    }
}
