# Calendish user walkthrough — October 12, 2026

## Summary

Overall: **Good**, with friction around recipe-detail hierarchy and action discoverability. The app's strongest experience is the journey from importing a recipe to choosing scaled groceries and reading one cooking step at a time. The dark interface, green actions, recipe imagery, and consistent cards give it a coherent identity.

Tested the installed app using T3 Code device tools and the returned agent-device CLI on the iPhone 18 Pro Max simulator, iOS 27.0. This was an interaction review, not a code review. No implementation changes were made.

## Recipes added and retained

- **Lemon Chickpea Salad:** manual entry; two ingredients and one instruction; saved successfully.
- **Cold Sesame Noodles:** imported from [Budget Bytes](https://www.budgetbytes.com/cold-sesame-noodles/); review populated photo, four servings, eight-minute prep, twelve-minute cook, ingredients, and instructions; saved successfully.
- **Peanut Butter Banana Toast:** entered recipe text in the text-import screen; preserved three ingredients, two steps, two servings, and five-minute prep; saved successfully.
- **Cinnamon Yogurt Bowl:** imported a generated, plain recipe-card image through the system photo picker; preserved four ingredients, three steps, one serving, and five-minute prep; saved successfully. The source image was added to the simulator photo library as a test fixture.

Recipe count increased from 13 to 17. The recipes were created in the existing signed-in household context; the detail screen describes new recipes as shared with the household.

## Other verified behavior

- Recipe search for “banana” located the toast recipe.
- Planned the toast recipe for today, October 12. Verified its card alongside the existing taco meal in Meal plan.
- Opened that planned meal and added groceries. Increased grocery servings from two to three; bread changed to three slices, peanut butter to three tablespoons, banana to 1½. Deselected banana and added the remaining two items.
- Verified bread and peanut butter in grocery search. Checked and then unchecked peanut butter; ultimately verified both were available to buy. Grocery list ended at 46 items left.
- Opened cooking mode and advanced from step one to step two. Closed without finishing; verified “No cooking recorded” remained.
- Camera scanning opened the system document scanner. Camera permission was allowed in the simulator, but capture reported “Unable to capture media.” This is a simulator limitation, not evidence of a physical-device defect.
- Choose file opened the system Files picker. Recents was empty; cancelled. File parsing was not tested.

## Improvements

### High — Recipe content is too far down the detail screen

**Observed:** For the toast recipe, a large empty photo placeholder, title, description, metadata, and the complete Notes and ratings section precede ingredients. On the large simulator screen, actual ingredient rows begin below the first viewport.

**Impact:** Someone opening a recipe to cook or check purchases must scroll past secondary information.

**Suggestion:** Collapse the missing-photo area to a compact Add photo control. Put ingredients and instructions before notes, ratings, and cooking history. Keep the full hero for recipes with a photo.

**Basis:** Product judgment, supported by `layout.md › Best practices`: “Use progressive disclosure to make layouts cleaner and easier to interact with.”

### Medium — Planning and grocery actions are hidden

**Observed:** Plan a meal and Add to groceries are in More recipe actions. Cook is prominent, but uses only a frying-pan icon onscreen.

**Impact:** A new user must explore an ellipsis to discover two central uses of their recipe library. The frying-pan icon also requires interpretation.

**Suggestion:** Add a compact labeled action row for Cook, Plan, and Groceries near recipe metadata. Reserve More for sharing, privacy, favorites, and deletion.

**Basis:** Product judgment.

### Medium — Website-specific clutter survives import

**Observed:** Budget Bytes ingredient strings retained prices and footnote markers, for example spaghetti's “$0.49*” and sesame oil's “$0.64***”.

**Impact:** Review fields become longer, and site annotations distract from cooking quantities. Downstream grocery behavior for these particular annotations was not tested.

**Suggestion:** Strip clearly identified pricing and footnote annotations while preserving preparation notes, quantities, and units. Preserve a source link for the original context.

**Basis:** Product judgment; distinguish metadata from recipe content.

### Medium — Grocery search hides the reason for some matches

**Observed:** Searching “peanut” returned both peanut butter and whole wheat bread. Bread belongs to Peanut Butter Banana Toast, but the filtered bread row showed no source-recipe explanation.

**Impact:** The result can look like an incorrect ingredient match.

**Suggestion:** When an item matches through its recipe rather than its own name, show “For Peanut Butter Banana Toast” under it, or clearly separate recipe matches from item matches.

**Basis:** Product judgment; `layout.md › Best practices`: “Group related items to clearly express related information or functions.”

### Medium — Returning from an action gives little durable confirmation

**Observed:** Saving a planned meal and adding groceries returned to recipe details. Subsequent navigation verified success, but there was no persistent indication on that detail screen of the day planned or ingredients added. A brief toast could have occurred between snapshots; this review cannot rule it out.

**Suggestion:** Offer unobtrusive confirmation such as “Planned for Monday · View” and “2 ingredients added · View groceries.”

**Basis:** `feedback.md › Best practices`: “Consider integrating status feedback into your interface.”

### Accessibility follow-up — Form controls need inspection

**Observed:** Empty title and ingredient fields exposed no descriptive label; prep/cook controls appeared as unnamed buttons. Empty instruction and recipe-text editors were not exposed as editable fields in the initial CLI snapshot, although tapping and typing worked. Instruction text appeared as an editable field after entry. Some remove controls appeared as images rather than named buttons. The cooking ingredients sheet was visually present but its ingredient controls were absent from the captured UI tree.

**Suggestion:** Check these controls in Accessibility Inspector and VoiceOver. Add stable names such as Recipe title, Ingredient 1, Instruction 1, Set prep time, and Remove ingredient 1; verify sheet focus and checkbox state announcements.

**Limit:** These are automation-tree observations, not confirmed VoiceOver failures. The tool sometimes used different accessibility backends. Do not classify them as confirmed critical defects until reproduced with assistive technology.

**Basis:** `accessibility.md › Vision`: “Describe your app’s interface and content for VoiceOver.”

## What works

- The six-route New recipe menu is clear and groups manual, text/link, and media entry sensibly.
- Import review provides control before saving and extracted the tested text/photo recipes accurately.
- Meal plan day cards make multiple meals and today's location easy to scan.
- Grocery selection supports excluding ingredients, scaling servings, and resetting to the original amount.
- Cooking mode has readable instructions, large navigation controls, a visible step count, and a useful current-step ingredient panel.
- Most top-level and recipe actions expose meaningful accessibility names even when their visual representation is an icon.

## Limits

No physical-device camera test, file-parser test, social-link import, Safari share-extension test, voice-command test, offline/error-recovery test, Dynamic Type audit, contrast measurement, or light-mode review was performed. No source code changed, so build/deployment scripts were not run.
