# Calendish feature audit

Reviewed October 7, 2026. Scope: current SwiftUI views, models, persistence and synchronization, recipe importer, and database schema. This is a code-based product audit; the device service failed to initialize and could not open an iOS simulator. Runtime accessibility, visual quality, and multi-device behavior were not verified. No app code was changed.

## Summary

Calendish has a good foundation for a household utility: save recipes, decide what to cook, shop, and follow instructions. Its strongest direction is completing that everyday loop with dependable quantities and less repeated work. Feature completeness needs work around shopping semantics and connectivity. The priorities below are product judgments based on the implementation, not measured user research or estimates of market demand.

The README understates the existing product. URL import, password reset, recipe deletion, adding recipe ingredients to groceries, and individual grocery editing/deletion already exist. Recipe drafts and cooking timers also persist locally. Preserve these capabilities rather than treating them as new roadmap work.

Effort labels are relative: Small is a focused flow change; Medium spans several screens or a contained schema change; Large changes core data or synchronization behavior. They are not delivery commitments.

## Recommended improvements

### 1. High — Make planned grocery quantities trustworthy

**Evidence:** `MealPlanView.swift:181` constructs one grocery candidate per recipe and uses the maximum planned servings. Two separately cooked four-serving dinners therefore produce ingredients for four servings, not eight. `GroceryImportReviewView.swift:55` blocks a recipe if any grocery row has a matching source title, including completed rows. A recipe rename can bypass the check, and two recipes with identical titles can block each other.

**Proposal:** Choose the shopping date range and meal occurrences first. Sum servings for separate cooking occasions, and explicitly mark leftovers as consuming an earlier batch. Track stable recipe and meal/batch IDs on imported groceries. Offer “add again” and “update quantities” deliberately instead of deciding solely from recipe titles. Completed purchases from an earlier trip must not prevent a fresh shopping list.

**Success check:** Planning the same four-serving recipe twice yields eight servings when both meals are new batches; marking the second as leftovers avoids double counting. Renaming a recipe and retaining completed groceries do not break reordering.

**Effort:** Medium–Large. Do before automatic meal planning or pantry automation.

### 2. High — Carry serving sizes through planning, shopping, and cooking

**Evidence:** `PlannedMeal` stores servings, but the meal-plan navigation passes only a `Recipe` to its detail screen. Recipe details and cook mode render the original ingredient strings and original recipe servings. Scaling currently exists only inside grocery import and recognizes a subset of leading numeric quantities.

**Proposal:** Introduce a shared serving-selection and ingredient-scaling model. A two-person planned meal should open a two-serving cooking session without editing the saved recipe. Preserve original ingredient text and flag quantities that cannot be scaled confidently. Keep temperatures and cooking times unchanged. Support common fractions and ranges; unit conversion can follow later.

**Success check:** The selected yield agrees in meal details, cooking ingredients, and grocery review. An unrecognized quantity remains readable and is explicitly marked for review rather than silently appearing scaled.

**Effort:** Medium–Large; shares foundational work with priority 1.

### 3. High — Add offline shopping and recoverable saves

**Evidence:** `HouseholdStore.swift:417` runs writes in background tasks; failure displays an error and refetches. The household lists have no durable local store or queued mutations. Recipe editor drafts are an existing, narrower protection. `loadHousehold()` routes a failed household load to household setup, which can make a connectivity failure look like missing membership.

**Proposal:** Persist the last household snapshot and pending operations. Allow grocery checkoffs, additions, and existing recipe viewing offline. Show concise saved/pending/retry status, preserve failed work, and distinguish “could not load household” from “no household.” Define conflict handling for simultaneous edits before enabling offline recipe editing.

**Success check:** In airplane mode, restart the app, open the saved list, check off items, reconnect, and see those changes synchronize once without losing another member’s changes.

**Effort:** Large. Especially valuable for shopping in unreliable reception.

### 4. High — Support how households actually plan meals

**Evidence:** `Models.swift:43` requires every planned meal to reference a recipe. The schema permits one recipe per breakfast/lunch/dinner slot. `MealPlanView` shows one selected day and requires choosing a saved recipe.

**Proposal:** Add simple entries such as “Leftovers,” “Eating out,” and free-text meals. Support a main and sides within one meal. Provide a compact week overview, copy-last-week action, and reusable weekly templates. Start with free-text meals and copying; recurrence and leftovers accounting need more design.

**Success check:** A household can plan a week including takeout, a main plus salad, and leftovers without inventing fake recipes or repeatedly opening each day.

**Effort:** Medium for initial free-text/copy flows; Large for multiple dishes and batch-linked leftovers. Schema changes are required.

### 5. Medium — Turn grocery review into an editable shopping decision

**Evidence:** `GroceryImportReviewView` selects whole recipes and renders ingredient lines as read-only text. `GroceryListView` groups by recipe or not at all. Imported ingredients become full-text names with empty amount fields, so matching ingredients from different recipes remain separate.

**Proposal:** Let people uncheck “already have” ingredients, adjust amounts before adding, and select a custom shopping range. Offer aisle/category grouping and suggest merging confidently matched ingredients while retaining recipe attribution. Begin with ingredient selection and manual grouping; a full pantry inventory adds substantial upkeep and can wait.

**Success check:** Exclude salt and oil, combine compatible lemon quantities from two dishes, and shop produce together without editing the list item by item afterward. Ambiguous units remain separate.

**Effort:** Medium for selection/grouping; Large for reliable quantity merging.

### 6. Medium — Make recipe capture and reuse faster

**Evidence:** URL import currently starts by pasting a link into an in-app form. Imported results already open in an editable recipe form. The importer falls back to page metadata when structured recipe content is unavailable. There is no recipe share extension, duplicate-source check, or recipe export flow in the reviewed app.

**Proposal:** Add “Save to Calendish” from the iOS share sheet, detect an already-saved source URL, and clearly identify incomplete imports. Allow pasting a block of ingredients/instructions. Follow with recipe text sharing and portable export; scanning a printed recipe is a later enhancement.

**Success check:** Save a recipe from Safari into the existing review screen, reopen a duplicate instead of adding it accidentally, and understand which imported fields still need attention.

**Effort:** Medium. Retain review-before-save and source attribution.

### 7. Medium — Make cook mode resumable and personally useful

**Evidence:** `CookModeView.swift:11` initializes the step to zero. Ingredient checks live in recipe-detail state. Timers already persist and schedule background notifications, but their duration comes from the first recognized duration in a step. “Finish” dismisses the screen without recording a cooking event.

**Proposal:** Resume the current step and ingredient progress after leaving the screen. Offer editable/custom timers and “add one minute.” Record an optional cooked date and personal note such as “use less lemon next time.” Later use that history for “cook again” suggestions and a today widget.

**Success check:** Leave midway through cooking and return to the same step; set a timer for a step without a parseable duration; retain a note without changing the recipe instructions.

**Effort:** Medium. A widget or Live Activity is a subsequent enhancement, not a prerequisite.

### 8. Medium — Add undo and recovery for shared changes

**Evidence:** Grocery deletion and clearing have no undo. Recipe deletion also removes planned meals and explicitly says it cannot be undone. Meal replacement deletes previous rows before inserting the replacement in a separate request.

**Proposal:** Add undo for grocery deletion, clearing completed items, and meal moves/replacements. Archive recipes or provide recently deleted recovery. Make meal replacement atomic so a failed insert does not leave the old meal deleted. Any shared undo must restore only the relevant change and preserve later changes by other members.

**Success check:** Recover an accidentally cleared shopping list; undo replacing dinner without overwriting subsequent household edits; simulate an interrupted meal save without losing the original meal.

**Effort:** Medium; shared-history recovery may be Large.

### 9. Medium — Complete household and account management

**Evidence:** Settings expose names, members, invite-code sharing, and sign-out. They do not expose leaving a household, transferring ownership, removing a member, replacing an invite code, exporting data, or deleting an account. Household loading selects the first membership.

**Proposal:** Provide leave-household and owner-transfer flows, owner-controlled membership and invite management, and clear account deletion/export options. Explicitly explain the effect on shared recipes. Add multiple-household switching only if users need it. Sign in with Apple is still a genuine addition, unlike most README roadmap items.

**Success check:** A departing member can leave without deleting the household’s recipes; an owner can transfer control; replaced invitations stop working. Authorization must be enforced server-side.

**Effort:** Medium–Large. This is a product-control recommendation, not an App Store compliance determination.

### 10. Low — Help people choose dinner from an established recipe book

**Evidence:** Recipe search already includes title, summary, category, tags, and ingredients. The meal picker searches only titles. The recipe book has favorites and a single tag filter; its “Recently Updated” option actually receives recipes ordered by creation time.

**Proposal:** Reuse recipe-book search in the meal picker; add time and category filters, remember useful filters, and make the recent-sort label accurate. Cooking history can later support “not cooked recently” and favorites rotation. These deterministic suggestions should precede a broad AI meal planner.

**Success check:** Find a vegetarian dinner under 30 minutes while planning, search by an ingredient, and get a predictable recent order after editing a recipe.

**Effort:** Small–Medium for search/filter consistency; history depends on priority 7.

## What to preserve

- The focused Recipes / Meal Plan / Groceries loop and familiar native controls.
- Explicit review before importing groceries and imported recipe content.
- Live household synchronization, local recipe drafts, and persistent cooking timers with notifications.
- Existing accessibility accommodations: alternate meal-plan layout for accessibility text sizes, labeled controls, grocery accessibility actions, and reduced-motion handling. These are implementation strengths, not proof of a completed runtime accessibility audit.

## Design guidance informing the proposals

These are local reference citations from the apple-design skill, separate from the product judgments above:

- `entering-data.md › Best practices`: “When possible, offer choices instead of requiring text entry.” This supports quick meal types, ingredient selection, and reusable plans.
- `undo-and-redo.md › Best practices`: “Show the results of an undo or redo.” Recovery should restore the affected item visibly and explain the result.
- `searching.md › Best practices`: “Clearly display the current scope of a search.” Consistent planner search should show active filters and searchable content.
- `typography.md › Supporting Dynamic Type`: “Make sure your app’s layout adapts to all font sizes.” Preserve the existing accessibility-specific layouts as new planning and grocery controls are added.

## Suggested implementation order

First address grocery repeat/re-add correctness and serving consistency. In parallel planning terms, scope offline persistence as a foundational project, not a cosmetic error-message change. Then deliver ingredient-level grocery review and simple free-text/copy meal planning. Follow with recipe share-sheet capture, cooking-session continuity, and account-management completion. Add history-based suggestions and system surfaces once the core loop is dependable.

Validate these priorities by watching a household plan a week, shop with poor reception, and cook a scaled recipe. Useful measures are time to plan the week, manual corrections after grocery import, failed saves that require re-entry, and successful return to an interrupted cooking session. No analytics collection was added by this audit.
