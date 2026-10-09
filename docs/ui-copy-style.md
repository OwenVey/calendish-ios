# Calendish interface language

Calendish sounds welcoming, practical, calm, and brief. Use warmth in welcome and completion moments. For errors, privacy, and deletion, lead with the action and consequence.

Use sentence case for app-owned titles, labels, and actions. Preserve proper names such as Calendish, Google, Live Activity, Lock Screen, and Dynamic Island. Keep stored enum values separate from display labels.

## Vocabulary

- **Household:** people sharing a grocery list and meal plan.
- **Personal recipe:** owned by a person; it can be private or shared with their household.
- **Only me:** visibility value. **Make private:** action. The household can retain a separate copy of a previously shared recipe.
- **Household recipe:** owned by the household rather than a person.
- **Plan a meal:** schedule a saved recipe. **New recipe:** write a recipe. **Import:** extract outside content into a draft. **Save:** add the reviewed draft to the collection.
- **Checked / Unchecked:** grocery checklist states. Use **Check off / Uncheck** for actions. Checking an item does not necessarily mean it was bought.
- **On list:** matches an unchecked grocery associated with that recipe. It does not verify the needed quantity or pantry stock.
- **Recipe note:** a member's cooking note, visible to household members who can access the recipe. **Meal-plan note:** a dated planning entry.
- **Marked cooked:** a recorded cook. **Planned:** a meal scheduled in the past; it does not establish that cooking happened. Combined history counts distinct days.
- **Saved recipe version:** ingredients and steps captured with a planned meal.
- **Voice commands:** the optional spoken-command feature in cook mode.
- **Timer finished / Cancel timer:** consistent timer state and action across app, speech, and system surfaces.

## Patterns

Use Continue between setup steps, a specific final action such as Join household, Save to commit edits, and Done to dismiss an informational or completed view. Destructive actions name their object and disclose effects on other household members.

Errors name the failed operation and an available next step. A missing response does not prove a write failed; use “Couldn’t confirm…” and tell the person to check current data before retrying. Keep raw service diagnostics out of interface copy.

Write singular and plural forms for dynamic values. Accessibility labels describe intent and state without repeating “button”. Explain loading actions explicitly. Instructions refer to actions or destinations instead of relying only on a plus icon.
