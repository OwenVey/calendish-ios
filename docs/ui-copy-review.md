# Calendish UI copy review

Reviewed October 9, 2026 against the current source using the writing-for-interfaces skill and its pattern reference.

## Assessment and scope

The copy generally explains the everyday recipe → plan → shop → cook flow well. The voice is warm, practical, and restrained. Most actions use clear verbs, and the household move and recipe deletion flows already explain unusually complex consequences. Preserve that foundation.

Clarity is strongest in ordinary actions and weakest when the app reports state: what has actually been saved, whether something was cooked, what “On List” means, and what happened after a failed request. Purpose is usually clear, but setup, import, and empty states sometimes omit the next step. Consistency needs a shared vocabulary and capitalization rule.

This is a source-based review of all app-owned interface text found in the main app, share extension, cooking Live Activity, App Intent metadata, permission descriptions, and supporting models that produce visible or spoken text. It includes dynamic strings and accessibility labels/hints. Repeated strings are grouped below. Recipe content, member names, imported text, model prompts, internal identifiers, developer scripts, and documentation are not interface-copy rewrite targets. Apple- and Google-owned picker/dialog text is outside the app's copy control.

The initial review changed no app code. Recommendations that require new state or actions are explicitly identified. See the implementation notes below for the subsequent changes. Existing skill installation changes were left alone.

## Implementation notes

Applied the wording and consistency recommendations, including state-aware household deletion consequences, safe operation-specific error messages, partial-import review guidance, persistent share-extension completion, repeat-meal disclosure, source-aware cooking history, singular forms, and accessible action/loading labels. The adopted voice and vocabulary are in `docs/ui-copy-style.md`.

Weekly quantities and cooking-history inclusion rules remain unchanged: repeated identical versions still use the largest single-meal serving count, and past plans still contribute to history. The interface now describes both accurately. No new pantry matching, occurrence-aware shopping model, offline queue, privacy-choice flow, or localization system was introduced. These were broader product options in the review, rather than prerequisites for truthful copy. Error messages provide safe recovery by operation and distinguish network failures; further service-specific classification remains possible without exposing raw diagnostics.

Verification: cooking-history, grocery-import-review, recipe-import, recipe-stats, household workflow, and hands-free cooking workflow checks passed. Three focused household UI checks and both partial-import UI checks passed. The instructions-only UI check was updated to scroll to the field after the new review guidance pushed it below the fold. The final simulator build and relaunch succeeded, followed by a successful build, installation, and relaunch on Owen’s iPhone. T3 Device panel support failed to initialize; simulator verification used repository scripts and screenshots. VoiceOver speech and every Dynamic Type/layout combination were not manually tested.

## Proposed voice

No documented voice guide was found. The following is inferred from “Plan meals and shop together,” “Save something you love to cook,” and the direct action labels:

- **Welcoming:** invite people into a useful household routine without cheerleading.
- **Practical:** name the thing and the next action in familiar cooking and shopping language.
- **Calm:** explain failures and irreversible consequences without jokes or alarm.
- **Brief:** keep mid-task copy short; allow more detail when sharing or deleting data.

Use sentence case for app-owned labels, buttons, titles, and sentences. Preserve product names such as Calendish, Google, Live Activity, Lock Screen, and Dynamic Island. Warmth belongs in welcome and completion moments; errors and ownership decisions need directness. Keep “Enjoy your meal!” as a rare celebratory exception. Persist this proposed voice and the word list below in a dedicated copy guide when adopted.

## High priority: correct misleading state and consequences

### H1. Grocery review describes the initial choice as the current choice

Source: `calendish-ios/Features/Groceries/GroceryImportReviewView.swift:90`, `calendish-ios/Features/Groceries/GroceryImportReview.swift:74`.

- Original: “These ingredients are already on your grocery list, so none are selected.” / “Ingredients already on your grocery list aren’t selected.”
- Rewrite: “Matching ingredients start unselected. Select them to add more.”
- Original badge: “On List”.
- Rewrite badge: “On list”; supporting explanation: “Matches an unchecked item for this recipe. Quantities may differ.”

The person can select these lines, and later grocery updates do not override their choices. The footer currently remains false after selection. The match also ignores quantity and requires the same recipe title, so it does not establish that the full amount is already on the list. The revised wording explains the initial behavior and avoids a quantity promise. Ideally show the matching quantity where needed; that requires UI work.

### H2. The recipe editor gives contradictory requirements

Source: `calendish-ios/RecipeViews.swift:613`, `:659`, `:686`; `calendish-ios/Features/Recipes/RecipeDraftEditing.swift:72`.

- Keep: “To save, add a title and at least one ingredient or instruction.”
- Original ingredients footer: “At least one entry is required. Drag the handles to reorder.”
- Rewrite: “Add ingredients here. Drag the handles to reorder.”
- Original instructions footer: the same “At least one entry is required…” sentence.
- Rewrite: “Add cooking steps here. Drag the handles to reorder.”

Saving requires either ingredients or instructions, not an entry in both sections. State the rule once and use the section footers only for section-specific guidance.

### H3. The share extension implies the recipe is already saved

Source: `ShareExtension/ShareViewController.swift:67`.

- Original progress: “Saving to Calendish…” → “Sending to Calendish…”
- Original success: “Saved to Calendish” → “Ready to import”
- Keep body: “Open Calendish to review and save the recipe.”
- Original failure: “Couldn’t Save to Calendish” → “Couldn’t send to Calendish”
- Original failure body: “Try sharing a link, text, photos, or a PDF.”
- Rewrite for unsupported content: “Share a recipe link, recipe text, photos, or a PDF.”
- Rewrite for an inbox/storage failure: “Open Calendish and try importing the recipe there.”

The extension saves source material to a local inbox; the recipe is not yet in the collection. Failure copy must distinguish unsupported content from a storage failure. That distinction requires preserving the error category rather than collapsing all failures into one state.

### H4. Deletion failures assert an outcome the request may not establish

Source: `calendish-ios/Features/Settings/SettingsView.swift:234`, `:380`.

- Original: “Your account wasn’t deleted. [raw error]”
- Rewrite for an unconfirmed response: “Couldn’t confirm account deletion. Check your account before trying again.”
- Original: “Nothing was deleted. [raw error]”
- Rewrite for an unconfirmed response: “Couldn’t confirm deletion. Check the household data before trying again.”

A server rejection can support a definite failure message; a lost response cannot. Use “Your account wasn’t deleted” or “Nothing was deleted” only when the app has confirmed that outcome. Classify the failure and reconcile state before presenting a retry. This is a state-handling change as well as a copy change.

### H5. Account deletion has conflicting explanations for the last member

Source: `calendish-ios/Features/Settings/SettingsView.swift:216`, `:227`.

- Original persistent footer: “Permanently deletes your account and personal recipes. Your household keeps the recipes you shared with it.”
- Rewrite for multiple members: keep the existing footer.
- Rewrite for the last member: “Permanently deletes your account, personal recipes, and household, including its recipes, meal plan, and groceries.”

The confirmation already switches to the last-member consequence, but the footer always promises retention. Use the same membership-dependent consequence before and inside the confirmation. In the last-member alert, explicitly name personal recipes too. Keep “This can’t be undone.”

### H6. Raw errors and a generic sync title hide what failed

Source: `calendish-ios/App/ContentView.swift:94`; `calendish-ios/Data/HouseholdStore.swift:828`; raw-error displays in account, import, household move, and photo views.

- Original: title “Couldn’t sync”; body `error.localizedDescription`; button “OK”.
- Recommended pattern: operation-specific title + verified state + available next action.
- Recipe save example: “Couldn’t confirm the save” / “Your draft is still on this iPhone. Reopen the editor to try again.” Only use this when the matching draft is retained.
- Grocery refresh example: “Couldn’t update groceries” / “Check your connection and reopen the list to try again.”
- Sign-in example for a known credential rejection: “Email or password didn’t match. Check both and try again.”
- Expired invitation example for a known rejection: “This invite code no longer works. Ask a household member for a new invitation.”

Do not replace every error with “Check your connection”: permission, input, and server failures have different remedies. Do not promise pending changes will sync automatically unless that operation is actually queued. Map known error categories to safe, actionable messages and keep technical details in diagnostics. “OK” is acceptable for acknowledgment, but a real recovery action is preferable when supported. Adding Retry, reopening the editor, or reconnect controls requires behavior, not just a new label.

### H7. “Cooked” is presented as a fact when history includes unconfirmed plans

Source: `calendish-ios/Features/Recipes/CookedHistory.swift:39`, `:60`; `calendish-ios/RecipeReviewViews.swift:120`, `:247`; `calendish-ios/Features/MealPlan/MealPlanView.swift:457`; sort labels in `Preferences.swift:46`.

- Original summary: “Last cooked [time]”, “Cooked [count] times”, “Not cooked yet”.
- Source-aware rewrite: “Last marked cooked [time]” for a marked cook; “Last planned [date]” for an unmarked past plan; “No cooking recorded” when there are no marked cooks.
- Original suggestions footer: “Well-liked recipes you haven’t cooked in a while.”
- Rewrite retaining the current combined history: “Well-liked recipes you haven’t marked cooked or planned recently.”
- Original history footer: “Days you mark and past planned meals both count. Remove a planned meal from the meal plan to take it out of the history.”
- Rewrite: “Includes days marked cooked and past planned meals. A past plan doesn’t confirm the meal was cooked. To remove a planned entry, remove it from the meal plan.”

Keep the distinction in every summary, count, sort label, and suggestion. A consistent alternative is to count only marked cooks, which is a product/model change. Do not ship a label-only change that calls the current combined count “recorded cooks.” Counts represent distinct days, not necessarily separate cooking sessions; use “days” when reporting that count.

### H8. Weekly grocery review does not explain repeated-meal quantities

Source: `calendish-ios/Features/Groceries/GroceryImportReview.swift:8`; `calendish-ios/Features/MealPlan/MealPlanView.swift:154`.

- Original: menu “Add to Groceries” → “This Week” / “Next Week”; review shows a serving count with no repeat explanation.
- Add when the same saved recipe version occurs more than once: “Planned more than once. This amount uses the largest serving count for one meal, not the total for the week.”

The review combines identical versions using the largest serving count. Someone shopping for two separate dinners may expect the total. Copy can disclose the current behavior, but occurrence-aware quantities are the stronger solution. The disclosure requires passing repeat information into the review.

## Medium priority: improve choices, recovery, and accessible meaning

| ID / source | Original | Recommendation | Reason |
| --- | --- | --- | --- |
| M1 · `AccountViews.swift:101` | “We’ll sign you in, or help you create an account.” | “Use your email to sign in or create an account.” | Describes the purpose without implying automatic account detection. |
| M2 · `AccountViews.swift:103` | Email field uses only “name@example.com”. | Keep the example; add the persistent/accessible label “Email address”. | An example is not the field’s name. |
| M3 · `AccountViews.swift:361` | “Continue” in household setup. | “Join household” when an invite is pending; “Start household” otherwise. Add “Start with your own household. Invite someone or join another household later.” for the solo branch. | The final setup action should explain the result. “Continue” remains appropriate between email steps. |
| M4 · `AccountViews.swift:342` | Name input silently disables Continue above 80 characters. | Add inline “Use 80 characters or fewer.” when exceeded. | Explain a blocked action at the field. Requires validation state. |
| M5 · `AccountViews.swift:405` | Reset-password action “Save”. | “Save password”; accessible busy state “Saving password”. | Names a sensitive action and its progress. Keep the existing length/matching guidance. |
| M6 · `HouseholdMoveView.swift:24–37` | “Review Household”, “Review Leave”, “Destination”, “A fresh solo household…” | “Review household”, “Review changes”, “Household to join”, “A new household for you, with an empty grocery list and meal plan.” | “Review Leave” is unnatural; destination and solo are less familiar than the actual outcome. Keep the preview-before-confirm promise. |
| M7 · `HouseholdMoveView.swift:48` | “Your existing personal recipes become shared with the destination household. You can set individual recipes to Only me afterward.” | “Joining shares all your existing personal recipes with this household. You can make individual recipes private afterward.” | Put the broad sharing consequence first. Keep prominently next to the final Join action. A privacy choice before joining would require a product change. |
| M8 · `HouseholdMoveView.swift:57` | “Saves [count] household-owned recipes as private personal copies before moving. Other members’ personal originals aren’t included.” | “Saves [1 recipe / count recipes] owned by the household as private copies. Recipes owned by other members aren’t included.” | Fix singular grammar and remove implementation-heavy “personal originals”. |
| M9 · `RecipeViews.swift:476–522` | “Make Only Me”; “Only me stops access to your original and future edits; it doesn’t retract prior sharing.” | Action/title “Make private”; body “Your household keeps a separate copy of this recipe. Only you can access your original and future edits.” | “Only me” works as a visibility value, but not as a verb phrase. Keep the retention consequence explicit. |
| M10 · `RecipeViews.swift:753` | “Only you can see this recipe.” in the new-recipe form. | “This recipe will be private.” Shared state: “Your household will be able to see and cook this recipe. Only you will be able to edit it.” | An unsaved recipe is not yet visible to the household. Existing retained copies need separate explanation where sharing can be changed. |
| M11 · `RecipeViews.swift:134–138` | Recipe empty state has no instruction; favorite state refers to a “More menu”. | “Add a recipe or import one from a link, text, photo, or PDF.” Favorites: “Open a recipe’s actions menu and choose Add to favorites.” | Give the next step and use the menu’s actual purpose. A visible Add recipe action would improve this further. |
| M12 · `RecipeViews.swift:138` | “Try another search or tag.” | “Try another search or change the filters.” | Favorites and collection scope can also exclude results. Clear filters action requires behavior. |
| M13 · `RecipeViews.swift:145` | “Recipes, ingredients, and more”. | “Search recipes and ingredients”. | Names the purpose without a vague “and more”. Current matching also covers description, category, and tags; a compact prompt need not list every field. |
| M14 · `RecipeViews.swift:172–182`, `RecipePhotos.swift:137`, `ProfilePhotos.swift:48` | “Add Manually”, “Choose from Photos”, “Choose from Library”, “Choose File”. | “Write a recipe”, “Choose photos” for import, “Choose a photo” for a single recipe/profile photo, “Choose a file”. | Start with the person’s action and distinguish multi-photo import from single-photo selection. Preserve “Scan with camera” and “Take photo” as different tasks. |
| M15 · `RecipeImportView.swift:46`, `:239`, `RecipeViews.swift:759` | Imported result opens “New Recipe” without review guidance. | Imported editor title “Review recipe”; intro “Check the ingredients, steps, and servings before saving.” If a list is missing, explicitly say “No ingredients were imported” or “No instructions were imported.” | Explain the review stage and partial imports. Preserve “New recipe” for manual creation. Requires retaining import provenance/missing-field state in the editor. |
| M16 · `RecipeLinkImporter.swift:297`, `RecipePDFImporter.swift:64–65`, `RecipeImageImporter.swift:94`, `RecipeImportView.swift:131` | “Couldn’t get a recipe from this link”; “Couldn’t open this PDF”; “Couldn’t find any text…”; “Couldn’t load these photos.” | Link: “Couldn’t find a written recipe at this link. Paste the ingredients or instructions instead.” PDF open: “Couldn’t open this PDF. Choose another file.” No text: “No readable text found. Try a clearer photo or paste the recipe text.” Photo load: “Couldn’t load the photos. Choose them again.” | Each failure needs a relevant next step. Use “photo”/“photos” by count. Keep the existing Edit text recovery when text was recovered. The heading “Couldn’t read recipe” can remain. |
| M17 · `ShareViewController.swift:71` | Success closes automatically after 1.5 seconds. | Keep the review/save instruction visible until Done, or make the app’s next step equally clear elsewhere. | Good copy loses its purpose if the person has insufficient time to read it. Timing change, not a wording fix. |
| M18 · `MealPlanView.swift:249`, `:490` | “Nothing planned — tap to add a recipe”; “Add Recipe” for scheduling. | “Nothing planned yet. Add a recipe or note.” Scheduling title/action “Plan a meal”. Keep “Add note” for flexible entries. | Avoid the dash, acknowledge note support, and distinguish scheduling from creating a recipe. The empty-row tap still adds a recipe; offer both actions if the copy names both. |
| M19 · `MealPlanView.swift:569`, `:579` | “Fend for Yourself”; “Leftovers, dinner out…” | “Everyone cooks separately”; placeholder “Leftovers or eating out”. | Remove the idiom and trailing ellipsis. Match the suggestion “Eating out”. |
| M20 · `MealPlanView.swift:483–484`, `RecipeViews.swift:378`, `:470` | “Keep saved version”; long explanation; “Saved version for this planned meal”; “Update to Latest Recipe”. | Keep “Keep saved version”; footer “Changing the day or servings keeps this meal’s saved recipe. Turn this off to choose a recipe from your collection.” Detail “Recipe version saved with this meal”; update “Use latest recipe version”. | Clarifies what is preserved and which object gets updated. Optional “Replaces this meal’s saved ingredients and instructions” hint makes the update consequence clearer. |
| M21 · `GroceryListView.swift:116`, `:119`, `:182`; `SettingsView.swift:76`; `GroceryListView.swift:329` | “Completed”, “Clear Completed”, “Clear Checked Items”, “Complete [item]”, “Mark [item] as not completed”. | Use “Checked”, “Clear checked items”, “Check off [full item]”, “Uncheck [full item]”; accessibility values “Checked” / “Unchecked”. | Use one state across shopping, settings, and VoiceOver. “Bought” would falsely assume every checkoff is a purchase. Include quantity to distinguish otherwise identical rows. |
| M22 · `GroceryListView.swift:181–193` | Completed-clear dialog omits household-wide consequence; full-clear does include it. | Checked-clear title “Clear checked items?”; body “Removes checked items for everyone in your household.” Action “Clear checked items”. Full-clear action “Clear grocery list”. | Both shared destructive actions need the same scope. Keep the full-clear warning that unchecked items are removed too. |
| M23 · `SettingsView.swift:82`, `Preferences.swift:96–99` | “Checked items are removed…” even with Never selected; “After an Hour/Day/Week”. | Never: “Checked items stay on the list until you clear them.” Otherwise: “Removes items [an hour/a day/a week] after they’re checked off, for everyone in your household.” | State timing relative to the checkoff and describe the selected value. Requires a value-dependent footer. |
| M24 · `SettingsView.swift:60`, `:54`; `Models.swift:73`, `:422` | “Default Servings”, “Units”, “As Written”, “System”. | Keep labels, in sentence case; explain default servings “Used for new recipes when no serving count is given.” Units helper “Converts supported quantities and temperatures. Saved recipe text stays unchanged.” Week option “Regional default”; appearance option “Device setting”. | Defaults and display conversions need their scope. The two “System” options mean different things. |
| M25 · `CookModeView.swift:324`; `CookingActivityWidget.swift:72` | “Finish” records a cook but does not say so. | “Finish cooking”; accessibility hint “Records this recipe as cooked and closes cook mode.” | Finishing changes history, not just navigation. Use the hint only where the recipe can actually be linked to the collection/history. Keep Live Activity labels aligned. |
| M26 · `CookModeView.swift:391` | “This step doesn’t name any ingredients.” | “No matching ingredients found for this step. Choose All ingredients to see the full list.” | Ingredient matching is a heuristic; no match does not prove an instruction names none. |
| M27 · `CookModeView.swift:561`; `SettingsView.swift:512` | “Keep Calendish open to hear your timers” under silent alerts; “Timers show a notification without a sound.” | Permission warning: “Notifications are off. Keep Calendish open to see timer alerts, or allow notifications in Settings.” Silent footer: “Timers show notifications without sound when notifications are allowed.” | Avoid promising sound in silent mode or notification delivery without permission. |
| M28 · `SettingsView.swift:509–512` | Alarm footer promises ringing without addressing not-yet-granted permission. | Not determined: “Allow alarms so timers can ring even when your iPhone is on silent or in a Focus.” Denied: “Alarms are off. Timers use notifications when allowed.” | Match the existing Allow alarms action. A selected mode is not proof authorization has been granted. Keep the approved-alarm description. |
| M29 · `CookModeView.swift:461`, `ContentView.swift:52` | Timer menu “Cancel”; global menu “Cancel [recipe], Step [n]”. | “Cancel timer”; “Cancel timer: [recipe], step [n]”. | Distinguish canceling a timer from leaving cooking or dismissing the menu. |
| M30 · `Info.plist:5`; project camera usage description | Camera: “Take photos for your profile and recipes.” | “Take profile and recipe photos, or scan printed recipes.” | The camera is also used to scan recipe text. Keep the alarm and microphone descriptions; they explain the benefit and scope clearly. |

## Polish and cross-screen consistency

These are lower priority than truthful state and recovery. Do not rewrite clear copy simply to make it sound different.

| Original / source | Proposed wording or rule | Rationale |
| --- | --- | --- |
| “Continue with Email”, “Sign In”, “Create Account”, “Forgot Password?” (`AccountViews.swift`) | “Continue with email”, “Sign in”, “Create account”, “Forgot password?” | Align with sentence case already used in welcome headings. |
| “Recipe Link”, “Recipe Text”, “Import recipe”, “Add from link”, “Add from text” (`RecipeImportView.swift`) | “Recipe link”, “Recipe text”, “Import recipe”, “Import from link”, “Import from text” | Use Import consistently for extracting a draft; Save for adding the reviewed recipe to the collection. |
| “Add a Note”, “Notes & Ratings”, “Your Note” (`RecipeReviewViews.swift`) | “Add note”, “Notes and ratings”, “Recipe note” | Distinguish recipe notes from meal-plan notes. “Your note” remains useful as an accessibility value for the person's own text. |
| “Mark Cooked”, “Mark as Cooked”, “Mark as Cooked Today” | “Mark cooked today” for the immediate action; “Mark cooked” for a chosen date. | Align visible and accessible actions with their actual date. |
| “1 servings”, “Reset to 1 servings”, “Rated 1 stars” (recipe details, grocery review, cards) | “1 serving”, “Reset to 1 serving”, “Rated 1 star”; plural forms otherwise. | Dynamic copy must read naturally at one. The rating picker and recipe count already handle singular forms well. |
| “[count] Completed”, “All done” (groceries) | “[count] checked”; “List is empty” when there are no items, “All checked off” when items exist and all are checked. | Distinguish an empty list from finishing a shopping list. |
| “All set for now” / “Tap + to start your household list.” | Keep title; body “Add an item to start your household grocery list.” | Retain calm warmth without relying on a symbol-only instruction. |
| “Open Recipes and tap + to add your first dish.” (meal picker) | “Add a recipe in Recipes, then return to plan a meal.” | Names the destination and purpose. A direct action would be better but needs navigation work. |
| “Let’s cook” (recipe detail) | Keep. | Warmth is appropriate beside cooking instructions. No need to flatten it to “Instructions” unless tested scanning shows a problem. |
| “Yield” / example “24 cookies” (recipe editor) | “Makes” / example “24 cookies”. | Uses the same familiar language as recipe details. |
| “Prep: [n] min”, “Cook: [n] min” | Keep compact visible text; accessible wording “Preparation time: [n] minutes”, “Cooking time: [n] minutes”, with singular forms. | Expand abbreviations for speech without lengthening the visual metadata. |
| “Show” / “Hide” (checked section) | Keep visibly; accessibility labels “Show checked items” / “Hide checked items”. | Nearby headings disambiguate visually; speech needs that context. |
| “Grocery Item”; “Edit the grocery item directly” | “Grocery item”; hint “Edit name and quantity”. | Explains what can be changed. The field's current value already supplies its content. |
| “Remove [tag]”, “Add [tag]” | “Remove tag [tag]”, “Add tag [tag]” as accessibility labels. | Makes arbitrary tag names intelligible in isolation. |
| “Timer Done” in app, notification, banner; spoken “timer done” | “Timer finished” throughout; body “[recipe], step [n]: [duration] timer finished.” | One consistent state label. Current “timer is up” is understandable but less neutral for localization. Retain recipe, step, and duration. |
| “Stop Voice Commands”, “Turn Off Voice Commands”, “Stop” | “Turn off voice commands” for toolbar/close accessibility labels; “Turn off” in the status panel. | One name for the same persistent action. Keep “Resume” for paused state and “Retry” for failures. |
| Voice introduction button “Turn On”; permission button “Settings” | “Turn on voice commands”; “Open Settings”. | Clarifies the action from the button alone. Keep the nearby-audio warning. |
| “Live Activities are off. You can enable them for Calendish in Settings.” | “Live Activities are off. Allow them for Calendish in the Settings app.” | Distinguish system Settings from Calendish's Settings tab. Keep “You can keep cooking here” for activity-creation failures. |
| “No timer on this step” (spoken feedback) | “This step has no timer.” | Natural spoken phrasing. Keep “First step”, “Last step”, and “Timer already running”. |
| “By You” / “By Household” (recipe rows) | “Added by you” for own originals; “Owned by the household” for household recipes; “[name]’s recipe” for another person's original. | These labels identify ownership, not necessarily authorship of an imported recipe. In detail, keep the clear visibility suffix. |
| “Send Feedback” opens GitHub Issues | “Report an issue”; helper “Opens GitHub. A GitHub account may be needed.” | Sets expectations about destination and the supported feedback mechanism without promising an in-app contact form. |

## Accessibility and loading copy

Existing strengths: rating values handle one star correctly; adjustable rating controls are modeled as one accessible element; photo positioning has named movement actions; recipe and grocery selectors expose state; household action menus name the member; calendar headers include full dates; Live Activity progress says “Step [n] of [total]”. Preserve these.

Items to address or verify:

- `AccountViews.swift:33`, `:299`, `:361`: loading spinners replace or obscure action text. Explicitly expose “Signing in”, “Creating account”, or “Starting household” as appropriate. Verify the accessible name survives `.opacity(0)` before treating it as missing.
- `ContentView.swift` loading screen / `Components.swift` `LoadingView`: provide “Loading Calendish” for the startup spinner. Recipe import already uses useful stage-specific progress text.
- `GroceryImportReviewView.swift:58`: use an accessible label such as “[ingredient]. Already on list” and hint “Select to add more” when applicable. Selected traits can continue carrying selection state; don't redundantly append “button”.
- `CookModeView.swift:391`: describe the result of matching, not an absolute claim about the instruction. Use the M26 rewrite.
- `RecipeReviewViews.swift:89`: “Adds a personal tweak…” can imply privacy. Prefer “Add a cooking note. Household members can see notes on recipes they can access.” The note footer should also cover household-owned and other members' shared recipes, not only “recipes you share”.
- `CookModeView.swift:465`: verify duration abbreviations are spoken naturally; if needed expose “Start a [duration in full words] timer”.
- `CookingActivityShared/CookingActivityAttributes.swift:25`: “Next cooking step” can finish cooking on the last step. Verify where the fixed intent title is surfaced; visible Live Activity controls already switch to Finish. Keep parameter labels “Session” and “Step” unless the internal session identifier is exposed to people.

These are source observations and verification targets, not a claim that VoiceOver currently fails on a device.

## Coverage and copy to retain

| Surface reviewed | Evaluation |
| --- | --- |
| Main tabs and navigation | Recipes, Meal Plan, Groceries, Settings are clear destinations. Normalize Meal plan to sentence case. |
| Welcome feature rows and privacy sentence | Short benefit-led structure works. Keep “Plan meals and shop together” and household-members-only wording; this review does not independently certify the privacy claim. “Live grocery list” can become “Shared grocery list” to describe the enduring benefit. |
| Email, password, account creation, reset notices | Clear step headings and useful email-confirmation/reset instructions. Keep them. Improve field labels, error mapping, and setup completion action as above. |
| Household setup and pending invitations | Good name-purpose footer and invitation context. Name what Continue does, disclose solo household creation, explain invalid-length blocking. |
| Household join/leave preview | Strong separation of what follows/stays, ownership transfer, and last-member deletion. Simplify terminology without removing consequences. Preserve “Nothing changes until you confirm.” |
| Profile, members, invitation sharing/copying | Clear actions, name field explanation, and copied-code accessibility value. “Join my household on Calendish… Invite code…” is useful share text. |
| Delete account, household data, remove member, transfer owner | Most scope/consequences are explicit. Fix the last-member footer and unconfirmed-error assertions. Rename generic “Remove” action to “Remove member”; ownership title can name the recipient: “Make [name] the owner?” Keep Cancel. |
| Recipe list, collection scopes, category/tag filters, sorting | Clear core vocabulary. All / Mine / Household are concise and supported by ownership labels. Preserve category names, List/Grid, favorites actions, and explicit Delete recipe. Address empty states, ownership attribution, and history-based sorts. |
| Recipe details, metadata, ingredient checks, source/copy/share actions | Good division between reading, planning, shopping, and cooking. Keep Visit source, Save to my collection, Ingredients, and ingredient Checked/Unchecked values. Fix sharing language, pluralization, and version action scope. |
| Recipe editor, durations, tags, source/yield, photos, drafts | Keep title + either list save rule, draft-retention message, Cancel / Discard changes / Keep editing, source-link example, tag guidance, duration units, and reordering guidance. Remove contradictory per-section requirements. |
| Link/text/photo/PDF import and share inbox | Progress labels identify what is being read. Text import error already explains that ingredients or instructions are needed. Explain draft review, partial imports, recoverable failures, and pending share material. |
| Recipe notes, ratings, cooked history | Clear rating mechanics and editable personal review. “Personal” must describe authorship without implying privacy. Separate marked cooks from historical plans. |
| Meal plan, day actions, loading earlier weeks, recipe picker | Today / This week / Next week and Pull/Release to load previous week serve their purpose. Keep recipe-selection status and date labels. Clarify Plan a meal, suggestions, saved versions, and repeated-meal grocery amounts. |
| Meal-plan notes and optional groceries | Useful flexibility and good “Included when you add this day’s meals…” explanation. Keep Add item, Remove note, and discard choices. Replace idiomatic suggestion/placeholder. |
| Grocery list, search/add, aisle/recipe grouping, inline edits | “Search or add an item” and “Add ‘[query]’” accurately explain the combined action. Aisle/category labels are understandable. Preserve remaining-count singular/plural handling. Align checked terminology and destructive scope. |
| Grocery import review, select-all, servings reset | Clear selection affordances and “[selected] of [total] selected”. Keep Select all / Deselect all, Cancel, and Reset. Correct matching claims; use “Add selected ingredients” as the accessible action because selected lines can merge into fewer grocery rows. |
| Cook mode, step chooser, ingredients, running timers | Step numbering, Next/Previous, scope menu, and named timer start actions are useful and concise. Explain finishing and fix heuristic no-match wording. |
| Voice commands, listening, pause, retry, denial/unavailable | Strong explanation of commands, on-device processing, listening scope, and incidental triggers. Keep permission/unavailable recovery with manual buttons. English-only accepted commands should be communicated if localization is added. |
| Timer alerts, local notifications, system alarms | Recipe + step + duration makes alerts specific. Normalize finished/cancel vocabulary and avoid permission/sound promises under silent or denied modes. |
| Live Activity and Dynamic Island | Short Cooking / Step / Finished labels fit the surface. Keep Next-step / Start-timer accessibility labels; align Finish cooking and timer wording with the app. |
| Settings: appearance, week, units, servings, cooking, groceries, about | Most names are scannable. Keep screen-awake, ingredient visibility, haptics, and approved alarm descriptions. Clarify defaults, permission-dependent descriptions, auto-clear timing, and feedback destination. Hidden App Store/privacy/terms link labels are clear and can remain when configured. |
| Profile-photo selection/crop and recipe-photo menus | Movement, zoom, Use photo, Cancel, Take photo, Paste photo, and Remove photo have clear purposes. Unify library-selection wording and map raw failures to helpful messages. |
| Permissions and system-visible metadata | Alarm and microphone explanations name benefits and privacy scope. Camera needs scanning use. Exported “Calendish Planned Meal” type name is clear. Intent names are concise; verify the final-step semantics noted above. |

## Proposed word list

| Use | Avoid / distinguish | Meaning |
| --- | --- | --- |
| Household | Family, group, destination | People sharing a meal plan and grocery list. “Household to join” identifies a move target. |
| Personal recipe | Personal original in ordinary UI | A recipe owned by a person. It may be private or shared. |
| Private / Only me | Make Only Me | Private is the action/adjective; Only me is a visibility value. Previously shared copies can remain elsewhere. |
| Shared with household | Public | Household members can access a person's recipe; it is not publicly published. |
| Recipe owned by the household | Household-owned personal original | A recipe independent of an individual member's collection. “Household recipe” is fine after the distinction is explained. |
| Separate copy | Independent household copy in routine copy | A retained recipe whose future edits do not follow the original. Use “independent” only if needed to emphasize that distinction. |
| Collection / My collection | Alternating collection, library, and book in actions | Saved recipes belonging to the person. “Recipe book” can remain in welcome/empty-state voice. “Library” should refer to the system photo library only. |
| Plan a meal | Add recipe when scheduling | Put a saved recipe on a date; writing/saving a recipe is a separate action. |
| Saved recipe version | Snapshot | Ingredients and steps captured with a planned meal. |
| Recipe note / Meal-plan note | Personal note implying privacy | The first is a member's cooking review; the second is a dated planning entry. |
| Checked / Unchecked | Completed, bought, done for grocery state | Checklist state. Use Check off / Uncheck as actions. |
| On list | Already have / Enough on list | A matching unchecked ingredient associated with the recipe; does not verify the needed quantity or pantry stock. |
| Import | Save for the extraction stage | Read outside content into a draft. |
| Save recipe | Saved to Calendish before review | Persist a reviewed draft into the recipe collection. |
| Voice commands | Siri mode, voice assistant | The optional command feature in cook mode. “Hands-free cook mode” remains the domain-level feature name. |
| Mark cooked | Mark completed | Record that cooking happened on a date. Planned meals must remain distinguishable. |
| Timer finished / Cancel timer | Timer Done / ambiguous Cancel | Timer state and action, consistently across app, speech, and system surfaces. |
| Continue / Save / Done | One generic label for every stage | Continue advances setup; Save commits edits; Done closes a completed or informational view. Use a specific final action when its consequence needs naming. |

## Verification before implementation is considered complete

1. Read every revised flow as title → body → actions and confirm the actions exist and match the stated result.
2. Check the troublesome states: select an On list ingredient; grocery list updates while review stays open; repeated weekly recipes; ingredient-only and instruction-only saves; private/shared/retained copies; last-member account deletion; lost deletion responses; marked versus planned history; silent timers with denied notifications.
3. Substitute one serving, one household recipe, one star, zero selections, many merged ingredients, long recipe/member names, and long invite/share text. Do not call selected lines “items added” when merging changes the row count.
4. Verify VoiceOver names, loading announcements, action hints, state changes, date reading, timer units, and photo movement. Check largest Dynamic Type and narrow layouts for the longer consequence text.
5. If implementing, keep display titles separate from persisted enum raw values (notably grocery grouping/scope/category values). Existing preferences must survive casing/terminology changes. Use localizable plural forms rather than scattered English string branches as localization is introduced.
6. After app code changes, run `./scripts/run-sim.sh`, then `./scripts/run-device.sh` sequentially as required by AGENTS.md. The initial review needed no builds; the subsequent implementation uses these deployment scripts.
