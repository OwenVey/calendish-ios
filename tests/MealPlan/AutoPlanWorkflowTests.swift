import SwiftUI

/// Reproducible choices, so a test can assert eligibility and preferences without fixing one exact week.
private struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Suspends an adapter operation until the test releases it.
@MainActor
private final class Gate {
    var entered = false
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { entered = true; continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}

/// Auto planning through HouseholdStore and the in-memory adapter: calendar choices, proposals, adjustments, and saves.
@MainActor
enum AutoPlanWorkflowTests {
    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: message, code: 1) }
    }

    private static func until(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            if ContinuousClock.now >= deadline { throw NSError(domain: "Timed out waiting for auto-plan state", code: 1) }
            await Task.yield()
        }
    }

    /// A signed-in store whose household holds the given recipes and plan.
    private struct Fixture {
        let backend: InMemoryHouseholdBackend
        let store: HouseholdStore
        let session: Task<Void, Never>
        let household: Household
    }

    private static func ready(recipes: [Recipe], meals: [PlannedMeal] = [], notes: [MealPlanNote] = [],
                              reviews: [RecipeReview] = [], cooks: [RecipeCook] = [], groceries: [GroceryItem] = [],
                              partner: UUID = UUID()) async throws -> Fixture {
        let backend = InMemoryHouseholdBackend()
        let me = backend.identity.id
        let household = Household(id: UUID(), name: "Auto plan home", inviteCode: String(UUID().uuidString.prefix(8)))
        backend.seed(HouseholdSnapshot(household: household,
            members: [HouseholdMember(userID: me, displayName: "Fixture", role: "owner"),
                      HouseholdMember(userID: partner, displayName: "Partner", role: "member")],
            recipes: recipes, meals: meals, notes: notes, reviews: reviews, cooks: cooks), groceries: groceries)
        let store = HouseholdStore(backend: backend, finishedCooks: FinishedCooks(defaults: UserDefaults(suiteName: "auto-plan-\(UUID().uuidString)")!))
        let session = Task { await store.start() }
        try await until { store.phase == .signedOut }
        try await store.signIn(email: "fixture@example.com", password: "fixture-password")
        try await until { store.phase == .ready }
        return Fixture(backend: backend, store: store, session: session, household: household)
    }

    private static let newYork = TimeZone(identifier: "America/New_York")!
    /// Wednesday, March 4, 2026 at noon in New York. Daylight saving time starts the following Sunday, March 8.
    private static var wednesday: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        return calendar.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 12))!
    }

    private static func day(_ number: Int, month: Int = 3) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: number))!
    }

    private static func recipe(_ title: String, category: RecipeCategory? = .dinner, servings: Int = 4, favorite: Bool = false) -> Recipe {
        var recipe = SampleRecipes.all[0]
        recipe.id = UUID()
        recipe.title = title
        recipe.category = category
        recipe.servings = servings
        recipe.isFavorite = favorite
        recipe.owner = .household
        return recipe
    }

    static func run() async throws {
        let previousZone = NSTimeZone.default
        let previousWeekStart = UserDefaults.standard.object(forKey: WeekStart.storageKey)
        NSTimeZone.default = newYork
        defer {
            NSTimeZone.default = previousZone
            UserDefaults.standard.set(previousWeekStart, forKey: WeekStart.storageKey)
        }
        try await calendarChoices()
        try await proposals()
        try await preferences()
        try await adjustments()
        try await saving()
        try await saveConflicts()
        try await saveRecovery()
        try await householdChanges()
    }

    private static func calendarChoices() async throws {
        UserDefaults.standard.set(WeekStart.sunday.rawValue, forKey: WeekStart.storageKey)
        let pasta = recipe("Pasta")
        let fixture = try await ready(recipes: [pasta],
            meals: [PlannedMeal(date: day(10), recipe: pasta, recipeID: pasta.id, servings: 2)],
            notes: [MealPlanNote(date: day(12), text: "Leftovers")])
        defer { fixture.session.cancel() }
        let plan = fixture.store.beginAutoPlan(now: wednesday, random: SeededRandom(state: 1))!
        try expect(fixture.store.autoPlan === plan, "The store holds the proposal for this session")
        try expect(plan.days.map(\.date) == (8...14).map { day($0) }, "Next week is chosen initially, following the Sunday week start across the time change")
        try expect(plan.days.filter(\.isSelected).map(\.date) == [8, 9, 11, 13, 14].map { day($0) }, "Empty days are selected initially")
        try expect(plan.days.first { $0.date == day(10) }?.availability == .planned
            && plan.days.first { $0.date == day(12) }?.availability == .planned, "Days with a recipe or a note are unavailable")
        plan.toggleDay(day(10))
        try expect(plan.days.first { $0.date == day(10) }?.isSelected == false, "Unavailable days cannot be selected")
        plan.toggleDay(day(9))
        try expect(plan.days.first { $0.date == day(9) }?.isSelected == false, "Days can be deselected")

        plan.showWeek(offset: -1)
        try expect(plan.days.map(\.date) == (1...7).map { day($0) }, "The current week is available")
        try expect(plan.days.filter { $0.availability == .past }.map(\.date) == [1, 2, 3].map { day($0) }, "Days before today are past")
        try expect(plan.days.filter(\.isSelected).map(\.date) == (4...7).map { day($0) }, "Today and later days in the current week are selected")
        try expect(!plan.canShowPreviousWeek, "Past weeks are unavailable")
        plan.showWeek(offset: -1)
        try expect(plan.days.first?.date == day(1), "Showing a past week does nothing")

        UserDefaults.standard.set(WeekStart.monday.rawValue, forKey: WeekStart.storageKey)
        let monday = fixture.store.beginAutoPlan(now: wednesday, random: SeededRandom(state: 1))!
        try expect(monday.days.map(\.date) == (9...15).map { day($0) }, "Weeks follow the Monday week start")
        UserDefaults.standard.set(WeekStart.saturday.rawValue, forKey: WeekStart.storageKey)
        let saturday = fixture.store.beginAutoPlan(now: wednesday, random: SeededRandom(state: 1))!
        try expect(saturday.days.map(\.date) == (7...13).map { day($0) }, "Weeks follow the Saturday week start")
        UserDefaults.standard.set(WeekStart.sunday.rawValue, forKey: WeekStart.storageKey)
        // A late-evening clock still belongs to the same calendar day.
        let lateEvening = Calendar.current.date(byAdding: .hour, value: 11, to: wednesday)!
        let evening = fixture.store.beginAutoPlan(now: lateEvening, random: SeededRandom(state: 1))!
        evening.showWeek(offset: -1)
        try expect(evening.days.first { $0.date == day(4) }?.availability == .open, "Today stays eligible late in the evening")
    }

    private static func proposals() async throws {
        UserDefaults.standard.set(WeekStart.sunday.rawValue, forKey: WeekStart.storageKey)
        let previousServings = UserDefaults.standard.object(forKey: PreferenceKey.defaultServings)
        UserDefaults.standard.set(3, forKey: PreferenceKey.defaultServings)
        defer { UserDefaults.standard.set(previousServings, forKey: PreferenceKey.defaultServings) }
        let dinner = recipe("Dinner", servings: 6)
        let uncategorized = recipe("Uncategorized", category: nil, servings: 0)
        let farEnough = recipe("Planned eight days before")
        let nearBefore = recipe("Planned seven days before")
        let nearAfter = recipe("Planned seven days after")
        let others = [recipe("Breakfast", category: .breakfast), recipe("Lunch", category: .lunch),
                      recipe("Dessert", category: .dessert), recipe("Snack", category: .snack)]
        let fixture = try await ready(recipes: [dinner, uncategorized, farEnough, nearBefore, nearAfter] + others, meals: [
            PlannedMeal(date: day(28, month: 2), recipe: farEnough, recipeID: farEnough.id, servings: 2),
            PlannedMeal(date: day(1), recipe: nearBefore, recipeID: nearBefore.id, servings: 2),
            PlannedMeal(date: day(21), recipe: nearAfter, recipeID: nearAfter.id, servings: 2),
        ])
        defer { fixture.session.cancel() }
        let plan = fixture.store.beginAutoPlan(now: wednesday, random: SeededRandom(state: 2))!
        plan.propose()
        let chosen = plan.dinners.compactMap(\.recipe?.id)
        try expect(plan.dinners.map(\.date) == (8...14).map { day($0) }, "Each selected day gets one dinner entry")
        try expect(Set(chosen) == [dinner.id, uncategorized.id, farEnough.id] && chosen.count == 3,
            "Only distinct Dinner and uncategorized recipes outside the inclusive nearby window are proposed")
        try expect(plan.dinners.filter { $0.recipe == nil }.count == 4 && plan.notice == "Only 3 recipes can be suggested, so 4 days stay open. Choose recipes for them yourself.",
            "A shortage leaves the remaining days open and explains why")
        try expect(plan.dinners.first { $0.recipe?.id == dinner.id }?.servings == 6, "Dinners start with the recipe's servings")
        try expect(plan.dinners.first { $0.recipe?.id == uncategorized.id }?.servings == 3, "Recipes without a usable serving count use the Settings default")
        try expect(fixture.store.meals.count == 3, "Proposing writes nothing to the plan")

        let breakfastOnly = try await ready(recipes: others)
        defer { breakfastOnly.session.cancel() }
        let empty = breakfastOnly.store.beginAutoPlan(now: wednesday, random: SeededRandom(state: 2))!
        empty.propose()
        try expect(empty.dinners.count == 7 && empty.dinners.allSatisfy { $0.recipe == nil }, "An empty pool leaves every day open")
        try expect(empty.notice == "None of your saved recipes can be suggested. Only Dinner recipes and recipes without a category are suggested; choose recipes for these days yourself.",
            "An empty pool is explained")
    }

    private static func preferences() async throws {
        let partner = UUID()
        let loved = recipe("Loved", favorite: true)
        let rated = recipe("Rated")
        let recent = recipe("Cooked yesterday")
        let plain = (1...7).map { recipe("Plain \($0)") }
        let all = [loved, rated, recent] + plain
        let fixture = try await ready(recipes: all,
            reviews: [RecipeReview(userID: partner, recipeID: rated.id, rating: 5), RecipeReview(userID: UUID(), recipeID: recent.id, rating: 5)],
            cooks: [RecipeCook(recipeID: recent.id, date: day(3), cookedBy: nil),
                    RecipeCook(recipeID: loved.id, date: day(1, month: 1), cookedBy: nil)],
            partner: partner)
        defer { fixture.session.cancel() }
        var counts: [UUID: Int] = [:]
        for seed in 0..<300 {
            let plan = fixture.store.beginAutoPlan(now: wednesday, random: SeededRandom(state: UInt64(seed)))!
            for date in plan.days.dropFirst().map(\.date) { plan.toggleDay(date) }
            plan.propose()
            if let id = plan.dinners.first?.recipe?.id { counts[id, default: 0] += 1 }
        }
        let plainAverage = Double(plain.map { counts[$0.id, default: 0] }.reduce(0, +)) / Double(plain.count)
        try expect(Double(counts[loved.id, default: 0]) > plainAverage * 2, "Favorites cooked long ago are favored")
        try expect(Double(counts[rated.id, default: 0]) > plainAverage * 1.5, "Strong household ratings are favored")
        try expect(Double(counts[recent.id, default: 0]) < plainAverage, "Recently cooked recipes are less likely, and a former member's rating doesn't count")
        try expect(counts[recent.id, default: 0] > 0, "Recently cooked recipes remain possible")
        try expect(plain.allSatisfy { counts[$0.id, default: 0] > 0 }, "Recipes without favorites or ratings are still considered")

        let plan = fixture.store.beginAutoPlan(now: wednesday, random: SeededRandom(state: 7))!
        plan.propose()
        let first = plan.dinners.compactMap(\.recipe?.id)
        try expect(Set(first).count == 7, "A full week uses seven different recipes")
        var varied = false
        for _ in 0..<5 where !varied {
            plan.propose()
            varied = plan.dinners.compactMap(\.recipe?.id) != first
        }
        try expect(varied, "Generating again offers a different week when alternatives exist")
    }

    private static func adjustments() async throws {
        UserDefaults.standard.set(WeekStart.sunday.rawValue, forKey: WeekStart.storageKey)
        let pool = (1...10).map { recipe("Dinner \($0)", servings: $0) }
        let breakfast = recipe("Pancakes", category: .breakfast, servings: 2)
        let fixture = try await ready(recipes: pool + [breakfast])
        defer { fixture.session.cancel() }
        let plan = fixture.store.beginAutoPlan(now: wednesday, random: SeededRandom(state: 3))!
        plan.propose()
        try expect(!plan.needsDiscardConfirmation, "An unadjusted proposal can close without confirmation")
        let ids = plan.dinners.map(\.id)
        func dinner(_ index: Int) -> AutoPlan.Dinner { plan.dinners.first { $0.id == ids[index] }! }

        let before = dinner(0).recipe!
        try expect(plan.suggestAnother(for: ids[0]), "Another suggestion is available")
        let swapped = dinner(0).recipe!
        let others = Set(plan.dinners.filter { $0.id != ids[0] }.compactMap(\.recipe?.id))
        try expect(swapped.id != before.id && !others.contains(swapped.id), "A swap picks a recipe not already in the proposal")
        try expect(dinner(0).servings == swapped.servings && !dinner(0).isKept, "A swap adopts the new recipe's servings")
        try expect(plan.needsDiscardConfirmation, "Adjusted proposals need confirmation before discarding")

        plan.setServings(9, for: ids[1])
        try expect(dinner(1).servings == 9 && dinner(1).isKept, "Editing servings keeps the dinner")
        plan.choose(breakfast, for: ids[2])
        try expect(dinner(2).recipe?.id == breakfast.id && dinner(2).servings == 2 && dinner(2).isKept,
            "Choosing a recipe manually can use another category, adopts its servings, and keeps the dinner")
        let repeated = dinner(3).recipe!
        plan.choose(repeated, for: ids[4])
        try expect(dinner(4).recipe?.id == repeated.id, "Manual choices may repeat a recipe")
        plan.toggleKeep(ids[4])
        try expect(!dinner(4).isKept, "Keep can be turned off")
        plan.toggleKeep(ids[3])
        try expect(dinner(3).isKept, "Keep can be turned on")
        plan.remove(ids[5])
        try expect(dinner(5).recipe == nil && dinner(5).isRemoved, "Removing a dinner leaves its day open")

        let kept = [1, 2, 3].map { dinner($0) }
        var changed = false
        for _ in 0..<5 {
            let previous = [0, 4, 6].map { dinner($0).recipe?.id }
            plan.shuffle()
            try expect([1, 2, 3].map { dinner($0) } == kept, "Shuffling preserves kept dinners and their servings")
            try expect(dinner(5).recipe == nil && dinner(5).isRemoved, "Shuffling leaves removed days open")
            let shuffled = [0, 4, 6].compactMap { dinner($0).recipe }
            let keptIDs = Set(kept.compactMap(\.recipe?.id))
            try expect(shuffled.count == 3 && Set(shuffled.map(\.id)).count == 3 && shuffled.allSatisfy { !keptIDs.contains($0.id) && $0.category == .dinner },
                "Shuffled dinners follow automatic eligibility and avoid kept recipes")
            changed = changed || previous != [0, 4, 6].map { dinner($0).recipe?.id }
        }
        try expect(changed, "Shuffling offers different dinners when alternatives exist")

        // Seven recipes for seven days leaves nothing else to suggest.
        let exact = try await ready(recipes: Array(pool.prefix(7)))
        defer { exact.session.cancel() }
        let full = exact.store.beginAutoPlan(now: wednesday, random: SeededRandom(state: 4))!
        full.propose()
        let proposed = full.dinners
        try expect(!full.suggestAnother(for: proposed[0].id) && full.dinners == proposed
            && full.notice == "No other recipe can be suggested for this day. Choose one yourself, or keep this dinner.",
            "A swap without alternatives explains why nothing changed")
        full.shuffle()
        try expect(full.dinners == proposed && full.notice == "No other recipes can be suggested, so these dinners stay the same.",
            "A shuffle without alternatives explains why nothing changed")
        full.remove(proposed[6].id)
        full.choose(proposed[0].recipe!, for: proposed[6].id)
        try expect(full.dinners[6].recipe?.id == proposed[0].recipe?.id && !full.dinners[6].isRemoved, "Choosing a recipe fills an open day")
        full.choose(pool[8], for: proposed[5].id)
        try expect(full.dinners[5] == proposed[5], "Manual choices come from recipes available in the household")
    }

    /// A proposal for every day of next week, March 8–14, from seven Dinner recipes.
    private static func proposed(_ fixture: Fixture, seed: UInt64 = 5) -> AutoPlan {
        let plan = fixture.store.beginAutoPlan(now: wednesday, random: SeededRandom(state: seed))!
        plan.propose()
        return plan
    }

    private static func saving() async throws {
        UserDefaults.standard.set(WeekStart.sunday.rawValue, forKey: WeekStart.storageKey)
        let pool = (1...7).map { recipe("Dinner \($0)", servings: $0) }
        let fixture = try await ready(recipes: pool, groceries: [GroceryItem(name: "Milk", amount: "1 gallon", source: "General", position: 0)])
        defer { fixture.session.cancel() }
        try await until { !fixture.store.groceries.items.isEmpty }
        let groceriesBefore = fixture.store.groceries.items.map { "\($0.name)|\($0.amount)" }
        let plan = proposed(fixture)
        plan.setServings(11, for: plan.dinners[0].id)
        plan.remove(plan.dinners[1].id)
        try expect(fixture.store.meals.isEmpty, "Adjusting writes nothing before Add to plan")
        let accepted = plan.dinners.filter { $0.recipe != nil }
        await plan.addToPlan()
        try expect(plan.dinners.filter { $0.recipe != nil }.allSatisfy { $0.outcome == .added }, "Every accepted dinner is added")
        try expect(plan.notice == "Added 6 dinners.", "The result is summarized")
        try expect(!plan.needsDiscardConfirmation, "Nothing is left to discard once every dinner is added")
        await fixture.store.refresh()
        let saved = fixture.store.meals
        try expect(saved.count == 6 && Set(saved.map(\.id)) == Set(accepted.map(\.mealID)), "Only accepted dinners become planned meals")
        for dinner in accepted {
            let meal = saved.first { $0.id == dinner.mealID }!
            try expect(Calendar.current.isDate(meal.date, inSameDayAs: dinner.date) && meal.servings == dinner.servings
                && meal.recipeID == dinner.recipe?.id && meal.recipe.hasSameVersion(as: dinner.recipe!),
                "Saved meals keep the reviewed version, date, and servings")
        }
        try expect(!saved.contains { Calendar.current.isDate($0.date, inSameDayAs: day(9)) }, "Removed days stay open")
        try expect(fixture.store.groceries.items.map { "\($0.name)|\($0.amount)" } == groceriesBefore, "Adding dinners leaves groceries unchanged")
        let review = GroceryReview(meals: saved, notes: [])
        try expect(review.candidates.count == 6, "Added dinners work with grocery import review")
        var edited = pool[0]; edited.steps = ["Changed later."]
        fixture.store.saveRecipe(edited)
        await fixture.store.waitForSaves()
        try expect(fixture.store.meals.first { $0.recipeID == pool[0].id }?.recipe.steps == pool[0].steps,
            "Later recipe edits leave added dinners unchanged")
    }

    private static func saveConflicts() async throws {
        let pool = (1...7).map { recipe("Dinner \($0)") }
        let fixture = try await ready(recipes: pool)
        defer { fixture.session.cancel() }
        let plan = proposed(fixture)
        let dinners = plan.dinners
        // Another member plans two days and edits and deletes recipes after this proposal was made.
        let other = PlannedMeal(date: day(8), recipe: pool[0], recipeID: pool[0].id, servings: 2)
        try await fixture.backend.write(.saveMeal(other, household: fixture.household.id, keepVersion: false))
        try await fixture.backend.write(.saveNote(MealPlanNote(date: day(9), text: "Dinner out"), household: fixture.household.id))
        var edited = dinners[2].recipe!; edited.steps = ["Edited elsewhere."]
        try await fixture.backend.write(.saveRecipe(edited, isNew: false, upload: nil, stalePhoto: nil))
        try await fixture.backend.write(.deleteRecipe(dinners[3].recipe!.id))
        await plan.addToPlan()
        try expect(plan.dinners[0].outcome == .skipped && plan.dinners[1].outcome == .skipped, "Days that gained a recipe or note are skipped")
        try expect(plan.dinners[2].outcome == .changed, "A recipe edited after review needs another review")
        try expect(plan.dinners[3].outcome == .unavailable, "A deleted recipe needs a replacement")
        try expect(plan.dinners[4...].allSatisfy { $0.outcome == .added }, "Other dinners are still added")
        try expect(plan.notice == "Added 3 dinners. 2 days already have plans, so they were skipped. "
            + "1 recipe changed since you reviewed it. 1 recipe isn’t available anymore.", "Each outcome is explained")
        let meals = fixture.store.meals
        try expect(meals.filter { Calendar.current.isDate($0.date, inSameDayAs: day(8)) }.map(\.id) == [other.id],
            "Another member's new meal is preserved")
        try expect(fixture.store.notes.contains { $0.text == "Dinner out" }, "Another member's new note is preserved")
        try expect(!meals.contains { $0.id == dinners[2].mealID } && !meals.contains { $0.id == dinners[3].mealID },
            "Changed and unavailable recipes aren't saved")
        try expect(plan.needsDiscardConfirmation, "Closing with unresolved dinners asks first, even without adjustments")

        plan.useLatestVersion(for: dinners[2].id)
        try expect(plan.dinners[2].recipe?.steps == ["Edited elsewhere."] && plan.dinners[2].outcome == nil, "The changed recipe can be reviewed again")
        plan.suggestAnother(for: dinners[3].id)
        try expect(plan.dinners[3].outcome == .unavailable, "No eligible replacement exists while every other recipe is taken")
        let repeated = plan.dinners[4].recipe!
        plan.choose(repeated, for: dinners[3].id)
        try expect(plan.dinners[3].recipe?.id == repeated.id && plan.dinners[3].outcome == nil, "An unavailable recipe can be replaced")
        plan.setServings(5, for: dinners[4].id)
        try expect(plan.dinners[4].servings == dinners[4].servings, "Added dinners can't change")
        await plan.addToPlan()
        try expect(plan.dinners[2].outcome == .added && plan.dinners[3].outcome == .added, "Reviewed dinners are added on retry")
        try expect(fixture.store.meals.count == 6, "Retrying adds no duplicates")
    }

    private static func saveRecovery() async throws {
        let pool = (1...7).map { recipe("Dinner \($0)") }
        let fixture = try await ready(recipes: pool)
        defer { fixture.session.cancel() }
        let plan = proposed(fixture)
        plan.toggleKeep(plan.dinners[0].id)
        let lost = plan.dinners[1].mealID, failing = plan.dinners[2].mealID
        fixture.backend.beforeAddMeal = { meal in if meal.id == failing { throw URLError(.notConnectedToInternet) } }
        fixture.backend.afterAddMeal = { meal in if meal.id == lost { throw URLError(.networkConnectionLost) } }
        await plan.addToPlan()
        try expect(plan.dinners[1].outcome == .failed && plan.dinners[2].outcome == .failed, "Unconfirmed dinners stay in the proposal")
        try expect(plan.dinners.filter { $0.outcome == .added }.count == 5, "Successful dinners are kept after a partial failure")
        try expect(plan.notice == "Added 5 dinners. Couldn’t confirm 2 dinners. Try again when you’re connected. Dinners already added won’t be added twice.",
            "Failures name a next step")
        try expect(plan.needsDiscardConfirmation, "Closing with unsaved dinners asks first")
        fixture.backend.beforeAddMeal = nil
        fixture.backend.afterAddMeal = nil
        await plan.addToPlan()
        try expect(plan.dinners.allSatisfy { $0.outcome == .added }, "Retrying recognizes the lost acknowledgement and adds the rest")
        await fixture.store.refresh()
        try expect(fixture.store.meals.count == 7 && fixture.store.meals.filter { $0.id == lost }.count == 1, "Retries never duplicate a meal")

        let emptyPlan = try await ready(recipes: pool)
        defer { emptyPlan.session.cancel() }
        let removed = proposed(emptyPlan)
        for dinner in removed.dinners { removed.remove(dinner.id) }
        try expect(removed.needsDiscardConfirmation, "Removing all dinners still leaves an adjusted proposal to discard")

        // A smaller pool after failed saves can leave an empty dinner during shuffle.
        let shrinking = try await ready(recipes: Array(pool.prefix(2)))
        defer { shrinking.session.cancel() }
        let shuffled = proposed(shrinking)
        shrinking.backend.beforeAddMeal = { _ in throw URLError(.notConnectedToInternet) }
        await shuffled.addToPlan()
        for recipe in pool.prefix(2) { try await shrinking.backend.write(.deleteRecipe(recipe.id)) }
        try await shrinking.backend.write(.saveRecipe(recipe("Replacement"), isNew: true, upload: nil, stalePhoto: nil))
        await shrinking.store.refresh()
        try expect(shuffled.shuffle(), "Shuffling uses the remaining replacement and leaves other days open")
        shrinking.backend.beforeAddMeal = nil
        await shuffled.addToPlan()
        try expect(shuffled.isFinished && !shuffled.canAddToPlan && shrinking.store.meals.count == 1,
            "Empty shuffled dinners stop being uncertain once earlier saves are confirmed absent")

        // A lost response, then a change to that dinner before retrying.
        let changed = try await ready(recipes: (1...9).map { recipe("Dinner \($0)") })
        defer { changed.session.cancel() }
        let edited = proposed(changed)
        let landed = edited.dinners[0]
        changed.backend.afterAddMeal = { meal in if meal.id == landed.mealID { throw URLError(.networkConnectionLost) } }
        changed.backend.beforeSnapshot = { _ in throw URLError(.notConnectedToInternet) }
        await edited.addToPlan()
        changed.backend.afterAddMeal = nil
        try expect(edited.dinners[0].outcome == .failed, "The lost response leaves the dinner unconfirmed")
        try expect(edited.suggestAnother(for: landed.id), "An unconfirmed dinner can still change")
        await edited.addToPlan()
        try expect(!edited.dinners[0].isSettled && edited.canAddToPlan && edited.needsDiscardConfirmation,
            "A failed reconciliation keeps the changed dinner retryable instead of treating its landed save as a conflict")
        edited.remove(landed.id)
        try expect(edited.canAddToPlan && !edited.isFinished && edited.needsDiscardConfirmation,
            "Removing the last unconfirmed dinner still allows its save to be checked")
        changed.backend.beforeSnapshot = nil
        await edited.addToPlan()
        try expect(edited.dinners[0].outcome == .added && edited.dinners[0].recipe?.id == landed.recipe?.id
            && edited.dinners[0].servings == landed.servings,
            "A save that landed is recognized, showing what was actually added, rather than reported as a conflict")
        try expect(changed.store.meals.count(where: { Calendar.current.isDate($0.date, inSameDayAs: landed.date) }) == 1, "The day gets one dinner")
    }

    private static func householdChanges() async throws {
        let pool = (1...7).map { recipe("Dinner \($0)") }
        let fixture = try await ready(recipes: pool)
        defer { fixture.session.cancel() }
        let plan = proposed(fixture)
        let gate = Gate()
        fixture.backend.beforeAddMeal = { _ in await gate.wait() }
        let saving = Task { await plan.addToPlan() }
        try await until { gate.entered }
        fixture.backend.beforeAddMeal = nil
        let leaving = try await fixture.backend.previewMove(code: nil)
        let moved = try await fixture.backend.move(code: nil, saveRecipes: false, expected: leaving.currentHouseholdID)
        fixture.backend.emit(.membership, household: fixture.household.id)
        try await until { fixture.store.household?.id == moved.household.id && fixture.store.phase == .ready }
        try expect(fixture.store.autoPlan == nil, "Changing households discards the proposal")
        gate.release()
        await saving.value
        try expect(fixture.store.meals.isEmpty, "Late save results can't publish into the new household")
        let former = try await fixture.backend.snapshot(household: fixture.household.id)
        try expect(former.meals.isEmpty, "The proposal writes nothing once its member has left the household")
        try expect(fixture.store.beginAutoPlan(now: wednesday)?.householdID == moved.household.id, "A new proposal belongs to the new household")
    }
}
