# Add spoken groceries through the iOS 27 Reminders schema

"Add apples to Calendish" has to work in one sentence for any item, but App Shortcut phrases can't carry free text. So spoken groceries go through the Reminders app schema (`.reminders.createReminder`), which needs iOS 27 and runs in the app process with the signed-in session. Calendish presents its one household grocery list as the only list, and each grocery as a reminder.

## Considered Options

- SiriKit's Lists domain (`INAddTasksIntent`) would also cover iOS 26, but Apple deprecated it in iOS 27, it doesn't reach the new Siri, and its Siri entitlement can't be signed by a personal development team. On iOS 26, people use the two-step shortcut instead.
- An App Shortcut with a prompt ("Add to Calendish" → "What do you want to add?") is kept for Shortcuts, Spotlight, and iOS 26, but it takes two steps.
- A grocery-name entity in the phrase works in one sentence only for items the household has added before.

## Consequences

- The exact sentences Siri routes to Calendish are Apple's to decide and need checking on a device. "Add apples to my groceries in Calendish" is an acceptable fallback.
