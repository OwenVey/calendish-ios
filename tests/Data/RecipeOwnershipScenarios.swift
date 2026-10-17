import Foundation

/// Recipe ownership rules from ADR-0001, run against `InMemoryHouseholdBackend` so store and auto-plan
/// workflow tests don't pass on behavior the database doesn't have. Each scenario mirrors an assertion
/// in `scripts/test-household-moves.mjs`, which runs the same rules against the SQL RPCs.
@MainActor
enum RecipeOwnershipScenarios {
    static func run() async throws {
        try await unsharingLeavesTheHouseholdACopy()
        try await deletingASharedOriginalLeavesTheHouseholdACopy()
        try await deletingAPrivateRecipeLeavesNoCopy()
        try await soloHouseholdsKeepCopiesToo()
        try await onlyOwnersChangeTheirRecipes()
    }

    private struct Fixture {
        let backend = InMemoryHouseholdBackend()
        let owner: HouseholdAccount
        let partner = HouseholdAccount(id: UUID(), email: "partner@example.com")
        let household = Household(id: UUID(), name: "Scenario home", inviteCode: String(UUID().uuidString.prefix(8)))
        let original: Recipe

        init(shared: Bool, solo: Bool = false) {
            owner = backend.identity
            var recipe = Recipe(title: "Stew", summary: "", prepMinutes: 0, cookMinutes: 0, servings: 4, tags: [],
                symbol: "fork.knife", ingredients: [Ingredient(text: "2 onions")], steps: ["Simmer"])
            recipe.owner = .person(owner.id, shared: shared)
            recipe.revision = 3
            original = recipe
            var members = [HouseholdMember(userID: owner.id, displayName: "Owner", role: "owner")]
            if !solo { members.append(HouseholdMember(userID: partner.id, displayName: "Partner", role: "member")) }
            let day = Calendar.current.startOfDay(for: .now)
            backend.seed(HouseholdSnapshot(household: household, members: members, recipes: [recipe],
                meals: [PlannedMeal(date: day, recipe: recipe, recipeID: recipe.id, servings: 4)],
                reviews: [RecipeReview(userID: owner.id, recipeID: recipe.id, rating: 5),
                          RecipeReview(userID: partner.id, recipeID: recipe.id, rating: 4, note: "Use half the salt")],
                cooks: [RecipeCook(recipeID: recipe.id, date: day, cookedBy: partner.id)]))
            backend.emitAuth(owner)
        }

        func snapshot() async throws -> HouseholdSnapshot { try await backend.snapshot(household: household.id) }
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "Recipe ownership: \(message)", code: 1) }
    }

    /// The household's copy follows the original's meals and cooked history, and keeps other members' reviews.
    private static func expectHouseholdCopy(_ snapshot: HouseholdSnapshot, of fixture: Fixture) throws -> Recipe {
        let copies = snapshot.recipes.filter { $0.owner == .household && $0.title == fixture.original.title }
        try expect(copies.count == 1, "the household keeps exactly one copy")
        let copy = copies[0]
        try expect(copy.id != fixture.original.id && copy.ingredients.map(\.text) == ["2 onions"], "the copy is independent")
        try expect(snapshot.meals.allSatisfy { $0.recipeID == copy.id }, "planned meals follow the household copy")
        try expect(snapshot.cooks.allSatisfy { $0.recipeID == copy.id }, "cooked history follows the household copy")
        let reviews = snapshot.reviews.filter { $0.recipeID == copy.id }
        try expect(reviews.map(\.userID) == [fixture.partner.id] || (reviews.isEmpty && !snapshot.members.contains { $0.userID == fixture.partner.id }),
            "the copy keeps other members' reviews, not the owner's")
        return copy
    }

    private static func unsharingLeavesTheHouseholdACopy() async throws {
        let fixture = Fixture(shared: true)
        try await fixture.backend.write(.sharing(fixture.original.id, false))
        var snapshot = try await fixture.snapshot()
        _ = try expectHouseholdCopy(snapshot, of: fixture)
        try expect(snapshot.recipes.first { $0.id == fixture.original.id }?.owner == .person(fixture.owner.id, shared: false),
            "the owner keeps the original, now private")
        try await fixture.backend.write(.sharing(fixture.original.id, false))
        snapshot = try await fixture.snapshot()
        _ = try expectHouseholdCopy(snapshot, of: fixture)
    }

    private static func deletingASharedOriginalLeavesTheHouseholdACopy() async throws {
        let fixture = Fixture(shared: true)
        try await fixture.backend.write(.deleteRecipe(fixture.original.id))
        let snapshot = try await fixture.snapshot()
        try expect(!snapshot.recipes.contains { $0.id == fixture.original.id }, "the original is deleted")
        _ = try expectHouseholdCopy(snapshot, of: fixture)
    }

    private static func deletingAPrivateRecipeLeavesNoCopy() async throws {
        let fixture = Fixture(shared: false)
        try await fixture.backend.write(.deleteRecipe(fixture.original.id))
        let snapshot = try await fixture.snapshot()
        try expect(snapshot.recipes.isEmpty && snapshot.reviews.isEmpty && snapshot.cooks.isEmpty, "nothing is retained")
        try expect(snapshot.meals.count == 1 && snapshot.meals[0].recipeID == nil, "planned meals keep their saved version")
    }

    private static func soloHouseholdsKeepCopiesToo() async throws {
        let unshared = Fixture(shared: true, solo: true)
        try await unshared.backend.write(.sharing(unshared.original.id, false))
        _ = try await expectHouseholdCopy(unshared.snapshot(), of: unshared)
        let deleted = Fixture(shared: true, solo: true)
        try await deleted.backend.write(.deleteRecipe(deleted.original.id))
        _ = try await expectHouseholdCopy(deleted.snapshot(), of: deleted)
    }

    private static func onlyOwnersChangeTheirRecipes() async throws {
        let fixture = Fixture(shared: true)
        fixture.backend.emitAuth(fixture.partner)
        for mutation in [HouseholdMutation.sharing(fixture.original.id, false), .deleteRecipe(fixture.original.id)] {
            do {
                try await fixture.backend.write(mutation)
                try expect(false, "a member can't unshare or delete someone else's recipe")
            } catch let error as CocoaError where error.code == .fileWriteNoPermission { }
        }
        try await expect(try fixture.snapshot().recipes.map(\.id) == [fixture.original.id], "rejected changes leave the recipe as it was")
    }
}
