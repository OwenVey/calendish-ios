import Foundation

@main
struct CookedHistoryTests {
    static func check(_ condition: Bool, _ message: String) {
        if !condition { print("FAIL: \(message)"); exit(1) }
    }

    static func main() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 18))!
        func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))! }
        let recipes = SampleRecipes.all
        let (orzo, bowls, oats) = (recipes[0], recipes[1], recipes[2])

        // Days carry where they came from: marked, a past planned meal, or both on the same day.
        let cooks = [
            RecipeCook(recipeID: orzo.id, date: daysAgo(21).addingTimeInterval(3600 * 19)),
            RecipeCook(recipeID: bowls.id, date: daysAgo(3)),
        ]
        let meals = [
            PlannedMeal(date: daysAgo(21), recipe: orzo, recipeID: orzo.id, servings: 4),
            PlannedMeal(date: daysAgo(40), recipe: orzo, recipeID: orzo.id, servings: 4),
            // Today's and future meals haven't been cooked yet.
            PlannedMeal(date: daysAgo(0), recipe: oats, recipeID: oats.id, servings: 2),
            // A meal whose source recipe was deleted counts toward no recipe.
            PlannedMeal(date: daysAgo(5), recipe: bowls, recipeID: nil, servings: 2),
        ]
        let histories = CookedHistory.make(cooks: cooks, meals: meals, now: now)
        check(histories[orzo.id]?.days == [
            CookedDay(date: daysAgo(21), isMarked: true, isPlanned: true),
            CookedDay(date: daysAgo(40), isMarked: false, isPlanned: true),
        ], "days merge, sort, and keep their source: \(String(describing: histories[orzo.id]?.days))")
        check(histories[orzo.id]?.lastCooked == daysAgo(21), "last cooked")
        check(histories[orzo.id]?.isMarked(on: daysAgo(21).addingTimeInterval(60)) == true, "marked day")
        check(histories[orzo.id]?.isMarked(on: daysAgo(40)) == false, "planned day can't be removed")
        check(histories[orzo.id]?.contains(daysAgo(40)) == true, "contains planned day")
        check(histories[oats.id] == nil, "today's planned meal isn't cooked yet")
        check(histories[bowls.id]?.days == [CookedDay(date: daysAgo(3), isMarked: true, isPlanned: false)], "marked only")

        check(CookedHistory.lastCookedText(histories[orzo.id], now: now) == "Last cooked 3 weeks ago", "last cooked text")
        check(CookedHistory.lastCookedText(nil, now: now) == "Not cooked yet", "not cooked text")
        check(CookedHistory.cookedAgo(daysAgo(0), now: now) == "today", "today: \(CookedHistory.cookedAgo(daysAgo(0), now: now))")
        check(CookedHistory.cookedAgo(daysAgo(1), now: now) == "yesterday", "yesterday")
        check(CookedHistory.cookedAgo(daysAgo(65), now: now) == "2 months ago", "months")

        // Which recipe a cook counts toward.
        let book = [orzo, bowls]
        check(CookedHistory.recipeID(cooking: orzo, in: book) == orzo.id, "recipe in the book")
        check(CookedHistory.recipeID(cooking: oats, in: book) == nil, "recipe not in the book")
        // A saved version counts toward its source recipe, even after the source became a household copy with a new ID.
        let moved = PlannedMeal(date: daysAgo(1), recipe: orzo, recipeID: bowls.id, servings: 4)
        check(CookedHistory.recipeID(cooking: orzo, plannedMeal: moved, in: book) == bowls.id, "planned meal's source")
        let orphaned = PlannedMeal(date: daysAgo(1), recipe: orzo, recipeID: nil, servings: 4)
        check(CookedHistory.recipeID(cooking: orzo, plannedMeal: orphaned, in: book) == nil, "planned meal without a source")

        // A cook counts for the day cooking started, even when it finishes after midnight.
        let lateStart = calendar.date(byAdding: .minute, value: 23 * 60 + 40, to: daysAgo(1))!
        check(FinishedCook(recipeID: orzo.id, startedAt: lateStart, accountID: nil).day == daysAgo(1), "day cooking started")

        // Finished cooks wait on the device until a household loads, then record for the same account only.
        let me = UUID(), someoneElse = UUID()
        let defaults = UserDefaults(suiteName: "cooked-history-tests-\(UUID().uuidString)")!
        let finished = FinishedCooks(defaults: defaults)
        finished.add(FinishedCook(recipeID: orzo.id, startedAt: now, accountID: me))
        finished.add(FinishedCook(recipeID: bowls.id, startedAt: now, accountID: someoneElse))
        check(FinishedCooks(defaults: defaults).pending.count == 2, "pending cooks survive relaunch")
        var recorded: [UUID] = []
        finished.record(for: me) { cook, acknowledge in recorded.append(cook.recipeID); acknowledge(true) }
        check(recorded == [orzo.id], "records own cooks, drops another account's: \(recorded)")
        check(finished.pending.isEmpty, "drained")
        finished.add(FinishedCook(recipeID: bowls.id, startedAt: now, accountID: me))
        check(recorded == [orzo.id, bowls.id], "records right away while loaded")
        finished.stopRecording()
        finished.add(FinishedCook(recipeID: oats.id, startedAt: now, accountID: me))
        check(recorded.count == 2 && finished.pending.count == 1, "waits again after the household unloads")
        // Delivery is not acknowledgment: failures and process interruption keep the cook durable.
        var acknowledge: ((Bool) -> Void)?
        finished.record(for: me) { _, completion in acknowledge = completion }
        check(finished.pending.count == 1, "in-flight cook remains durable")
        acknowledge?(false)
        check(FinishedCooks(defaults: defaults).pending.count == 1, "failed delivery survives relaunch")
        finished.retry()
        let staleAcknowledgment = acknowledge
        finished.stopRecording()
        finished.record(for: me) { _, completion in acknowledge = completion }
        staleAcknowledgment?(true)
        check(finished.pending.count == 1, "old session cannot acknowledge current delivery")
        acknowledge?(true)
        check(finished.pending.isEmpty, "acknowledged delivery drains")

        let cook = FinishedCook(recipeID: orzo.id, startedAt: now, accountID: me)
        finished.record(for: me) { _, completion in acknowledge = completion }
        finished.add(cook); finished.add(cook)
        check(finished.pending.count == 1, "duplicate pending cook is retained only once")
        acknowledge?(true)
        // Repeating a completion must not affect the next delivery.
        let repeatedAcknowledgment = acknowledge
        finished.add(FinishedCook(recipeID: bowls.id, startedAt: now, accountID: me))
        repeatedAcknowledgment?(true)
        check(finished.pending.count == 1, "repeated acknowledgment cannot drain next cook")
        acknowledge?(true)
        check(finished.pending.isEmpty, "next cook acknowledged independently")
        print("Cooked history tests passed")
    }
}
