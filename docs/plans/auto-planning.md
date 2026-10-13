# Auto plan a week of dinners

Published as [GitHub issue #4](https://github.com/OwenVey/calendish-ios/issues/4), labeled `ready-for-agent`.

## Problem Statement

Choosing what to cook each week is a recurring chore. A household member already has saved recipes in Calendish but must individually select recipes and dates to build a meal plan. They want a reasonable week of dinners they can adjust, without disturbing existing plans or adding groceries before reviewing ingredients.

## Solution

Add an “Auto plan” toolbar action to the Meal plan tab. A person chooses a calendar week and empty days, reviews a meal plan proposal drawn from saved recipes, adjusts dinners as needed, and taps “Add to plan.” Default to next week and one dinner per selected empty day. Favor favorites, household ratings, less recently cooked recipes, and variety. Preserve existing recipes and notes, and leave grocery additions to the existing grocery import review.

## User Stories

1. As a household member, I want to start auto planning from the Meal plan tab, so that I can reduce the weekly chore of deciding what to cook.
2. As a household member, I want next week selected initially, so that I can prepare the coming week's dinners quickly.
3. As a household member, I want to choose another current or future calendar week, so that I can plan the dates that suit me.
4. As a household member, I want weeks to follow my week-start setting, so that auto planning matches the calendar I already use.
5. As a household member, I want to choose which days receive dinners, so that I can leave room for leftovers, eating out, and other plans.
6. As a household member, I want empty days selected initially, so that I do not have to identify every available day myself.
7. As a household member, I want days with recipes or notes to be unavailable with an explanation, so that existing plans remain intact.
8. As a household member, I want to plan today and future days in the current week, so that I can finish planning a week already underway.
9. As a household member, I want past days and past weeks excluded, so that suggestions concern meals still to come.
10. As a household member, I want one dinner suggested per selected day, so that the proposal is a manageable starting point.
11. As a household member, I want suggestions from saved recipes available to me in my household, so that I can use my existing collection.
12. As a household member, I want Dinner and uncategorized recipes eligible, so that I do not need to categorize my entire collection first.
13. As a household member, I want explicitly labeled Breakfast, Lunch, Dessert, and Snack recipes excluded from automatic choices, so that the proposal fits dinner planning.
14. As a household member, I want my favorites favored, so that familiar meals I like are more likely to appear.
15. As a household member, I want strong household ratings favored, so that the proposal reflects what household members enjoy.
16. As a household member, I want recipes cooked less recently favored, so that dinners have variety over time.
17. As a household member, I want other eligible saved recipes considered even without favorites or high ratings, so that a small review history does not prevent planning.
18. As a household member, I want recently cooked recipes to remain possible, so that a strict recency cutoff does not unnecessarily empty my week.
19. As a household member, I want recipes planned in or near the chosen week excluded from automatic choices, so that the proposal avoids nearby repeats.
20. As a household member, I want different recipes across automatically suggested dinners, so that the week is varied.
21. As a household member, I want generation and shuffling to offer different possibilities when alternatives exist, so that I do not always receive the same highest-ranked set.
22. As a household member, I want each dinner to start with its recipe's default servings, so that the proposal respects how that recipe is normally prepared.
23. As a household member, I want the Settings default servings used when a recipe has no usable serving count, so that the dinner still has a serving count.
24. As a household member, I want to adjust individual serving counts, so that each dinner can suit the people eating it.
25. As a household member, I want swapping a recipe to adopt the replacement recipe's default servings, so that the serving count fits the new recipe.
26. As a household member, I want a proposal before anything is saved, so that I can decide whether the week works for me.
27. As a household member, I want an automatic alternative for one dinner, so that I can change that dinner without disturbing the others.
28. As a household member, I want to choose a specific saved recipe manually, so that I can override the automatic suggestion.
29. As a household member, I want to choose a repeated recipe or another available category manually, so that automatic eligibility rules do not prevent an intentional choice.
30. As a household member, I want to remove a proposed dinner, so that I can leave that day open.
31. As a household member, I want removed days to stay open during shuffling, so that shuffling respects my adjustments.
32. As a household member, I want to mark a dinner as Keep, so that it survives shuffling.
33. As a household member, I want manual recipe choices and serving edits to mark a dinner as Keep automatically, so that shuffling does not unexpectedly undo my work.
34. As a household member, I want to toggle Keep off, so that I can make that dinner eligible for shuffling again.
35. As a household member, I want to shuffle unkept dinners together, so that I can explore another week while retaining choices I like.
36. As a household member, I want a shortage explained and remaining days left open when too few recipes qualify, so that the app does not silently repeat recipes or use excluded categories.
37. As a household member, I want an explanation when no automatic alternative is available, so that I understand why a swap or shuffle cannot change a dinner.
38. As a household member, I want to add only the dinners I accept with “Add to plan,” so that the household plan reflects my final choices.
39. As a household member, I want groceries unchanged when I add dinners, so that I can review ingredients and quantities separately.
40. As a household member, I want newly planned meals to work with grocery import review, so that I can prepare a shopping list through the existing flow.
41. As a household member, I want another member's newly added recipe or note preserved when I save, so that my older proposal does not disturb their plan.
42. As a household member, I want to know which days were skipped during saving, so that I can see what remains unresolved.
43. As a household member, I want changed recipes reviewed again and unavailable recipes replaced before saving, so that the saved version is the one I accepted.
44. As a household member, I want successfully added dinners retained if another dinner fails to save, so that a partial failure does not discard completed work.
45. As a household member, I want unsaved suggestions retained and retryable without duplicate meals, so that I can recover from interrupted saves safely.
46. As a household member, I want confirmation before discarding an adjusted proposal, so that I do not accidentally lose my choices.
47. As a household member, I want proposals tied to their original household and discarded when I change households, so that dinners cannot be added to the wrong household.
48. As a household member, I want saved meals to retain their reviewed recipe versions and serving counts, so that later recipe changes do not alter the plan I accepted.

## Implementation Decisions

The product behavior below was settled in the design interview. Module and save-contract details are implementation guidance inferred from the existing architecture; they must satisfy these behaviors without introducing unrelated abstractions.

- **Entry and calendar:** Extend the Meal plan tab with the Auto plan action and a week/day selection flow. Use existing calendar-day and week-start behavior. Default to next week, select eligible empty days, and permit current/future weeks only. Today is eligible; earlier days are not. Use calendar dates rather than rolling 24-hour intervals.
- **Existing entries:** A recipe or any note makes a day unavailable, regardless of its contents. Explain unavailable days. Auto planning never clears, replaces, or appends to an occupied day. Do not reintroduce breakfast/lunch/dinner slots or a global one-meal-per-day constraint: manual planning still permits multiple recipes and notes.
- **Recipe access:** Use the existing visible recipe collection and personal/shared/household recipe access rules. Do not fetch or invent new recipes. Automatic choices accept Dinner and uncategorized recipes only. Manual choice uses the existing saved-recipe access rules and can intentionally override category and repeat exclusions.
- **Eligibility and selection:** Automatically use each recipe at most once in a proposal. Exclude source recipes already planned anywhere in the selected week or the seven calendar days immediately before or after it, inclusive. An automatic alternative must differ from the replaced recipe and avoid recipes in other proposed dinners, including kept dinners. If there are no alternatives, explain this rather than pretending a change occurred.
- **Preferences:** Reuse existing personal favorites, current household members' ratings, and Cooked history. Cooked history includes marked cooks and past planned meals. Favor less recently cooked recipes without imposing the existing suggestion list's strict 14-day cutoff or favorite/high-rating-only qualification. Use varied selection among eligible recipes while preserving these preferences; exact ranking weights are implementation details, not fixed acceptance criteria.
- **Shortages:** Propose as many distinct eligible recipes as possible for selected days. Leave the remainder open and explain the shortage, including an empty recipe pool. Do not automatically repeat recipes or relax category/nearby-plan exclusions. Manual choices can fill open days intentionally.
- **Servings:** Initialize each dinner from its recipe's serving count, with the Settings default as fallback when unavailable. Allow individual edits. Any recipe swap resets servings to the replacement recipe's default or fallback. Do not add a common weekly serving count or a remembered auto-planning serving preference. The existing recipe model currently requires a serving count; the fallback is defensive behavior, not a request to make that field optional.
- **Proposal module:** Keep proposal state separate from persisted planned meals. Expose generation, individual changes, Keep, shuffle, and save outcomes through a compact feature-level workflow interface integrated with HouseholdStore. Reuse the existing HouseholdBackend seam and its production/in-memory adapters; avoid separate public seams for ranking, random choice, and each adjustment. Views consume workflow state rather than distributing selection and retry rules across view actions.
- **Proposal adjustments:** Allow automatic alternatives, manual recipe choice, removal, and serving edits. Keep can be toggled explicitly. Manual recipe selection and serving edits automatically set Keep. Shuffle only unkept dinners, preserving kept dinner contents/servings and explicitly removed days. Respect all automatic eligibility rules when selecting replacements.
- **Proposal lifetime:** Hold proposals temporarily for the current app session; do not persist them across launches. Closing an adjusted proposal requires a discard confirmation. A household change discards the proposal and invalidates ongoing work associated with its original household. Follow existing session cancellation/stale-result protections so late work cannot populate or write to another household.
- **Explicit save:** No proposal changes write planned meals or groceries before Add to plan. Saving creates ordinary planned meals with source recipe identity, reviewed recipe version, date, and accepted servings. Existing editing, moving, recipe-version preservation, and grocery import review continue to work.
- **Authoritative save checks:** The existing single-meal save path alone does not enforce these proposal guarantees. Extend the backend write contract as needed to check household membership, day vacancy for both recipes and notes, and the expected reviewed recipe version as part of the authoritative save. A client-only check before calling an unconditional save is insufficient for concurrent edits. Preserve existing manual save semantics.
- **Save results and retry:** Expose actionable results for added dinners, occupied/skipped days, changed or unavailable recipes requiring review, and failed/unsaved suggestions. Bind stable meal/request identities to each accepted suggestion so a retry or a lost acknowledgement cannot add the same dinner twice. Identify a previously successful save before treating its day as an unrelated occupancy conflict. Keep unresolved suggestions available during the proposal session; do not resubmit acknowledged additions as new meals.
- **Concurrent recipe changes:** Validate the reviewed version at saving, including changes between a client refresh and the write. Require another review for a changed recipe and replacement for a deleted/inaccessible recipe. Never silently capture a newer version. Once saved, preserve the version according to the existing recipe-ownership ADR.
- **Groceries and notes:** Adding dinners does not add groceries or generate notes for open days. Use the existing grocery import review after planning. Previously added groceries remain unchanged by recipe or meal-plan changes.
- **Persistence scope:** No durable proposal storage, meal-slot schema, or new dietary/budget preferences are required. Any backend contract or persistence changes needed for guarded, idempotent saves should be limited to those guarantees and retain existing household authorization. Exact database structure and request names remain implementation choices.

## Testing Decisions

The user confirmed this approach: test primarily through the existing HouseholdStore workflow seam with InMemoryHouseholdBackend, supplemented by focused backend contract/database checks and a small simulator UI check.

- **Good tests:** Exercise externally observable proposal contents, allowed actions, persisted planned meals, grocery state, and save outcomes through the workflow interface. Avoid assertions on private ranking helpers, exact weights, view structure, internal task counts, or an arbitrary exact randomly selected week. Control dates/calendar and randomness when needed for reproducibility; assert eligibility, preserved choices, and preference/variation behavior across controlled fixtures.
- **Primary modules:** Cover the auto-planning workflow integrated with HouseholdStore and its temporary proposal state. Use the existing HouseholdBackend seam and in-memory adapter to seed household data, pause operations, inject failures, and deliver changes. Prefer this one high-level workflow surface over separate mock interfaces for every operation.
- **Calendar coverage:** Verify supported week starts, next-week default, current-week eligibility, today/past-day filtering, date-boundary behavior including daylight-saving transitions, selected/deselected days, and unavailable days containing either recipes or notes.
- **Selection coverage:** Verify category/access eligibility, favorites/ratings/recency preferences, eligibility without reviews, distinct automatic dinners, the inclusive nearby-plan exclusion window, small/empty pools, manual overrides, and controlled generation/shuffle variability when alternatives exist.
- **Adjustment coverage:** Verify recipe-default/fallback servings, individual edits, servings after swaps, automatic and manual swaps, Keep toggling and automatic Keep after manual edits, removed-day preservation, and shuffle preservation of kept dinners. Verify unavailable alternatives produce an understandable outcome.
- **Save/lifecycle coverage:** Verify no writes before confirmation, ordinary saved-meal versions/servings, unchanged groceries, explicit discard behavior, household-change invalidation, stale async results, occupied-day skips, changed/unavailable recipes, partial failure, acknowledged success, lost acknowledgement, and duplicate-free retries.
- **Backend contract checks:** Extend existing HouseholdBackend production-adapter contract tests to verify the guarded-save request and actionable response semantics. Exercise authoritative concurrent saves against the real database with ordinary member sessions: occupancy from meals and notes, recipe changes between review and save, membership changes, and lost-response retries. The in-memory adapter cannot establish database concurrency correctness.
- **Prior art:** HouseholdStoreWorkflowTests already uses InMemoryHouseholdBackend operation gates, injected failures, membership changes, planned-meal version assertions, and duplicate-safe finished-cook recovery. SupabaseHouseholdBackendContractTests checks outgoing requests with a controlled HTTP transport. Existing household-move backend tests exercise signed-in members and planned-meal versions. RecipeStatsTests and CookedHistoryTests cover the statistics used as input; GroceryImportReviewTests covers saved-version ingredient review and repeated-meal behavior. Reuse their fixture/harness patterns rather than duplicating existing tests unchanged.
- **UI verification:** Add a focused simulator flow through Auto plan, week/day selection, proposal adjustment, Keep/shuffle, and Add to plan. Check shortage/conflict messaging and the resulting Meal plan screen. Use behavior assertions for controls and state, screenshots for visuals, and verify usable labels and layout with accessibility settings. Keep exhaustive rule coverage at the workflow seam.
- **Implementation completion:** Run relevant workflow, backend, and UI checks. Follow repository requirements to format/lint before sequential simulator and physical-device builds and relaunches, and inspect affected simulator screens with available device tooling. Report physical-device deployment failures accurately. This specification-only task does not require app builds.

## Out of Scope

- Discovering/importing new recipes or generating recipe content.
- Automatically planning breakfast, lunch, snacks, or desserts; adding meal slots to the plan.
- Dietary/allergy, nutrition, cost, pantry, ingredient-overlap, or prep-time optimization and new controls for them.
- Automatic repetition, automatic leftovers/eating-out notes, or overriding occupied days.
- A common serving count for the week, household-size modeling, or a new auto-planning serving preference.
- Automatic grocery additions or changes to grocery merging/repeated-meal import semantics.
- Persisting proposals across launches, sharing proposals between members, or recurring/scheduled auto planning.
- Changes to recipe ownership, household membership rules, or existing manual planning capabilities.
- Committing to a particular ranking formula, database schema, or new backend technology before implementation.

## Further Notes

- This specification synthesizes the settled design interview, including the correction that dinners use each recipe's default servings rather than a common weekly count. The testing approach was separately confirmed.
- Respect the existing personal/household recipe-ownership and household onboarding/ownership ADRs: plans belong to households, all members may edit them, personal recipes survive household changes, and planned meals preserve saved recipe versions and serving counts.
- Current manual meal suggestions are limited to three favorites/highly rated recipes and use strict exclusions. Auto planning must not inherit that restricted pool unchanged.
- Publish this specification as a GitHub issue in OwenVey/calendish-ios with ready-for-agent. Implementation is a subsequent task.
