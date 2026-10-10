# Legacy SiriKit plus the iOS 27 Reminders schema for spoken grocery add

"Add apples to Calendish" has to work in one sentence for any item, but App Shortcut phrases can't carry free text. So spoken groceries go through SiriKit's Lists domain (`INAddTasksIntent`) on iOS 26 and the Reminders app schema (`.reminders.createReminder`) on iOS 27, which deprecates the former. Both are handled in the app process, launched in the background, so they reuse the signed-in session instead of sharing it with an Intents extension. Calendish presents its one household grocery list as the only list, and each grocery as a reminder.

## Considered Options

- An App Shortcut with a prompt ("Add to Calendish" → "What do you want to add?") is kept for Shortcuts and Spotlight, but it takes two steps.
- A grocery-name entity in the phrase works in one sentence only for items the household has added before.

## Consequences

- SiriKit can't say "already on your list", so an item that's already there is reported as added. The list ends up correct either way.
- The exact sentences Siri routes to Calendish are Apple's to decide and need checking on a device. "Add apples to my groceries in Calendish" is an acceptable fallback.
