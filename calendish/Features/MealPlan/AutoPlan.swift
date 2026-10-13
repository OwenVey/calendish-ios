import Observation
import SwiftUI

/// A meal plan proposal: a week of dinners drawn from saved recipes, adjusted before anything is added to the household's plan.
/// It lives only for this app session and belongs to the household it started in.
@Observable
final class AutoPlan {
    enum Availability: Equatable {
        /// Empty, today or later.
        case open
        /// Before today.
        case past
        /// Already has a recipe or a meal-plan note, which auto planning leaves alone.
        case planned
    }

    struct Day: Identifiable, Equatable {
        let date: Date
        var availability: Availability
        var isSelected: Bool
        var id: Date { date }
    }

    /// One selected day's dinner.
    struct Dinner: Identifiable, Equatable {
        let id = UUID()
        /// The planned meal this dinner saves as, so retrying can't add it twice. A different recipe gets a new one,
        /// so an earlier save that may have landed can't be mistaken for it.
        var mealID = UUID()
        /// Meal IDs from earlier saves that couldn't be confirmed, so one that landed is recognized after a change.
        var unconfirmedMealIDs: [UUID] = []
        let date: Date
        /// The recipe version the person reviewed, or nil while the day is open.
        var recipe: Recipe?
        var servings: Int
        /// Kept dinners survive shuffling.
        var isKept = false
        /// The person removed this dinner, so shuffling leaves the day open.
        var isRemoved = false
        /// What happened the last time this dinner was added to the plan.
        var outcome: Outcome?
        /// Added and skipped dinners are settled; the rest can still change and be added.
        var isSettled: Bool { outcome == .added || outcome == .skipped }
    }

    enum Outcome: Equatable {
        case added
        /// The day gained a recipe or note from someone else, so it was left alone.
        case skipped
        /// The recipe was edited since it was proposed, so it needs another look.
        case changed
        /// The recipe was deleted or isn't available anymore, so it needs a replacement.
        case unavailable
        /// The save couldn't be confirmed. Retrying is safe.
        case failed
    }

    let householdID: UUID
    /// The first day of the chosen week.
    private(set) var week: Date
    private(set) var days: [Day] = []
    /// Empty until the person asks for suggestions.
    private(set) var dinners: [Dinner] = []
    /// Why fewer dinners were suggested than requested, or why a change couldn't be made.
    private(set) var notice: String?
    /// Whether the person changed the proposal, so closing it should ask before discarding their choices.
    private(set) var isAdjusted = false
    private(set) var isSaving = false
    /// Dinners with a recipe that haven't been added yet.
    var unsavedDinners: [Dinner] { dinners.filter { $0.recipe != nil && !$0.isSettled } }
    /// Closing asks first once the person has adjusted dinners or tried to add them, while any remain unsaved.
    var needsDiscardConfirmation: Bool { !isFinished && (isAdjusted || dinners.contains { $0.outcome != nil } || hasUnconfirmedSaves) }
    /// Every dinner with a recipe has been added or skipped.
    var isFinished: Bool { unsavedDinners.isEmpty && !hasUnconfirmedSaves && dinners.contains { $0.outcome != nil } }
    /// Includes removed dinners whose earlier save may still have landed.
    private var hasUnconfirmedSaves: Bool { dinners.contains { $0.outcome == .failed || !$0.unconfirmedMealIDs.isEmpty } }
    var canAddToPlan: Bool { !unsavedDinners.isEmpty || hasUnconfirmedSaves }
    /// Whether any dinner would change on shuffling.
    var canShuffle: Bool { dinners.contains(where: isShuffleable) }

    @ObservationIgnored private weak var store: HouseholdStore?
    @ObservationIgnored private let now: Date
    @ObservationIgnored private let weekStart: WeekStart
    @ObservationIgnored private var random: AnyRandom

    init(store: HouseholdStore, householdID: UUID, now: Date, weekStart: WeekStart, random: any RandomNumberGenerator) {
        self.store = store
        self.householdID = householdID
        self.now = now
        self.weekStart = weekStart
        self.random = AnyRandom(base: random)
        let thisWeek = CalendarDays.startOfWeek(now, weekStart: weekStart)
        week = Calendar.current.date(byAdding: .day, value: 7, to: thisWeek)!
        loadDays()
    }

    private var thisWeek: Date { CalendarDays.startOfWeek(now, weekStart: weekStart) }
    var canShowPreviousWeek: Bool { week > thisWeek }
    /// Zero for the current week, one for next week, and so on.
    var weekOffset: Int { (Calendar.current.dateComponents([.day], from: thisWeek, to: week).day ?? 0) / 7 }

    /// Moves to an earlier or later week. Weeks before the current one aren't available.
    func showWeek(offset: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: 7 * offset, to: week), next >= thisWeek else { return }
        week = next
        loadDays()
    }

    func toggleDay(_ date: Date) {
        guard let index = days.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }),
              days[index].availability == .open else { return }
        days[index].isSelected.toggle()
    }

    // MARK: Suggestions

    /// Suggests one dinner for each selected day, replacing any earlier proposal.
    func propose() {
        let selected = days.filter(\.isSelected).map(\.date)
        var picks = pick(selected.count, from: eligibleRecipes(excluding: []))
        dinners = selected.map { date in
            let recipe = picks.isEmpty ? nil : picks.removeFirst()
            return Dinner(date: date, recipe: recipe, servings: recipe.map(Self.servings) ?? 0)
        }
        notice = shortageNotice()
        isAdjusted = false
    }

    // MARK: Adjustments

    /// Replaces one dinner with a different automatic choice. Returns false, with a notice, when no other recipe qualifies.
    @discardableResult
    func suggestAnother(for id: UUID) -> Bool {
        guard let index = editableIndex(id) else { return false }
        let taken = Set(dinners.compactMap(\.recipe?.id))
        guard let recipe = pick(1, from: eligibleRecipes(excluding: taken)).first else {
            notice = "No other recipe can be suggested for this day. Choose one yourself, or keep this dinner."
            return false
        }
        set(recipe, at: index)
        notice = shortageNotice()
        return true
    }

    /// Uses a recipe the person picked, which may repeat another dinner or have another category. Keeps the dinner.
    func choose(_ recipe: Recipe, for id: UUID) {
        guard let index = editableIndex(id), let available = store?.recipes.first(where: { $0.id == recipe.id }) else { return }
        set(available, at: index)
        dinners[index].isKept = true
        notice = shortageNotice()
    }

    /// Leaves the day open. Shuffling won't fill it again.
    func remove(_ id: UUID) {
        guard let index = editableIndex(id) else { return }
        dinners[index].recipe = nil
        dinners[index].isRemoved = true
        dinners[index].isKept = false
        renewMealID(at: index)
        isAdjusted = true
        notice = shortageNotice()
    }

    /// Changes one dinner's servings, and keeps it.
    func setServings(_ servings: Int, for id: UUID) {
        guard let index = editableIndex(id), dinners[index].recipe != nil, servings > 0 else { return }
        dinners[index].servings = servings
        dinners[index].isKept = true
        isAdjusted = true
    }

    func toggleKeep(_ id: UUID) {
        guard let index = editableIndex(id), dinners[index].recipe != nil else { return }
        dinners[index].isKept.toggle()
        isAdjusted = true
    }

    /// Suggests new dinners for every day that isn't kept or removed, favoring recipes not already shown there.
    /// Returns false, with a notice, when no other recipe qualifies.
    @discardableResult
    func shuffle() -> Bool {
        let shuffling = dinners.indices.filter { isShuffleable(dinners[$0]) }
        let kept = Set(dinners.filter { $0.isKept || $0.isSettled }.compactMap(\.recipe?.id))
        let current = Set(shuffling.compactMap { dinners[$0].recipe?.id })
        let pool = eligibleRecipes(excluding: kept)
        let fresh = pool.filter { !current.contains($0.id) }
        guard !shuffling.isEmpty, !fresh.isEmpty else {
            notice = "No other recipes can be suggested, so these dinners stay the same."
            return false
        }
        // Fill from new recipes first, then from the ones being replaced if there aren't enough.
        var picks = pick(shuffling.count, from: fresh)
        picks += pick(shuffling.count - picks.count, from: pool.filter { current.contains($0.id) })
        picks.shuffle(using: &random)
        for index in shuffling {
            if picks.isEmpty {
                dinners[index].recipe = nil
                renewMealID(at: index)
            } else {
                set(picks.removeFirst(), at: index)
            }
        }
        isAdjusted = true
        notice = shortageNotice()
        return true
    }

    private func isShuffleable(_ dinner: Dinner) -> Bool { !dinner.isKept && !dinner.isRemoved && !dinner.isSettled }

    /// A different recipe gets a new meal identity and starts from its own servings.
    private func set(_ recipe: Recipe, at index: Int) {
        dinners[index].recipe = recipe
        dinners[index].servings = Self.servings(for: recipe)
        dinners[index].isRemoved = false
        renewMealID(at: index)
        isAdjusted = true
    }

    private func renewMealID(at index: Int) {
        if dinners[index].outcome == .failed { dinners[index].unconfirmedMealIDs.append(dinners[index].mealID) }
        dinners[index].mealID = UUID()
        dinners[index].outcome = nil
    }

    /// Reviews a recipe edited since it was proposed, adopting its current version and keeping the servings.
    func useLatestVersion(for id: UUID) {
        guard let index = editableIndex(id), let recipeID = dinners[index].recipe?.id,
              let latest = store?.recipes.first(where: { $0.id == recipeID }) else { return }
        dinners[index].recipe = latest
        renewMealID(at: index)
    }

    private func editableIndex(_ id: UUID) -> Int? {
        dinners.firstIndex { $0.id == id && !$0.isSettled && !isSaving }
    }

    // MARK: Saving

    /// Adds each unsaved dinner to the household's plan. Days that gained plans are skipped, recipes edited or removed
    /// since review are held back, and dinners whose save couldn't be confirmed stay in the proposal to retry.
    func addToPlan() async {
        guard let store, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        // Let earlier meal plan edits land first.
        await store.waitForSaves()
        if hasUnconfirmedSaves {
            // Only an applied snapshot can distinguish a lost reply from somebody else's occupied day.
            do {
                guard try await store.reload() else {
                    notice = "Couldn’t confirm earlier saves. Try again when you’re connected."
                    return
                }
            } catch {
                notice = "Couldn’t confirm earlier saves. Try again when you’re connected."
                return
            }
            guard store.autoPlan === self else { return }
            recognizeLandedSaves()
        }
        for dinner in unsavedDinners {
            guard store.autoPlan === self, let reviewed = dinner.recipe else { return }
            let outcome: Outcome
            if let latest = store.recipes.first(where: { $0.id == reviewed.id }) {
                if latest.hasSameVersion(as: reviewed) {
                    let meal = PlannedMeal(id: dinner.mealID, date: dinner.date, recipe: reviewed, recipeID: reviewed.id, servings: dinner.servings)
                    do {
                        // The content matches, so the current revision is the one the person reviewed.
                        outcome = switch try await store.addProposedMeal(meal, household: householdID, expectedRevision: latest.revision ?? 1) {
                        case .added, .alreadyAdded: .added
                        case .occupied: .skipped
                        case .changed: .changed
                        case .unavailable: .unavailable
                        }
                    } catch is CancellationError { return } catch { outcome = .failed }
                } else { outcome = .changed }
            } else { outcome = .unavailable }
            guard store.autoPlan === self, let index = dinners.firstIndex(where: { $0.id == dinner.id }) else { return }
            dinners[index].outcome = outcome
        }
        guard store.autoPlan === self else { return }
        notice = saveSummary()
        await store.refresh()
    }

    /// A save whose response was lost may have landed. Shows what was actually added instead of retrying,
    /// even if the person changed the dinner since.
    private func recognizeLandedSaves() {
        guard let store else { return }
        for index in dinners.indices where !dinners[index].isSettled {
            let ids = Set(dinners[index].unconfirmedMealIDs + [dinners[index].mealID])
            dinners[index].unconfirmedMealIDs = []
            guard let meal = store.meals.first(where: { ids.contains($0.id) }) else {
                if dinners[index].recipe == nil { dinners[index].outcome = nil }
                continue
            }
            dinners[index].recipe = store.recipes.first { $0.id == meal.recipeID && $0.hasSameVersion(as: meal.recipe) } ?? meal.recipe
            dinners[index].servings = meal.servings
            dinners[index].mealID = meal.id
            dinners[index].isRemoved = false
            dinners[index].outcome = .added
        }
    }

    private func saveSummary() -> String {
        func count(_ outcome: Outcome) -> Int { dinners.count { $0.outcome == outcome && $0.recipe != nil } }
        var sentences: [String] = []
        let added = count(.added)
        if added > 0 { sentences.append(added == 1 ? "Added 1 dinner." : "Added \(added) dinners.") }
        let skipped = count(.skipped)
        if skipped > 0 { sentences.append(skipped == 1 ? "1 day already has plans, so it was skipped." : "\(skipped) days already have plans, so they were skipped.") }
        let changed = count(.changed)
        if changed > 0 { sentences.append(changed == 1 ? "1 recipe changed since you reviewed it." : "\(changed) recipes changed since you reviewed them.") }
        let unavailable = count(.unavailable)
        if unavailable > 0 { sentences.append(unavailable == 1 ? "1 recipe isn’t available anymore." : "\(unavailable) recipes aren’t available anymore.") }
        let failed = count(.failed)
        if failed > 0 {
            sentences.append(failed == 1 ? "Couldn’t confirm 1 dinner." : "Couldn’t confirm \(failed) dinners.")
            sentences.append("Try again when you’re connected. Dinners already added won’t be added twice.")
        }
        return sentences.joined(separator: " ")
    }

    /// Starting servings: the recipe's own, or the Settings default when it has no usable count.
    private static func servings(for recipe: Recipe) -> Int {
        recipe.servings > 0 ? recipe.servings : PreferenceKey.servingsForNewRecipes
    }

    private func shortageNotice() -> String? {
        let open = dinners.filter { $0.recipe == nil && !$0.isRemoved }.count
        guard open > 0 else { return nil }
        let suggested = dinners.count { $0.recipe != nil }
        if suggested == 0, dinners.allSatisfy({ !$0.isKept }) {
            return "None of your saved recipes can be suggested. Only Dinner recipes and recipes without a category are suggested; "
                + "choose recipes for these days yourself."
        }
        let recipes = suggested == 1 ? "Only 1 recipe can" : "Only \(suggested) recipes can"
        let days = open == 1 ? "1 day stays" : "\(open) days stay"
        return "\(recipes) be suggested, so \(days) open. Choose recipes for them yourself."
    }

    /// Recipes automatic choices may use: Dinner or uncategorized, not planned within a week of the chosen week,
    /// and not already in the proposal.
    private func eligibleRecipes(excluding taken: Set<UUID>) -> [Recipe] {
        guard let store else { return [] }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -7, to: week)!
        let end = calendar.date(byAdding: .day, value: 14, to: week)!
        let nearby = Set(store.meals.filter { (start..<end).contains(calendar.startOfDay(for: $0.date)) }.compactMap(\.recipeID))
        return store.recipes.filter { recipe in
            (recipe.category == nil || recipe.category == .dinner) && !nearby.contains(recipe.id) && !taken.contains(recipe.id)
        }
    }

    /// Chooses up to `count` different recipes at random, weighted toward favorites, well-rated recipes,
    /// and ones the household hasn't cooked lately. Every eligible recipe keeps some chance.
    private func pick(_ count: Int, from pool: [Recipe]) -> [Recipe] {
        guard let store else { return [] }
        let stats = store.recipeStats(now: now)
        let today = Calendar.current.startOfDay(for: now)
        var weighted = pool.map { recipe in
            let stat = stats[recipe.id]
            let liked = (recipe.isFavorite ? 3 : 0) + max(0, (stat?.averageRating ?? 0) - 3) * 1.5
            // Up to two points for a long gap. Never-cooked recipes count as six weeks, so a favorite last cooked
            // long ago edges out one nobody has tried.
            let days = stat?.history.lastCooked.map { Calendar.current.dateComponents([.day], from: $0, to: today).day ?? 0 } ?? 45
            return (recipe: recipe, weight: 1 + liked + Double(min(max(days, 0), 90)) / 45)
        }
        var picks: [Recipe] = []
        while picks.count < count, !weighted.isEmpty {
            var target = Double.random(in: 0..<weighted.map(\.weight).reduce(0, +), using: &random)
            let index = weighted.firstIndex { target -= $0.weight; return target < 0 } ?? weighted.count - 1
            picks.append(weighted.remove(at: index).recipe)
        }
        return picks
    }

    private func loadDays() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        days = CalendarDays.week(containing: week, weekStart: weekStart).map { date in
            let availability: Availability = if date < today { .past }
                else if isPlanned(date) { .planned }
                else { .open }
            return Day(date: date, availability: availability, isSelected: availability == .open)
        }
    }

    private func isPlanned(_ date: Date) -> Bool {
        guard let store else { return false }
        return store.meals.contains { Calendar.current.isDate($0.date, inSameDayAs: date) }
            || store.notes.contains { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }
}

/// Lets tests pass a seeded generator while standard library APIs get a concrete type.
private struct AnyRandom: RandomNumberGenerator {
    var base: any RandomNumberGenerator
    mutating func next() -> UInt64 { base.next() }
}
